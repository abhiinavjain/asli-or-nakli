-- =====================================================================
-- Asli-or-Nakli · Phase 3 · mediator_db: federated context discovery
-- RUN ON: mediator_db, after the three sources ran asli_ctx_core.sql and
--         <source>_07_tables.sql.   Alt+X.  Safe to re-run.
-- =====================================================================
--
--  user query ──► p3_parse  ──► seeds (item codes, batch numbers, names, words)
--                    │
--                    ▼   round 1: the SAME sub-query goes to every source AT ONCE (dblink async)
--     manufacturer: asli_ctx.discover(seeds)   distributor: ...   vendor: ...
--         each source walks ITS OWN FK -> PK graph and returns ranked context rows
--                    │
--                    ▼   cross-database keys found in the answers (p3_links)
--                        e.g. distributor says "shipped to CityCare" -> vendor seed;
--                        vendor says "bought from distributor 1"   -> distributor seed
--                    ▼   round 2: only the NEW seeds, only to the source they point to
--                    ▼
--  p3_context (one row per context row, with round, source, FK path, relevance)
--
-- A source that is down or slow is skipped and logged; the answer is built from
-- the others (p3_source_calls shows what happened).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS dblink;

-- ---------------------------------------------------------------------
-- 1. Settings (match_config) and registry
-- ---------------------------------------------------------------------
INSERT INTO public.match_config (key, value, description) VALUES
    ('p3_rounds',          2,    'Phase 3: rounds of federated discovery (round 2 follows cross-database keys)'),
    ('p3_depth',           3,    'Phase 3: FK steps each source may walk from a seed'),
    ('p3_rows_per_source', 40,   'Phase 3: most context rows one source returns per round'),
    ('p3_seeds_per_kind',  5,    'Phase 3: most new seeds of one kind sent to one source in round 2'),
    ('p3_min_seed_weight', 0.25, 'Phase 3: a cross-database key must be at least this relevant to become a seed'),
    ('p3_timeout_ms',      8000, 'Phase 3: a source slower than this is skipped for the round'),
    ('p3_context_top',     60,   'Phase 3: context rows kept for the answer, most relevant first')
ON CONFLICT (key) DO NOTHING;

-- which foreign server reaches each registered source (step 6 registry)
CREATE TABLE IF NOT EXISTS public.p3_endpoints (
    source_id   text PRIMARY KEY REFERENCES public.asli_sources (source_id),
    server_name text NOT NULL,
    enabled     boolean NOT NULL DEFAULT true
);
INSERT INTO public.p3_endpoints (source_id, server_name)
SELECT s.source_id, lower(s.kind) || '_server' FROM public.asli_sources s
WHERE s.kind IN ('MANUFACTURER', 'DISTRIBUTOR', 'VENDOR')
  AND EXISTS (SELECT 1 FROM pg_foreign_server f WHERE f.srvname = lower(s.kind) || '_server')
ON CONFLICT (source_id) DO NOTHING;

-- cross-database keys: a value in one source's answer that is a seed for another
CREATE TABLE IF NOT EXISTS public.p3_links (
    source_kind  text NOT NULL,
    table_name   text NOT NULL,
    column_name  text NOT NULL,
    seed_kind    text NOT NULL,
    target_kinds text[] NOT NULL,
    weight       numeric NOT NULL DEFAULT 1,
    PRIMARY KEY (source_kind, table_name, column_name)
);
INSERT INTO public.p3_links VALUES
    ('MANUFACTURER', 'manufactured_items', 'unique_item_code', 'item_code',      '{DISTRIBUTOR,VENDOR}', 0.9),
    ('MANUFACTURER', 'medicines',          'medicine_name',    'medicine_name',  '{DISTRIBUTOR,VENDOR}', 0.5),
    ('DISTRIBUTOR',  'inventory_items',    'product_code',     'item_code',      '{MANUFACTURER,VENDOR}', 0.9),
    ('DISTRIBUTOR',  'supplied_items',     'vendor_reference', 'vendor_name',    '{VENDOR}', 0.8),
    ('DISTRIBUTOR',  'shipments',          'shop_name',        'vendor_name',    '{VENDOR}', 0.8),
    ('DISTRIBUTOR',  'distributors',       'distributor_id',   'distributor_id', '{VENDOR}', 0.6),
    ('VENDOR',       'vendor_inventory',   'item_identifier',  'item_code',      '{MANUFACTURER,DISTRIBUTOR}', 0.9),
    ('VENDOR',       'vendor_inventory',   'distributor_id',   'distributor_id', '{DISTRIBUTOR}', 0.7),
    ('VENDOR',       'purchase_invoices',  'distributor_id',   'distributor_id', '{DISTRIBUTOR}', 0.6),
    ('VENDOR',       'medicine_sales',     'item_identifier',  'item_code',      '{MANUFACTURER,DISTRIBUTOR}', 0.8),
    ('VENDOR',       'vendors',            'vendor_name',      'vendor_name',    '{DISTRIBUTOR}', 0.7)
ON CONFLICT (source_kind, table_name, column_name) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. Audit trail: every query, every source call, every context row
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.p3_queries (
    query_id    serial PRIMARY KEY,
    asked_at    timestamptz NOT NULL DEFAULT now(),
    query_text  text,
    fields      jsonb,
    seeds       jsonb,
    rounds_run  int,
    context_rows int,
    elapsed_ms  numeric
);

CREATE TABLE IF NOT EXISTS public.p3_source_calls (
    query_id  int  NOT NULL REFERENCES public.p3_queries (query_id) ON DELETE CASCADE,
    round     int  NOT NULL,
    source_id text NOT NULL,
    seeds     jsonb,
    rows_back int,
    elapsed_ms numeric,
    status    text NOT NULL,          -- OK / SKIPPED (no seeds) / ERROR / TIMEOUT
    error     text,
    PRIMARY KEY (query_id, round, source_id)
);

CREATE TABLE IF NOT EXISTS public.p3_context (
    query_id   int  NOT NULL REFERENCES public.p3_queries (query_id) ON DELETE CASCADE,
    round      int  NOT NULL,
    source_id  text NOT NULL,
    kind       text NOT NULL,
    db         text,
    table_name text NOT NULL,
    row_key    text NOT NULL,
    hop        int,
    path       text,
    seeds      text,
    relevance  numeric,
    row_data   jsonb,
    PRIMARY KEY (query_id, source_id, table_name, row_key)
);

-- ---------------------------------------------------------------------
-- 3. p3_parse: free text (+ optional structured fields) -> seeds
-- ---------------------------------------------------------------------
--   item codes   ITEM000041, ITEM0O0041, item-000202, ITM000174 ...   weight 1.0
--   batch no.    SUN-MED005-2603                                      weight 1.0
--   other words  ibuprofen, sunrise, citycare, crumbly ...            weight 0.7
--   fields       {"item_code": .., "medicine_name": .., "manufacturer_name": ..,
--                 "vendor_name": .., "distributor_name": .., "batch_no": ..}  weight 1.0 / 0.9
CREATE OR REPLACE FUNCTION public.p3_parse(p_text text, p_fields jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE sql STABLE AS $$
WITH t AS (SELECT coalesce(p_text, '') AS q),
codes AS (
    SELECT DISTINCT upper(m[1]) AS v FROM t,
           regexp_matches(t.q, '((?:[I1l][T7][E3]M|ITM|[I1l]TRM)[\s-]?[0-9A-Za-z]{3,8})', 'gi') m),
batches AS (
    SELECT DISTINCT upper(m[1]) AS v FROM t,
           regexp_matches(t.q, '\m([A-Za-z]{3}-[A-Za-z0-9]{3,14}-[0-9]{4})\M', 'g') m),
rest AS (   -- the text without codes and batch numbers
    SELECT regexp_replace(regexp_replace(t.q, '((?:[I1l][T7][E3]M|ITM|[I1l]TRM)[\s-]?[0-9A-Za-z]{3,8})', ' ', 'gi'),
                          '\m[A-Za-z]{3}-[A-Za-z0-9]{3,14}-[0-9]{4}\M', ' ', 'g') AS q FROM t),
words AS (
    SELECT DISTINCT w FROM rest, regexp_split_to_table(lower(rest.q), '[^a-z0-9]+') w
    WHERE length(w) >= 4
      AND w NOT IN ('what', 'which', 'where', 'when', 'from', 'with', 'this', 'that', 'there', 'their',
                    'have', 'has', 'been', 'were', 'does', 'doing', 'about', 'tell', 'show', 'give', 'find',
                    'into', 'than', 'then', 'they', 'them', 'your', 'mine', 'some', 'any', 'medicine', 'medicines',
                    'safe', 'sold', 'bought', 'item', 'items', 'pack', 'packs', 'shop', 'store', 'please', 'should',
                    'could', 'would', 'also', 'only', 'very', 'much', 'many', 'more', 'most', 'genuine', 'real',
                    'fake', 'check', 'know', 'batch', 'code', 'bill', 'want', 'need', 'information', 'details', 'everything', 'related')
      AND w !~ '^[0-9]+$'
      AND w !~ '^[0-9.]+(mg|g|mcg|ml|iu)$'),         -- a strength alone ("500mg") matches half the catalogue
f AS (
    SELECT key AS kind, value #>> '{}' AS v FROM jsonb_each(coalesce(p_fields, '{}'))
    WHERE nullif(btrim(value #>> '{}'), '') IS NOT NULL)
SELECT coalesce(jsonb_agg(DISTINCT s), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('kind', 'item_code', 'value', v, 'weight', 1.0) AS s FROM codes
    UNION ALL SELECT jsonb_build_object('kind', 'batch_no', 'value', v, 'weight', 1.0) FROM batches
    UNION ALL SELECT jsonb_build_object('kind', 'text', 'value', w, 'weight', 0.7) FROM words
    UNION ALL SELECT jsonb_build_object('kind', kind, 'value', v,
                                        'weight', CASE WHEN kind IN ('item_code', 'batch_no') THEN 1.0 ELSE 0.9 END) FROM f
) x
$$;

-- ---------------------------------------------------------------------
-- 4. p3_discover: the federated, multi-round context discovery
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.p3_discover(p_query_id int, p_seeds jsonb)
RETURNS int LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_rounds   int     := public.match_cfg('p3_rounds')::int;
    v_depth    int     := public.match_cfg('p3_depth')::int;
    v_rows     int     := public.match_cfg('p3_rows_per_source')::int;
    v_per_kind int     := public.match_cfg('p3_seeds_per_kind')::int;
    v_min_seed numeric := public.match_cfg('p3_min_seed_weight');
    v_timeout  int     := public.match_cfg('p3_timeout_ms')::int;
    r          int;
    ep         record;
    v_conn     text;
    v_seeds    jsonb;
    v_sent     text[];
    v_started  timestamptz;
    v_n        int;
    v_total    int := 0;
BEGIN
    -- seeds per source for this round
    IF to_regclass('pg_temp._p3_round_seeds') IS NOT NULL THEN DROP TABLE pg_temp._p3_round_seeds; END IF;
    CREATE TEMP TABLE _p3_round_seeds (source_id text PRIMARY KEY, seeds jsonb);
    INSERT INTO _p3_round_seeds SELECT e.source_id, p_seeds FROM public.p3_endpoints e
    JOIN public.asli_sources s USING (source_id) WHERE e.enabled AND s.enabled;
    -- seeds already sent to a source (never sent twice)
    IF to_regclass('pg_temp._p3_sent') IS NOT NULL THEN DROP TABLE pg_temp._p3_sent; END IF;
    CREATE TEMP TABLE _p3_sent (source_id text, kind text, value text, PRIMARY KEY (source_id, kind, value));
    INSERT INTO _p3_sent SELECT rs.source_id, x->>'kind', lower(x->>'value')
    FROM _p3_round_seeds rs, jsonb_array_elements(rs.seeds) x ON CONFLICT DO NOTHING;

    FOR r IN 1 .. v_rounds LOOP
        EXIT WHEN NOT EXISTS (SELECT 1 FROM _p3_round_seeds WHERE jsonb_array_length(seeds) > 0);
        v_sent := '{}';
        v_started := clock_timestamp();

        -- (a) send the sub-query to every source that has seeds, WITHOUT waiting
        FOR ep IN SELECT e.source_id, e.server_name, s.kind, rs.seeds
                  FROM public.p3_endpoints e
                  JOIN public.asli_sources s USING (source_id)
                  LEFT JOIN _p3_round_seeds rs USING (source_id)
                  WHERE e.enabled AND s.enabled ORDER BY e.source_id LOOP
            IF ep.seeds IS NULL OR jsonb_array_length(ep.seeds) = 0 THEN
                INSERT INTO public.p3_source_calls VALUES (p_query_id, r, ep.source_id, '[]', 0, 0, 'SKIPPED', 'no seeds for this source');
                CONTINUE;
            END IF;
            v_conn := 'p3_' || ep.source_id;
            BEGIN
                IF v_conn = ANY (coalesce(dblink_get_connections(), '{}')) THEN
                    -- a pooled connection from an earlier query: drop it if it is broken
                    IF dblink_error_message(v_conn) <> 'OK' THEN
                        PERFORM dblink_disconnect(v_conn);
                    END IF;
                END IF;
                IF NOT (v_conn = ANY (coalesce(dblink_get_connections(), '{}'))) THEN
                    PERFORM dblink_connect(v_conn, ep.server_name);
                END IF;
                PERFORM dblink_exec(v_conn, format('SET statement_timeout = %s', v_timeout));
                PERFORM dblink_send_query(v_conn,
                    format('SELECT * FROM asli_ctx.discover(%L::jsonb, %s, %s)', ep.seeds, v_depth, v_rows));
                v_sent := v_sent || ep.source_id;
            EXCEPTION WHEN OTHERS THEN
                INSERT INTO public.p3_source_calls VALUES (p_query_id, r, ep.source_id, ep.seeds, 0,
                    round(extract(epoch FROM clock_timestamp() - v_started) * 1000), 'ERROR', SQLERRM);
                BEGIN PERFORM dblink_disconnect(v_conn); EXCEPTION WHEN OTHERS THEN NULL; END;
            END;
        END LOOP;

        -- (b) collect the answers (the sources have been working in parallel)
        FOR ep IN SELECT e.source_id, s.kind, rs.seeds FROM public.p3_endpoints e
                  JOIN public.asli_sources s USING (source_id)
                  JOIN _p3_round_seeds rs USING (source_id)
                  WHERE e.source_id = ANY (v_sent) LOOP
            v_conn := 'p3_' || ep.source_id;
            BEGIN
                INSERT INTO public.p3_context
                SELECT p_query_id, r, ep.source_id, ep.kind, t.db, t.table_name, t.row_key, t.hop, t.path,
                       t.seeds, t.relevance, t.row_data
                FROM dblink_get_result(v_conn) AS t(db text, table_name text, row_key text, hop int, path text,
                                                    seeds text, relevance numeric, row_data jsonb)
                ON CONFLICT (query_id, source_id, table_name, row_key) DO UPDATE
                    SET relevance = greatest(p3_context.relevance, EXCLUDED.relevance),
                        seeds = p3_context.seeds || ' + ' || EXCLUDED.seeds;
                GET DIAGNOSTICS v_n = ROW_COUNT;
                PERFORM * FROM dblink_get_result(v_conn) AS t(db text);   -- end of result set
                v_total := v_total + v_n;
                INSERT INTO public.p3_source_calls VALUES (p_query_id, r, ep.source_id, ep.seeds, v_n,
                    round(extract(epoch FROM clock_timestamp() - v_started) * 1000), 'OK', NULL);
            EXCEPTION WHEN OTHERS THEN
                INSERT INTO public.p3_source_calls VALUES (p_query_id, r, ep.source_id, ep.seeds, 0,
                    round(extract(epoch FROM clock_timestamp() - v_started) * 1000),
                    CASE WHEN SQLERRM ILIKE '%statement timeout%' THEN 'TIMEOUT' ELSE 'ERROR' END, SQLERRM);
                BEGIN PERFORM dblink_disconnect(v_conn); EXCEPTION WHEN OTHERS THEN NULL; END;
            END;
        END LOOP;

        -- (c) cross-database keys in this round's answers become next round's seeds
        TRUNCATE _p3_round_seeds;
        INSERT INTO _p3_round_seeds
        SELECT target, jsonb_agg(jsonb_build_object('kind', seed_kind, 'value', val, 'weight', round(w, 3),
                                                    'derived', true))
        FROM (
            SELECT target, seed_kind, val, w,
                   row_number() OVER (PARTITION BY target, seed_kind ORDER BY w DESC, val) AS n
            FROM (
                SELECT e.source_id AS target, l.seed_kind, c.row_data ->> l.column_name AS val,
                       max(c.relevance * l.weight) AS w
                FROM public.p3_context c
                JOIN public.p3_links l ON l.source_kind = c.kind AND l.table_name = c.table_name
                JOIN public.asli_sources s ON s.kind = ANY (l.target_kinds)
                JOIN public.p3_endpoints e ON e.source_id = s.source_id AND e.enabled
                WHERE c.query_id = p_query_id AND c.round = r
                  AND nullif(btrim(c.row_data ->> l.column_name), '') IS NOT NULL
                GROUP BY 1, 2, 3
            ) cand
            WHERE w >= v_min_seed
              AND NOT EXISTS (SELECT 1 FROM _p3_sent ps
                              WHERE ps.source_id = cand.target AND ps.kind = cand.seed_kind AND ps.value = lower(cand.val))
        ) ranked
        WHERE n <= v_per_kind
        GROUP BY target;
        INSERT INTO _p3_sent SELECT rs.source_id, x->>'kind', lower(x->>'value')
        FROM _p3_round_seeds rs, jsonb_array_elements(rs.seeds) x ON CONFLICT DO NOTHING;
    END LOOP;

    UPDATE public.p3_queries SET rounds_run = (SELECT max(round) FROM public.p3_source_calls WHERE query_id = p_query_id)
    WHERE query_id = p_query_id;
    RETURN v_total;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. p3_run: the entry point the GUI calls. Returns the query id.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.p3_run(p_text text, p_fields jsonb DEFAULT '{}')
RETURNS int LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_id    int;
    v_seeds jsonb := public.p3_parse(p_text, p_fields);
    v_t0    timestamptz := clock_timestamp();
BEGIN
    INSERT INTO public.p3_queries (query_text, fields, seeds) VALUES (p_text, p_fields, v_seeds)
    RETURNING query_id INTO v_id;
    PERFORM public.p3_discover(v_id, v_seeds);
    UPDATE public.p3_queries
       SET context_rows = (SELECT count(*) FROM public.p3_context WHERE query_id = v_id),
           elapsed_ms   = round(extract(epoch FROM clock_timestamp() - v_t0) * 1000)
     WHERE query_id = v_id;
    RETURN v_id;
END;
$$;

-- the context of one query, most relevant first (round 2 rows already carry
-- the relevance of the key that led to them)
CREATE OR REPLACE FUNCTION public.p3_top_context(p_query_id int, p_limit int DEFAULT NULL)
RETURNS SETOF public.p3_context LANGUAGE sql STABLE AS $$
    SELECT * FROM public.p3_context WHERE query_id = p_query_id
    ORDER BY relevance DESC, round, hop, source_id, table_name, row_key
    LIMIT coalesce(p_limit, public.match_cfg('p3_context_top')::int)
$$;

-- ---------------------------------------------------------------------
-- 6. Context -> search terms for the unstructured documents
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.p3_term_columns (
    column_name text PRIMARY KEY,
    term_kind   text NOT NULL,
    weight      numeric NOT NULL
);
INSERT INTO public.p3_term_columns VALUES
    ('batch_no', 'batch_no', 1.2),
    ('unique_item_code', 'item_code', 0.9), ('product_code', 'item_code', 0.9), ('item_identifier', 'item_code', 0.9),
    ('medicine_name', 'medicine', 1.0), ('composition', 'medicine', 0.8), ('drug_name', 'medicine', 0.6),
    ('manufacturer_name', 'manufacturer', 1.0), ('mfr_name', 'manufacturer', 0.6), ('company', 'manufacturer', 0.6),
    ('vendor_name', 'shop', 0.8), ('shop_name', 'shop', 0.8), ('vendor_reference', 'shop', 0.6),
    ('distributor_name', 'distributor', 0.7),
    ('plant_name', 'plant', 0.5), ('city', 'place', 0.5), ('gmp_certificate', 'certificate', 0.6),
    ('test_name', 'qc_test', 0.4), ('vehicle_no', 'vehicle', 0.5)
ON CONFLICT (column_name) DO NOTHING;

CREATE OR REPLACE FUNCTION public.p3_context_terms(p_query_id int, p_limit int DEFAULT 25)
RETURNS TABLE (term text, term_kind text, weight numeric, found_in text)
LANGUAGE sql STABLE AS $$
    -- an item code is shown in its clean form when any source holds it that way
    SELECT (array_agg(v ORDER BY (k = 'item_code' AND v ~ '^ITEM[0-9]{6}$') DESC, (v <> upper(v)) DESC, w DESC))[1],
           (array_agg(k ORDER BY w DESC))[1], round(max(w), 3),
           string_agg(DISTINCT src, ', ')
    FROM (
        SELECT btrim(c.row_data ->> tc.column_name) AS v, tc.term_kind AS k,
               c.relevance * tc.weight AS w, c.source_id || '.' || c.table_name AS src
        FROM public.p3_top_context(p_query_id) c
        JOIN public.p3_term_columns tc ON c.row_data ? tc.column_name
        WHERE nullif(btrim(c.row_data ->> tc.column_name), '') IS NOT NULL
          AND (tc.term_kind <> 'qc_test' OR c.row_data ->> 'result' = 'FAIL')
    ) x
    GROUP BY lower(CASE WHEN k = 'item_code' THEN asli.fold(v) ELSE v END)
    ORDER BY 3 DESC
    LIMIT p_limit
$$;

-- ---------------------------------------------------------------------
-- 7. Risk signals found in the context (rules are data, not code)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.p3_signal_rules (
    rule_id     text PRIMARY KEY,
    source_kind text NOT NULL,
    table_name  text NOT NULL,
    condition   text NOT NULL,      -- SQL on r (the row as jsonb)
    severity    int  NOT NULL CHECK (severity BETWEEN 1 AND 3),   -- 1 info, 2 warning, 3 serious
    message     text NOT NULL       -- SQL expression on r
);
INSERT INTO public.p3_signal_rules VALUES
    ('QC_FAIL', 'MANUFACTURER', 'qc_reports', $$r->>'result' = 'FAIL'$$, 3,
     $$'QC ' || (r->>'test_name') || ' failed (' || coalesce(r->>'measured_value', '?') || ', spec ' || coalesce(r->>'spec_range', '?') || '): ' || coalesce(r->>'remarks', '')$$),
    ('BATCH_STATUS', 'MANUFACTURER', 'production_batches', $$r->>'release_status' <> 'RELEASED'$$, 2,
     $$'Batch ' || (r->>'batch_no') || ' status: ' || (r->>'release_status')$$),
    ('GMP_EXPIRED', 'MANUFACTURER', 'plants', $$(r->>'gmp_valid_until')::date < CURRENT_DATE$$, 3,
     $$'Plant ' || (r->>'plant_name') || ' GMP certificate ' || (r->>'gmp_certificate') || ' expired on ' || (r->>'gmp_valid_until')$$),
    ('TEMP_EXCURSION', 'DISTRIBUTOR', 'temperature_logs', $$(r->>'temp_c')::numeric > 25$$, 3,
     $$'Transport at ' || (r->>'temp_c') || ' °C on ' || left(r->>'logged_at', 10) || ': ' || coalesce(r->>'note', '')$$),
    ('TRANSPORT_NOTE', 'DISTRIBUTOR', 'temperature_logs', $$(r->>'temp_c')::numeric <= 25 AND nullif(r->>'note', '') IS NOT NULL$$, 2,
     $$'Transport note ' || left(r->>'logged_at', 10) || ': ' || (r->>'note')$$),
    ('COMPLAINT', 'VENDOR', 'customer_complaints', $$r->>'status' <> 'CLOSED' OR r->>'complaint_text' ~* '(fake|hologram|altered|crumbl|sticky|leak|blurred|different)'$$, 2,
     $$'Customer complaint (' || (r->>'reported_on') || ', ' || (r->>'status') || '): ' || (r->>'complaint_text')$$)
ON CONFLICT (rule_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.p3_signals(p_query_id int)
RETURNS TABLE (rule_id text, severity int, source_id text, table_name text, row_key text,
               relevance numeric, message text, path text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    rr record;
BEGIN
    FOR rr IN SELECT * FROM public.p3_signal_rules LOOP
        RETURN QUERY EXECUTE format(
            'SELECT %L::text, %s, c.source_id, c.table_name, c.row_key, c.relevance, (%s)::text, c.path
             FROM public.p3_top_context($1) c, LATERAL (SELECT c.row_data AS r) x
             WHERE c.kind = %L AND c.table_name = %L AND (%s)',
            rr.rule_id, rr.severity, rr.message, rr.source_kind, rr.table_name, rr.condition)
        USING p_query_id;
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------
-- 8. The FK graph of every source, read live from each machine (GUI + viva)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.p3_source_schemas()
RETURNS TABLE (source_id text, kind text, child_table text, child_column text,
               parent_table text, parent_column text, fk_name text)
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    ep record;
BEGIN
    FOR ep IN SELECT e.source_id, e.server_name, s.kind FROM public.p3_endpoints e
              JOIN public.asli_sources s USING (source_id) WHERE e.enabled ORDER BY 1 LOOP
        BEGIN
            RETURN QUERY
            SELECT ep.source_id, ep.kind, t.child_table, t.child_column, t.parent_table, t.parent_column, t.fk_name
            FROM dblink(ep.server_name,
                        'SELECT child_table, child_column, parent_table, parent_column, fk_name FROM asli_ctx.fk_edges')
                 AS t(child_table text, child_column text, parent_table text, parent_column text, fk_name text);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'source % did not answer: %', ep.source_id, SQLERRM;
        END;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.p3_source_tables()
RETURNS TABLE (source_id text, kind text, table_name text, role text, label text, fk_links bigint)
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    ep record;
BEGIN
    FOR ep IN SELECT e.source_id, e.server_name, s.kind FROM public.p3_endpoints e
              JOIN public.asli_sources s USING (source_id) WHERE e.enabled ORDER BY 1 LOOP
        BEGIN
            RETURN QUERY
            SELECT ep.source_id, ep.kind, t.table_name, t.role, t.label, t.fk_links
            FROM dblink(ep.server_name, 'SELECT table_name, role, label, fk_links FROM asli_ctx.v_schema')
                 AS t(table_name text, role text, label text, fk_links bigint);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'source % did not answer: %', ep.source_id, SQLERRM;
        END;
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------
-- Checks
-- ---------------------------------------------------------------------
WITH t AS (
    SELECT 1 AS n, 'dblink installed' AS test,
           (EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'dblink'))::text AS got, 'true' AS expected
    UNION ALL
    SELECT 2, 'every source has 5+ tables',
           (SELECT bool_and(c >= 5)::text FROM (SELECT source_id, count(*) c FROM public.p3_source_tables() GROUP BY 1) x), 'true'
    UNION ALL
    SELECT 3, 'every source has FK -> PK links',
           (SELECT (count(DISTINCT source_id) = (SELECT count(*) FROM public.p3_endpoints WHERE enabled))::text
            FROM public.p3_source_schemas()), 'true'
    UNION ALL
    SELECT 4, 'parse finds code, batch and words',
           (SELECT string_agg(DISTINCT x->>'kind', ',' ORDER BY x->>'kind')
            FROM jsonb_array_elements(public.p3_parse('ITEM0O0041 batch SUN-MED005-2603 ibuprofen')) x), 'batch_no,item_code,text'
)
SELECT test, CASE WHEN got = expected THEN 'PASS' ELSE 'FAIL (got ' || coalesce(got, 'nothing') || ')' END AS result
FROM t ORDER BY n;
