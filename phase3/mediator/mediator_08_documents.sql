-- =====================================================================
-- Asli-or-Nakli · Phase 3 · mediator_db: unstructured documents + hybrid search
-- RUN ON: mediator_db, after mediator_07_federated_context.sql.  Alt+X.  Safe to re-run.
-- Then load / refresh the documents with:  python app/phase3_index_documents.py
-- =====================================================================
--
-- Documents from outside the three databases: regulator alerts, recall notices,
-- package inserts, inspection reports, news, consumer posts. Origin REAL (a
-- public source, summarised, with its URL) or SYNTHETIC (fictional, made for
-- the demo, always marked [Demo]).
--
-- Search = the QUERY CONTEXT, not just the user's words:
--   terms     the names, batch numbers, item codes, shops ... that the federated
--             discovery found (p3_context_terms), each with its relevance
--   lexical   sum over terms of  weight x ts_rank_cd(document, term)  (full-text, GIN)
--   semantic  cosine(document embedding, embedding of query + context)  (optional)
--   entities  exact mentions of a batch number / item code / shop / maker found in
--             the context: strong evidence that the document is about THIS case
--   score     0.55 x lexical/(lexical+0.5)  +  0.30 x cosine  +  0.15 per entity mention (max 3),
--             capped at 1; absolute, so a weak match stays weak even when it ranks first
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.p3_documents (
    doc_id          serial PRIMARY KEY,
    doc_key         text NOT NULL UNIQUE,
    doc_type        text NOT NULL,
    origin          text NOT NULL CHECK (origin IN ('REAL', 'SYNTHETIC')),
    title           text NOT NULL,
    issuer          text,
    published_on    date,
    url             text,
    body            text NOT NULL,
    tsv             tsvector GENERATED ALWAYS AS (
                        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
                        setweight(to_tsvector('english', coalesce(body, '')), 'B')) STORED,
    embedding       real[],          -- written by phase3_index_documents.py
    embedding_model text,
    loaded_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS p3_documents_tsv ON public.p3_documents USING gin (tsv);

INSERT INTO public.match_config (key, value, description) VALUES
    ('p3_doc_terms',   25,   'Phase 3: context terms used to search the documents'),
    ('p3_doc_pool',    40,   'Phase 3: candidate documents per retriever (lexical, semantic) before fusion'),
    ('p3_w_lexical',   0.55, 'Phase 3: weight of the (saturated) full-text score in the document score'),
    ('p3_w_semantic',  0.30, 'Phase 3: weight of the embedding cosine in the document score'),
    ('p3_min_doc_score', 0.30, 'Phase 3: documents scoring below this are not shown'),
    ('p3_entity_bonus', 0.15, 'Phase 3: score added per exact mention of a context entity (max 3)'),
    ('p3_min_semantic', 0.20, 'Phase 3: semantic matches below this cosine are ignored')
ON CONFLICT (key) DO NOTHING;

-- cosine similarity of two embeddings stored as real[]
-- (for millions of documents: pgvector with an HNSW index replaces this; the
--  search function below is the only place that would change)
CREATE OR REPLACE FUNCTION public.p3_cosine(a real[], b real[]) RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN a IS NULL OR b IS NULL OR array_length(a, 1) <> array_length(b, 1) THEN NULL
                ELSE sum(x * y) / nullif(sqrt(sum(x * x)) * sqrt(sum(y * y)), 0) END
    FROM unnest(a, b) AS t(x, y)
$$;

DROP FUNCTION IF EXISTS public.p3_search_documents(int, text, real[], int);
CREATE FUNCTION public.p3_search_documents(p_query_id int, p_query_text text,
                                           p_query_vec real[] DEFAULT NULL, p_k int DEFAULT 8)
RETURNS TABLE (doc_id int, doc_key text, doc_type text, origin text, title text, issuer text,
               published_on date, url text,
               lexical numeric, semantic numeric, entity_hits text[], score numeric,
               lexical_rank int, semantic_rank int, headline text)
LANGUAGE sql STABLE AS $$
WITH ctx AS (
    SELECT term, term_kind, weight FROM public.p3_context_terms(p_query_id, public.match_cfg('p3_doc_terms')::int)
),
terms AS (
    -- the context terms + the user's own words (the free-text seeds p3_parse kept)
    SELECT term, term_kind, weight FROM ctx
    UNION ALL
    -- the generic name of each medicine ("Paracetamol 500mg" -> "paracetamol"):
    -- outside documents rarely repeat our exact strength / pack wording
    (SELECT DISTINCT ON (lower(split_part(term, ' ', 1)))
            split_part(term, ' ', 1), 'generic', weight * 0.8
     FROM ctx
     WHERE term_kind = 'medicine' AND position(' ' IN term) > 0 AND length(split_part(term, ' ', 1)) >= 4
     ORDER BY lower(split_part(term, ' ', 1)), weight DESC)
    UNION ALL
    SELECT x->>'value', 'query', (x->>'weight')::numeric
    FROM public.p3_queries q, jsonb_array_elements(q.seeds) x
    WHERE q.query_id = p_query_id AND x->>'kind' = 'text'
),
tq AS (
    SELECT t.term, t.term_kind, t.weight, plainto_tsquery('english', t.term) AS q
    FROM terms t WHERE plainto_tsquery('english', t.term)::text <> ''
),
anyq AS (   -- OR of every term, for the index scan
    SELECT string_agg('(' || q::text || ')', ' | ')::tsquery AS q FROM tq
),
lex AS (
    SELECT d.doc_id,
           sum(tq.weight * ts_rank_cd(d.tsv, tq.q, 32)) AS s
    FROM public.p3_documents d, anyq, tq
    WHERE d.tsv @@ anyq.q
    GROUP BY d.doc_id
    ORDER BY s DESC LIMIT public.match_cfg('p3_doc_pool')::int
),
sem AS (
    SELECT d.doc_id, public.p3_cosine(d.embedding, p_query_vec) AS s
    FROM public.p3_documents d
    WHERE p_query_vec IS NOT NULL AND d.embedding IS NOT NULL
      AND public.p3_cosine(d.embedding, p_query_vec) >= public.match_cfg('p3_min_semantic')
    ORDER BY s DESC LIMIT public.match_cfg('p3_doc_pool')::int
),
ranked AS (
    SELECT coalesce(l.doc_id, s.doc_id) AS doc_id, l.s AS lex_s, s.s AS sem_s,
           rank() OVER (ORDER BY l.s DESC NULLS LAST)::int AS lr,
           rank() OVER (ORDER BY s.s DESC NULLS LAST)::int AS sr
    FROM lex l FULL JOIN sem s ON s.doc_id = l.doc_id
),
ent AS (    -- exact mentions of the case's own entities
    SELECT r.doc_id, array_agg(DISTINCT t.term ORDER BY t.term) AS hits
    FROM ranked r
    JOIN public.p3_documents d ON d.doc_id = r.doc_id
    JOIN terms t ON t.term_kind IN ('batch_no', 'item_code', 'shop', 'manufacturer', 'plant', 'certificate', 'vehicle')
                AND position(lower(t.term) IN lower(d.title || ' ' || d.body)) > 0
    GROUP BY r.doc_id
)
SELECT d.doc_id, d.doc_key, d.doc_type, d.origin, d.title, d.issuer, d.published_on, d.url,
       round(r.lex_s::numeric, 4), round(r.sem_s::numeric, 4), e.hits,
       -- fusion: saturating lexical score + semantic cosine + exact entity mentions
       round(least(1.0, public.match_cfg('p3_w_lexical')  * coalesce(r.lex_s / (r.lex_s + 0.5), 0)
                      + public.match_cfg('p3_w_semantic') * greatest(coalesce(r.sem_s, 0), 0)
                      + least(coalesce(array_length(e.hits, 1), 0), 3) * public.match_cfg('p3_entity_bonus'))::numeric, 4) AS score,
       CASE WHEN r.lex_s IS NOT NULL THEN r.lr END,
       CASE WHEN r.sem_s IS NOT NULL THEN r.sr END,
       ts_headline('english', d.body, (SELECT q FROM anyq),
                   'MaxFragments=2, MaxWords=22, MinWords=8, StartSel=**, StopSel=**')
FROM ranked r
JOIN public.p3_documents d ON d.doc_id = r.doc_id
LEFT JOIN ent e ON e.doc_id = r.doc_id
WHERE least(1.0, public.match_cfg('p3_w_lexical')  * coalesce(r.lex_s / (r.lex_s + 0.5), 0)
               + public.match_cfg('p3_w_semantic') * greatest(coalesce(r.sem_s, 0), 0)
               + least(coalesce(array_length(e.hits, 1), 0), 3) * public.match_cfg('p3_entity_bonus'))
      >= public.match_cfg('p3_min_doc_score')
ORDER BY score DESC, d.published_on DESC NULLS LAST
LIMIT p_k
$$;
