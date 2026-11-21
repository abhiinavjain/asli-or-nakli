-- =====================================================================
-- Asli-or-Nakli · Phase 2 refactor, step 6 · RUN ON: mediator_db (DBeaver: Alt+X)
--
-- The mediator stops reading whole tables. Each source finds its own top-k
-- candidates with an index (asli_match extension + expression indexes, already
-- added by the *_06_candidate_indexes.sql scripts on the three sources) and the
-- mediator only compares the few tuples that come back.
--
-- Run order:  sources: *_06_candidate_indexes.sql   ->   THIS script
--             -> step3/mediator_03_candidate_search.sql -> step5_cleansing/mediator_05_cleansing.sql
-- No existing table, column or constraint is changed; new mediator tables only.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. The same extension on the mediator, and permission for postgres_fdw to
--    send its functions to each source (so WHERE / ORDER BY / LIMIT run there)
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS asli_match;

DO $$
DECLARE s text;
BEGIN
    FOR s IN SELECT srvname FROM pg_foreign_server
             WHERE srvname IN ('manufacturer_server', 'distributor_server', 'vendor_server') LOOP
        IF EXISTS (SELECT 1 FROM pg_foreign_server f, unnest(f.srvoptions) o
                   WHERE f.srvname = s AND o LIKE 'extensions=%') THEN
            EXECUTE format('ALTER SERVER %I OPTIONS (SET extensions %L)', s, 'asli_match');
        ELSE
            EXECUTE format('ALTER SERVER %I OPTIONS (ADD extensions %L)', s, 'asli_match');
        END IF;
        -- ask the source for its own row estimates, so the planner sees that running
        -- the join, ORDER BY and LIMIT at the source is cheaper than shipping rows
        IF EXISTS (SELECT 1 FROM pg_foreign_server f, unnest(f.srvoptions) o
                   WHERE f.srvname = s AND o LIKE 'use_remote_estimate=%') THEN
            EXECUTE format('ALTER SERVER %I OPTIONS (SET use_remote_estimate %L)', s, 'true');
        ELSE
            EXECUTE format('ALTER SERVER %I OPTIONS (ADD use_remote_estimate %L)', s, 'true');
        END IF;
        -- rows per network round trip: where a LIMIT stays in the mediator, the
        -- source still sends at most this many rows before the cursor is closed
        IF EXISTS (SELECT 1 FROM pg_foreign_server f, unnest(f.srvoptions) o
                   WHERE f.srvname = s AND o LIKE 'fetch_size=%') THEN
            EXECUTE format('ALTER SERVER %I OPTIONS (SET fetch_size %L)', s, '25');
        ELSE
            EXECUTE format('ALTER SERVER %I OPTIONS (ADD fetch_size %L)', s, '25');
        END IF;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 2. New settings (editable in the Matching settings tab)
-- ---------------------------------------------------------------------
INSERT INTO public.match_config (key, value, description) VALUES ('probe_k', 5, 'Candidates each source returns per pass (top k)') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('probe_k_reverse', 20, 'Candidates per source when looking for the noisy records of one item') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('context_pass_above', 1.0, 'Ask a source for context matches only when its nearest code is further than this') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('discrimination_floor', 0.2, 'Lowest share of its weight an attribute keeps when it cannot tell the candidates apart') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('reliability_prior', 0.9, 'Reliability assumed for a source or attribute with no history yet') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('reliability_strength', 10, 'How many checked records the prior counts as') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('beta_entity', 0.25, 'Trust score: weight of entity (code) similarity') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('beta_context', 0.25, 'Trust score: weight of context similarity to the buyer''s pack') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('beta_consistency', 0.20, 'Trust score: weight of agreement with the other records of the item') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('beta_source', 0.10, 'Trust score: weight of source reliability') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('beta_attribute', 0.10, 'Trust score: weight of attribute reliability') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('beta_completeness', 0.10, 'Trust score: weight of completeness') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('trust_accept', 0.75, 'Trust score the most reliable record needs to be accepted') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('trust_margin', 0.05, 'How far the most reliable record must be ahead of the next') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('vote_accept_share', 0.6, 'Cleansing: share of the reliability-weighted support a value needs to win') ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------
-- 3. The candidate tuple every source returns, whatever its own column names
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.asli_probe(text, text, text, text[], text[], int);
DROP TYPE IF EXISTS public.asli_candidate;
CREATE TYPE public.asli_candidate AS (
    source_id      text,     -- registry id of the source
    kind           text,     -- MANUFACTURER / DISTRIBUTOR / VENDOR
    record_id      int,      -- row key in the source (item_id or inventory_id)
    stored_code    text,
    name           text,
    composition    text,
    company        text,
    mfg            text,     -- as stored (vendor: MM/YYYY text)
    expiry         text,
    mfg_date       date,     -- parsed
    exp_date       date,
    distributor_id int,
    vendor_id      int,
    vendor_name    text,
    medicine_code  text,
    received_date  date,
    supplied_to    text,     -- distributor: the shop it supplied this item to
    hit            text,     -- which pass found it: code / fold / context
    pre_dist       numeric   -- code distance computed at the source
);

-- ---------------------------------------------------------------------
-- 4. Source registry. One row per source database. A new source = one INSERT
--    (its probe in the same shape) + its indexes; no function changes.
--    Probe parameters: $1 code keys, $2 folded codes to look up exactly,
--    $3 typed code, $4 name sound key, $5 expiry month, $6 k.
--    Three passes, each pushed down to the source with its own LIMIT:
--      code    : shares a blocking key with the typed code, nearest k
--      fold    : folded code is one of $2 (exact lookups)
--      context : same medicine sound key and expiry month, nearest k
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.asli_sources (
    source_id   text PRIMARY KEY,
    kind        text NOT NULL CHECK (kind IN ('MANUFACTURER', 'DISTRIBUTOR', 'VENDOR')),
    enabled     boolean NOT NULL DEFAULT true,
    description text,
    probe_sql   text NOT NULL
);

INSERT INTO public.asli_sources (source_id, kind, description, probe_sql) VALUES ('manufacturer', 'MANUFACTURER', 'manuf_db via manufacturer_server', $q$
(SELECT 'manufacturer'::text, 'MANUFACTURER'::text, mi.item_id, mi.unique_item_code::text, md.medicine_name::text, md.composition::text,
        mf.manufacturer_name::text, mi.manufacturing_date::text, mi.expiry_date::text, mi.manufacturing_date, mi.expiry_date,
        NULL::int, NULL::int, NULL::text, mi.medicine_code::text, NULL::date, NULL::text, 'code'::text, asli.dist(mi.unique_item_code, $3)
 FROM public.manufactured_items mi
 JOIN public.medicines md ON md.medicine_code = mi.medicine_code
 JOIN public.manufacturers mf ON mf.manufacturer_id = md.manufacturer_id
 WHERE asli.keys(mi.unique_item_code) && $1
 ORDER BY asli.dist(mi.unique_item_code, $3), mi.unique_item_code LIMIT $6)
UNION ALL
(SELECT 'manufacturer', 'MANUFACTURER', mi.item_id, mi.unique_item_code::text, md.medicine_name::text, md.composition::text,
        mf.manufacturer_name::text, mi.manufacturing_date::text, mi.expiry_date::text, mi.manufacturing_date, mi.expiry_date,
        NULL::int, NULL::int, NULL::text, mi.medicine_code::text, NULL::date, NULL::text, 'fold', asli.dist(mi.unique_item_code, $3)
 FROM public.manufactured_items mi
 JOIN public.medicines md ON md.medicine_code = mi.medicine_code
 JOIN public.manufacturers mf ON mf.manufacturer_id = md.manufacturer_id
 WHERE asli.fold(mi.unique_item_code) = ANY ($2))
UNION ALL
(SELECT 'manufacturer', 'MANUFACTURER', mi.item_id, mi.unique_item_code::text, md.medicine_name::text, md.composition::text,
        mf.manufacturer_name::text, mi.manufacturing_date::text, mi.expiry_date::text, mi.manufacturing_date, mi.expiry_date,
        NULL::int, NULL::int, NULL::text, mi.medicine_code::text, NULL::date, NULL::text, 'context', asli.dist(mi.unique_item_code, $3)
 FROM public.manufactured_items mi
 JOIN public.medicines md ON md.medicine_code = mi.medicine_code
 JOIN public.manufacturers mf ON mf.manufacturer_id = md.manufacturer_id
 WHERE asli.name_key(md.medicine_name) = $4 AND asli.month_key(mi.expiry_date) = $5
 ORDER BY asli.dist(mi.unique_item_code, $3), mi.unique_item_code LIMIT $6)
$q$) ON CONFLICT (source_id) DO UPDATE SET probe_sql = EXCLUDED.probe_sql, kind = EXCLUDED.kind, description = EXCLUDED.description;

INSERT INTO public.asli_sources (source_id, kind, description, probe_sql) VALUES ('distributor', 'DISTRIBUTOR', 'distributor_db via distributor_server', $q$
(SELECT 'distributor'::text, 'DISTRIBUTOR'::text, d.inventory_id, d.product_code::text, d.drug_name::text, NULL::text,
        d.mfr_name::text, d.mfg_date::text, d.exp_date::text, d.mfg_date, d.exp_date,
        d.distributor_id, NULL::int, NULL::text, NULL::text, d.received_date, s.vendor_reference::text, 'code'::text, asli.dist(d.product_code, $3)
 FROM public.inventory_items d LEFT JOIN public.supplied_items s ON s.product_code = d.product_code
 WHERE asli.keys(d.product_code) && $1
 ORDER BY asli.dist(d.product_code, $3), d.product_code LIMIT $6)
UNION ALL
(SELECT 'distributor', 'DISTRIBUTOR', d.inventory_id, d.product_code::text, d.drug_name::text, NULL::text,
        d.mfr_name::text, d.mfg_date::text, d.exp_date::text, d.mfg_date, d.exp_date,
        d.distributor_id, NULL::int, NULL::text, NULL::text, d.received_date, s.vendor_reference::text, 'fold', asli.dist(d.product_code, $3)
 FROM public.inventory_items d LEFT JOIN public.supplied_items s ON s.product_code = d.product_code
 WHERE asli.fold(d.product_code) = ANY ($2))
UNION ALL
(SELECT 'distributor', 'DISTRIBUTOR', d.inventory_id, d.product_code::text, d.drug_name::text, NULL::text,
        d.mfr_name::text, d.mfg_date::text, d.exp_date::text, d.mfg_date, d.exp_date,
        d.distributor_id, NULL::int, NULL::text, NULL::text, d.received_date, s.vendor_reference::text, 'context', asli.dist(d.product_code, $3)
 FROM public.inventory_items d LEFT JOIN public.supplied_items s ON s.product_code = d.product_code
 WHERE asli.name_key(d.drug_name) = $4 AND asli.month_key(d.exp_date) = $5
 ORDER BY asli.dist(d.product_code, $3), d.product_code LIMIT $6)
$q$) ON CONFLICT (source_id) DO UPDATE SET probe_sql = EXCLUDED.probe_sql, kind = EXCLUDED.kind, description = EXCLUDED.description;

INSERT INTO public.asli_sources (source_id, kind, description, probe_sql) VALUES ('vendor', 'VENDOR', 'vendor_db via vendor_server', $q$
(SELECT 'vendor'::text, 'VENDOR'::text, v.inventory_id, v.item_identifier::text, v.medicine_name::text, NULL::text,
        v.company::text, v.mfg::text, v.expiry::text, asli.parse_date(v.mfg), asli.parse_date(v.expiry),
        v.distributor_id, v.vendor_id, w.vendor_name::text, NULL::text, v.received_date, NULL::text, 'code'::text, asli.dist(v.item_identifier, $3)
 FROM public.vendor_inventory v LEFT JOIN public.vendors w ON w.vendor_id = v.vendor_id
 WHERE asli.keys(v.item_identifier) && $1
 ORDER BY asli.dist(v.item_identifier, $3), v.item_identifier LIMIT $6)
UNION ALL
(SELECT 'vendor', 'VENDOR', v.inventory_id, v.item_identifier::text, v.medicine_name::text, NULL::text,
        v.company::text, v.mfg::text, v.expiry::text, asli.parse_date(v.mfg), asli.parse_date(v.expiry),
        v.distributor_id, v.vendor_id, w.vendor_name::text, NULL::text, v.received_date, NULL::text, 'fold', asli.dist(v.item_identifier, $3)
 FROM public.vendor_inventory v LEFT JOIN public.vendors w ON w.vendor_id = v.vendor_id
 WHERE asli.fold(v.item_identifier) = ANY ($2))
UNION ALL
(SELECT 'vendor', 'VENDOR', v.inventory_id, v.item_identifier::text, v.medicine_name::text, NULL::text,
        v.company::text, v.mfg::text, v.expiry::text, asli.parse_date(v.mfg), asli.parse_date(v.expiry),
        v.distributor_id, v.vendor_id, w.vendor_name::text, NULL::text, v.received_date, NULL::text, 'context', asli.dist(v.item_identifier, $3)
 FROM public.vendor_inventory v LEFT JOIN public.vendors w ON w.vendor_id = v.vendor_id
 WHERE asli.name_key(v.medicine_name) = $4 AND asli.month_key(v.expiry) = $5
 ORDER BY asli.dist(v.item_identifier, $3), v.item_identifier LIMIT $6)
$q$) ON CONFLICT (source_id) DO UPDATE SET probe_sql = EXCLUDED.probe_sql, kind = EXCLUDED.kind, description = EXCLUDED.description;

-- ---------------------------------------------------------------------
-- 5. asli_probe: ask the registered sources for candidates.
--    p_code   typed / stored code (NULL = no code pass)
--    p_name, p_expiry  context for the context pass (both needed)
--    p_kinds  which kinds of source to ask (NULL = all)
--    p_folds  extra codes to look up exactly (folded)
--    A source that fails is skipped with a warning: the decision is made on what
--    came back, and the evidence from that source is simply missing.
-- ---------------------------------------------------------------------
CREATE FUNCTION public.asli_probe(
    p_code   text,
    p_name   text   DEFAULT NULL,
    p_expiry text   DEFAULT NULL,
    p_kinds  text[] DEFAULT NULL,
    p_folds  text[] DEFAULT '{}',
    p_k      int    DEFAULT NULL)
RETURNS SETOF public.asli_candidate
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_keys  text[] := CASE WHEN nullif(btrim(p_code), '') IS NULL THEN '{}'::text[] ELSE asli.keys(p_code) END;
    v_folds text[];
    v_name  text   := asli.name_key(nullif(btrim(p_name), ''));
    v_month int    := asli.month_key(nullif(btrim(p_expiry), ''));
    v_k     int    := coalesce(p_k, public.match_cfg('probe_k')::int, 5);
    v_sort  text   := current_setting('enable_sort');
    v_sql   text;
    v_best  numeric;
    v_seen  int[];
    v_fits  boolean;
    c       public.asli_candidate;
    s       record;
BEGIN
    -- never sort candidates in the mediator: with local sorting off, the planner
    -- sends ORDER BY ... LIMIT k to the source, so only k rows per pass come back
    PERFORM set_config('enable_sort', 'off', true);
    SELECT coalesce(array_agg(DISTINCT f), '{}') INTO v_folds
    FROM unnest(coalesce(p_folds, '{}') || CASE WHEN nullif(btrim(p_code), '') IS NULL THEN '{}'::text[]
                                                ELSE ARRAY[asli.fold(p_code)] END) f
    WHERE f IS NOT NULL AND f <> '';
    IF v_name IS NULL OR v_month IS NULL THEN v_name := NULL; v_month := NULL; END IF;

    FOR s IN SELECT * FROM public.asli_sources
             WHERE enabled AND (p_kinds IS NULL OR kind = ANY (p_kinds)) ORDER BY source_id LOOP
        BEGIN
            v_sql := 'SELECT DISTINCT ON (q.record_id) q.* FROM (' || s.probe_sql || ') q(source_id, kind, record_id, stored_code, name, '
                || 'composition, company, mfg, expiry, mfg_date, exp_date, distributor_id, vendor_id, vendor_name, '
                || 'medicine_code, received_date, supplied_to, hit, pre_dist) '
                || 'ORDER BY q.record_id, CASE q.hit WHEN ''fold'' THEN 0 WHEN ''code'' THEN 1 ELSE 2 END';
            -- 1st round: code and folded-code passes only
            v_best := NULL; v_seen := '{}'; v_fits := false;
            FOR c IN EXECUTE v_sql USING v_keys, v_folds, coalesce(p_code, ''), NULL::text, NULL::int, v_k LOOP
                v_best := LEAST(coalesce(v_best, c.pre_dist), c.pre_dist);
                v_seen := v_seen || c.record_id;
                v_fits := v_fits OR (asli.name_key(c.name) = v_name AND asli.month_key(c.exp_date) = v_month);
                RETURN NEXT c;
            END LOOP;
            -- 2nd round, the context pass (same medicine sound key + expiry month),
            -- only when it can add something: no code close enough, or none of the
            -- close codes fits the pack (a real code on the wrong medicine)
            IF v_name IS NOT NULL
               AND (NOT v_fits OR v_best IS NULL
                    OR v_best > coalesce(public.match_cfg('context_pass_above'), 1.0)) THEN
                FOR c IN EXECUTE v_sql USING '{}'::text[], '{}'::text[], coalesce(p_code, ''), v_name, v_month, v_k LOOP
                    IF NOT c.record_id = ANY (v_seen) THEN RETURN NEXT c; END IF;
                END LOOP;
            END IF;
        EXCEPTION WHEN others THEN
            RAISE WARNING 'source % did not answer: %', s.source_id, SQLERRM;
        END;
    END LOOP;
    PERFORM set_config('enable_sort', v_sort, true);
END;
$$;

-- ---------------------------------------------------------------------
-- 6. Reliability, learned from the cleansing history.
--    reliability = (prior * strength + confirmed) / (strength + checked)
--    no history  -> the prior (0.9) for everyone, so nobody is trusted or
--    distrusted before there is evidence.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.source_attribute_reliability (
    kind       text NOT NULL,
    attribute  text NOT NULL,     -- code / name / company / mfg / expiry / ALL
    confirmed  numeric NOT NULL DEFAULT 0,
    checked    numeric NOT NULL DEFAULT 0,
    updated_at timestamp DEFAULT now(),
    PRIMARY KEY (kind, attribute)
);

CREATE OR REPLACE FUNCTION public.asli_reliability(p_kind text, p_attribute text DEFAULT 'ALL')
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN upper(p_kind) IN ('PACK', 'BUYER') THEN 1.0 ELSE
           round((public.match_cfg('reliability_prior') * public.match_cfg('reliability_strength') + coalesce(r.confirmed, 0))
                 / (public.match_cfg('reliability_strength') + coalesce(r.checked, 0)), 3) END
    FROM (SELECT 1) one
    LEFT JOIN public.source_attribute_reliability r ON r.kind = upper(p_kind) AND r.attribute = p_attribute
$$;

-- Recompute the counters from the cleansing history: every record a scan
-- assigned to an item was checked; every applied fix on it is one error.
CREATE OR REPLACE FUNCTION public.refresh_reliability()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    DELETE FROM public.source_attribute_reliability;
    WITH checked AS (
        SELECT a.source AS kind, count(*)::numeric AS n
        FROM public.cleansing_assignments a
        WHERE a.scan_id = (SELECT min(scan_id) FROM public.cleansing_scans)   -- the first, uncleaned look at the data
        GROUP BY 1
        UNION ALL
        SELECT 'MANUFACTURER', count(DISTINCT a.item_code)::numeric
        FROM public.cleansing_assignments a
        WHERE a.scan_id = (SELECT min(scan_id) FROM public.cleansing_scans)
    ),
    errors AS (
        SELECT p.source AS kind,
               CASE WHEN p.field IN ('medicine') THEN 'name' ELSE p.field END AS attribute,
               count(*)::numeric AS n
        FROM public.cleansing_log l JOIN public.cleansing_proposals p ON p.proposal_id = l.proposal_id
        GROUP BY 1, 2
    ),
    attrs AS (SELECT unnest(ARRAY['code', 'name', 'company', 'mfg', 'expiry']) AS attribute)
    INSERT INTO public.source_attribute_reliability (kind, attribute, confirmed, checked)
    SELECT c.kind, a.attribute, greatest(c.n - coalesce(e.n, 0), 0), c.n
    FROM checked c CROSS JOIN attrs a
    LEFT JOIN errors e ON e.kind = c.kind AND e.attribute = a.attribute
    WHERE c.n > 0
    UNION ALL
    SELECT c.kind, 'ALL', greatest(c.n - coalesce((SELECT sum(e2.n) FROM errors e2 WHERE e2.kind = c.kind), 0), 0), c.n
    FROM checked c WHERE c.n > 0;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END;
$$;

-- ---------------------------------------------------------------------
-- 7. Checks
-- ---------------------------------------------------------------------
SELECT 'extension on mediator' AS check_name,
       CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'asli_match') THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'servers may ship asli functions',
       CASE WHEN (SELECT count(*) FROM pg_foreign_server f, unnest(f.srvoptions) o
                  WHERE o = 'extensions=asli_match'
                    AND f.srvname IN ('manufacturer_server', 'distributor_server', 'vendor_server')) = 3 THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'every source answers a probe',
       CASE WHEN (SELECT count(DISTINCT kind) FROM public.asli_probe('ITEM000001')) = 3 THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'noisy code ITEM0O0041 finds ITEM000041 at the manufacturer',
       CASE WHEN EXISTS (SELECT 1 FROM public.asli_probe('ITEM0O0041', NULL, NULL, ARRAY['MANUFACTURER'])
                         WHERE stored_code = 'ITEM000041') THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'at most k per pass per source',
       CASE WHEN (SELECT max(n) FROM (SELECT source_id, hit, count(*) AS n FROM public.asli_probe('ITEM000150')
                                      WHERE hit = 'code' GROUP BY 1, 2) x) <= public.match_cfg('probe_k') THEN 'PASS' ELSE 'FAIL' END;
