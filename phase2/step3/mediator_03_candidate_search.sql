-- =====================================================================
-- Asli-or-Nakli · Phase 2 · Step 3
-- Combined scoring + candidate search (both directions)
-- RUN ON: mediator_db   (after mediator_02_matching_functions.sql)
-- In DBeaver run as a script: Alt+X.  Safe to run more than once.
-- =====================================================================
--
--   search_by_pack(code, name, company, mfg, expiry)
--        Buyer types a (possibly noisy) code + what the pack says
--        -> every approximately matching item, ranked, with a verdict.
--
--   match_stored_record(source, record_id)
--        A distributor / vendor row -> which real item it most likely is.
--        Also uses supply-chain context (distributor ID, who it was supplied to).
--
--   find_records_for_item(item_code)          ("vice versa")
--        A real item -> every distributor / vendor record that is, or
--        looks like, that item (including noisy ones).
--
--   v_stored_record_flags
--        Every distributor / vendor row: OK, UNKNOWN CODE, or CONTEXT CONFLICT.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Weights and thresholds (added to match_config from step 2)
-- ---------------------------------------------------------------------
INSERT INTO public.match_config (key, value, description) VALUES ('w_code', 0.40, 'Weight: item code similarity') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('w_name', 0.30, 'Weight: medicine name similarity') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('w_expiry', 0.15, 'Weight: expiry date') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('w_company', 0.10, 'Weight: manufacturer name') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('w_mfg', 0.05, 'Weight: manufacturing date') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('w_distributor', 0.10, 'Weight: stored records only - distributor ID agrees with the other database') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('w_supply', 0.10, 'Weight: vendor records only - distributor says it supplied this item to this shop (counts only when it agrees)') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('min_code_similarity', 0.80, 'Only items at least this similar on code are considered candidates') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('match_threshold', 0.85, 'Best total score needed for a confident MATCH') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('review_threshold', 0.60, 'Below this nothing is suggested (NO MATCH)') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('total_margin', 0.10, 'MATCH needs this lead in total score over the runner-up, or') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('code_margin', 0.50, 'a lead of this much code-edit cost with equal or better context') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('conflict_name_below', 0.50, 'Name similarity below this contradicts the record') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('conflict_company_below', 0.50, 'Company similarity below this contradicts the record') ON CONFLICT (key) DO NOTHING;
INSERT INTO public.match_config (key, value, description) VALUES ('context_tolerance', 0.05, 'Runner-up context may be this much better and the clearly better code still wins') ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. Unified views (schema matching made explicit)
-- ---------------------------------------------------------------------

-- The reference ("golden") item list from the manufacturer
CREATE OR REPLACE VIEW public.v_golden_items AS
SELECT mi.unique_item_code   AS item_code,
       mi.medicine_code,
       m.medicine_name,
       m.composition,
       mf.manufacturer_name,
       mi.manufacturing_date,
       mi.expiry_date
FROM public.manufactured_items mi
JOIN public.medicines     m  ON m.medicine_code    = mi.medicine_code
JOIN public.manufacturers mf ON mf.manufacturer_id = m.manufacturer_id;

-- Distributor and vendor rows mapped onto ONE set of column names
--   distributor: product_code / drug_name / mfr_name / mfg_date / exp_date
--   vendor:      item_identifier / medicine_name / company / mfg / expiry
CREATE OR REPLACE VIEW public.v_stored_records AS
SELECT 'DISTRIBUTOR'::text  AS source,
       d.inventory_id       AS record_id,
       d.product_code       AS stored_code,
       d.distributor_id,
       NULL::int            AS vendor_id,
       NULL::text           AS vendor_name,
       d.drug_name::text    AS name,
       d.mfr_name::text     AS company,
       d.mfg_date::text     AS mfg,
       d.exp_date::text     AS expiry,
       d.received_date
FROM public.inventory_items d
UNION ALL
SELECT 'VENDOR',
       vi.inventory_id,
       vi.item_identifier,
       vi.distributor_id,
       vi.vendor_id,
       v.vendor_name::text,
       vi.medicine_name::text,
       vi.company::text,
       vi.mfg::text,
       vi.expiry::text,
       vi.received_date
FROM public.vendor_inventory vi
LEFT JOIN public.vendors v ON v.vendor_id = vi.vendor_id;

-- Health check of every stored row against the manufacturer:
--   OK               code is a real item code and the context agrees
--   UNKNOWN CODE     code is not exactly any manufacturer code (noise, formatting, fake)
--   CONTEXT CONFLICT code is real but name / company / dates disagree
CREATE OR REPLACE VIEW public.v_stored_record_flags AS
WITH chk AS (
    SELECT r.*,
           g.item_code AS golden_code,
           medicine_name_similarity(r.name, g.medicine_name)  AS name_s,
           medicine_name_similarity(r.name, g.composition)    AS comp_name_s,
           company_similarity(r.company, g.manufacturer_name) AS company_s,
           date_similarity(r.expiry, g.expiry_date::text)     AS expiry_s,
           date_similarity(r.mfg, g.manufacturing_date::text) AS mfg_s
    FROM public.v_stored_records r
    LEFT JOIN public.v_golden_items g ON g.item_code = r.stored_code
)
SELECT source, record_id, stored_code, distributor_id, vendor_id, vendor_name,
       name, company, mfg, expiry, received_date,
       CASE
         WHEN golden_code IS NULL THEN 'UNKNOWN CODE'
         WHEN greatest(name_s, comp_name_s) < match_cfg('conflict_name_below')
           OR company_s < match_cfg('conflict_company_below')
           OR expiry_s  < 1
           OR mfg_s     < 1 THEN 'CONTEXT CONFLICT'
         ELSE 'OK'
       END AS status,
       concat_ws('; ',
         CASE WHEN golden_code IS NULL THEN 'code not found at manufacturer' END,
         CASE WHEN greatest(name_s, comp_name_s) < match_cfg('conflict_name_below') THEN 'medicine name differs' END,
         CASE WHEN company_s < match_cfg('conflict_company_below') THEN 'manufacturer differs' END,
         CASE WHEN expiry_s < 1 THEN 'expiry differs' END,
         CASE WHEN mfg_s < 1 THEN 'mfg date differs' END) AS issues
FROM chk;

-- ---------------------------------------------------------------------
-- 3a. Result shape shared by all search functions
--     (dropped and recreated so the script can be re-run after edits)
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.record_trust(text, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.verify_item(text);
DROP FUNCTION IF EXISTS public.find_records_for_item(text);
DROP FUNCTION IF EXISTS public.match_stored_record(text, int, int);
DROP FUNCTION IF EXISTS public.search_by_pack(text, text, text, text, text, int);
DROP FUNCTION IF EXISTS public.match_candidates(text, text, text, text, text, text, int, text, int);
DROP TYPE IF EXISTS public.match_result;

CREATE TYPE public.match_result AS (
    rank              int,
    item_code         text,
    medicine_name     text,
    manufacturer      text,
    mfg_date          date,
    expiry_date       date,
    code_edit_cost    numeric,
    code_score        numeric,
    name_score        numeric,
    company_score     numeric,
    expiry_score      numeric,
    mfg_score         numeric,
    distributor_score numeric,
    supply_score      numeric,
    dates_swapped     boolean,
    context_score     numeric,
    total_score       numeric,
    verdict           text,
    decided_item      text,
    weights           jsonb      -- the dynamic attribute weights used for this search
);

-- ---------------------------------------------------------------------
-- 3. Core: score every candidate item for one (noisy) record
-- ---------------------------------------------------------------------
--   p_source: 'PACK' (buyer input), 'VENDOR' or 'DISTRIBUTOR' (stored row)
--
--   total score = weighted average of the evidence that is AVAILABLE
--                 (missing context is left out, not counted as 0)
--
--   verdict (same on every row; decided_item = the item it settles on)
--     EXACT MATCH           code is exactly a real code and context agrees
--     MATCH                 one candidate clearly wins
--     CONTEXT ERROR         code is real and the medicine agrees, other fields are wrong
--     WRONG CODE            code is real but belongs to another medicine;
--                           a different item fits the context -> decided_item
--     POSSIBLE CLONED CODE  (buyer only) real code, pack contradicts it,
--                           nothing else fits -> treat as NAKALI
--     NOISY MANUFACTURER RECORD
--                           the distributor AND the vendor both hold this exact
--                           code but the manufacturer does not: the manufacturer's
--                           copy is the noisy one (majority 2 of 3). Only when their
--                           code is in the standard format ITEM + 6 digits and the
--                           manufacturer's copy is not. Only items
--                           no other database holds are candidates; decided_item
--                           is the manufacturer's (noisy) record of this item
--     REVIEW                more than one plausible item -> a person decides
--     NO MATCH              nothing plausible
CREATE FUNCTION public.match_candidates(
    p_source         text,
    p_code           text,
    p_name           text DEFAULT NULL,
    p_company        text DEFAULT NULL,
    p_mfg            text DEFAULT NULL,
    p_expiry         text DEFAULT NULL,
    p_distributor_id int  DEFAULT NULL,
    p_vendor_name    text DEFAULT NULL,
    p_limit          int  DEFAULT 10)
RETURNS SETOF public.match_result
LANGUAGE sql STABLE AS $$
WITH cfg AS (
    SELECT max(value) FILTER (WHERE key = 'w_code')        AS w_code,
           max(value) FILTER (WHERE key = 'w_name')        AS w_name,
           max(value) FILTER (WHERE key = 'w_expiry')      AS w_exp,
           max(value) FILTER (WHERE key = 'w_company')     AS w_comp,
           max(value) FILTER (WHERE key = 'w_mfg')         AS w_mfg,
           max(value) FILTER (WHERE key = 'w_distributor') AS w_dist,
           max(value) FILTER (WHERE key = 'w_supply')      AS w_sup,
           max(value) FILTER (WHERE key = 'min_code_similarity') AS min_code,
           max(value) FILTER (WHERE key = 'match_threshold')     AS t_match,
           max(value) FILTER (WHERE key = 'review_threshold')    AS t_review,
           max(value) FILTER (WHERE key = 'total_margin')        AS m_total,
           max(value) FILTER (WHERE key = 'code_margin')         AS m_code,
           max(value) FILTER (WHERE key = 'conflict_name_below')    AS c_name,
           max(value) FILTER (WHERE key = 'conflict_company_below') AS c_comp,
           coalesce(max(value) FILTER (WHERE key = 'context_tolerance'), 0) AS ctx_tol
    FROM public.match_config
),
-- Candidates come from the SOURCES (step 6): each source finds its own top k
-- with an index and returns only those tuples. Nothing reads a whole table.
-- golden = the manufacturer's candidate items for this code (+ context pass)
golden AS MATERIALIZED (
    SELECT DISTINCT ON (c.record_id)
           c.stored_code AS item_code, c.medicine_code, c.name AS medicine_name, c.composition,
           c.company AS manufacturer_name, c.mfg_date AS manufacturing_date, c.exp_date AS expiry_date
    FROM public.asli_probe(p_code, p_name, p_expiry, ARRAY['MANUFACTURER']) c
    ORDER BY c.record_id),
-- distributor / vendor records that carry one of these codes (or the typed one),
-- looked up exactly by folded code at each source
held_rows AS MATERIALIZED (
    SELECT c.* FROM public.asli_probe(NULL, NULL, NULL, ARRAY['DISTRIBUTOR', 'VENDOR'],
                                      ARRAY(SELECT asli.fold(g.item_code) FROM golden g) || asli.fold(p_code)) c),
dist_inv AS MATERIALIZED (
    SELECT h.stored_code AS product_code, h.distributor_id FROM held_rows h
    WHERE h.kind = 'DISTRIBUTOR' AND p_source = 'VENDOR' AND p_distributor_id IS NOT NULL),
vend_inv AS MATERIALIZED (
    SELECT h.stored_code AS item_identifier, h.distributor_id FROM held_rows h
    WHERE h.kind = 'VENDOR' AND p_source = 'DISTRIBUTOR' AND p_distributor_id IS NOT NULL),
supply AS MATERIALIZED (
    SELECT h.stored_code AS product_code, h.supplied_to AS vendor_reference FROM held_rows h
    WHERE h.kind = 'DISTRIBUTOR' AND h.supplied_to IS NOT NULL AND p_source = 'VENDOR' AND p_vendor_name IS NOT NULL),
-- codes held by the distributor (D) and vendor (V), cleaned up
held AS MATERIALIZED (
    SELECT normalize_code(h.stored_code) AS code, CASE h.kind WHEN 'DISTRIBUTOR' THEN 'D' ELSE 'V' END AS src
    FROM held_rows h),
-- stage 1: approximate code match
near AS MATERIALIZED (
    SELECT g.*, cd.dist,
           round(greatest(0, 1 - cd.dist / greatest(length(normalize_code(p_code)), length(g.item_code), 1)), 3) AS code_s
    FROM golden g
    CROSS JOIN LATERAL (SELECT code_distance(p_code, g.item_code) AS dist) cd
),
-- majority rule: the distributor AND the vendor both hold this exact code, the
-- manufacturer does not, so the manufacturer's copy is the noisy one. The
-- manufacturer issues the codes, so this only applies when the code they hold is
-- in the standard format ITEM + 6 digits and the manufacturer's look-alike copy
-- is NOT (ITEM0OO002 vs ITEM000002). In every other case (both hold ITEM00008S,
-- or both hold a valid-looking ITEM000820) it is their noise, matched as usual.
maj AS (
    SELECT normalize_code(p_code) ~ '^ITEM[0-9]{6}$'
       AND normalize_code(p_code) NOT IN (SELECT item_code FROM golden)
       AND EXISTS (SELECT 1 FROM held WHERE code = normalize_code(p_code) AND src = 'D')
       AND EXISTS (SELECT 1 FROM held WHERE code = normalize_code(p_code) AND src = 'V')
       AND EXISTS (SELECT 1 FROM near n, cfg
                   WHERE n.dist <= cfg.m_code          -- a near-identical copy (look-alikes, a dropped zero)
                     AND n.item_code !~ '^ITEM[0-9]{6}$'
                     AND n.item_code NOT IN (SELECT code FROM held)) AS on
),
cand AS (
    SELECT n.* FROM near n, cfg, maj
    WHERE n.code_s >= cfg.min_code
      -- under the majority rule an item already held by another database
      -- cannot be the manufacturer's noisy copy of this code
      AND (NOT maj.on OR (n.item_code NOT IN (SELECT code FROM held)
                          AND n.item_code !~ '^ITEM[0-9]{6}$'
                          AND n.dist <= cfg.m_code))
),
-- stage 2: context and supply-chain evidence
scored AS (
    SELECT c.*,
           greatest(medicine_name_similarity(p_name, c.medicine_name),
                    medicine_name_similarity(p_name, c.composition))       AS name_s,
           company_similarity(p_company, c.manufacturer_name)               AS comp_s,
           date_similarity(p_expiry, c.expiry_date::text)                   AS exp_raw,
           date_similarity(p_mfg, c.manufacturing_date::text)               AS mfg_raw,
           coalesce(date_similarity(p_mfg, c.expiry_date::text) = 1
                AND date_similarity(p_expiry, c.manufacturing_date::text) = 1
                AND date_similarity(p_expiry, c.expiry_date::text) < 1, false) AS swapped,
           CASE p_source
             WHEN 'VENDOR'      THEN (SELECT (di.distributor_id = p_distributor_id)::int::numeric
                                      FROM dist_inv di WHERE di.product_code = c.item_code LIMIT 1)
             WHEN 'DISTRIBUTOR' THEN (SELECT (vi.distributor_id = p_distributor_id)::int::numeric
                                      FROM vend_inv vi WHERE vi.item_identifier = c.item_code LIMIT 1)
           END                                                              AS dist_s,
           -- positive evidence only: 1 if the distributor says it supplied this item to
           -- this shop; a different shop is a supply-chain anomaly (Phase 1), not proof
           -- that the record is a different item, so it counts as "no evidence"
           (SELECT 1::numeric FROM supply s
            WHERE s.product_code = c.item_code
              AND lower(btrim(s.vendor_reference)) = lower(btrim(p_vendor_name)) LIMIT 1) AS sup_s
    FROM cand c
),
adj AS (
    SELECT s.*,
           CASE WHEN s.swapped THEN 1 ELSE s.exp_raw END AS exp_s,
           CASE WHEN s.swapped THEN 1 ELSE s.mfg_raw END AS mfg_s
    FROM scored s
),
-- DYNAMIC WEIGHTS (requirement 3). Each attribute weight =
--   base weight (match_config)
--   x discrimination: how well the attribute tells THESE candidates apart
--     (normalised entropy of its values; 1 when there is only one candidate,
--      the floor when every candidate has the same value)
--   x reliability of the record's source for that attribute (buyer = 1)
-- Presence is handled below: a missing attribute is left out and the others
-- share its weight.
disc AS (
    SELECT n,
           CASE WHEN n < 2 THEN 1 ELSE public.match_cfg('discrimination_floor')
                + (1 - public.match_cfg('discrimination_floor')) * h_name / ln(n::numeric) END AS d_name,
           CASE WHEN n < 2 THEN 1 ELSE public.match_cfg('discrimination_floor')
                + (1 - public.match_cfg('discrimination_floor')) * h_comp / ln(n::numeric) END AS d_comp,
           CASE WHEN n < 2 THEN 1 ELSE public.match_cfg('discrimination_floor')
                + (1 - public.match_cfg('discrimination_floor')) * h_exp / ln(n::numeric) END AS d_exp,
           CASE WHEN n < 2 THEN 1 ELSE public.match_cfg('discrimination_floor')
                + (1 - public.match_cfg('discrimination_floor')) * h_mfg / ln(n::numeric) END AS d_mfg
    FROM (SELECT (SELECT count(*) FROM adj) AS n,
                 (SELECT coalesce(-sum(p * ln(p)), 0) FROM (SELECT count(*)::numeric / (SELECT count(*) FROM adj) AS p
                         FROM adj GROUP BY lower(medicine_name)) z) AS h_name,
                 (SELECT coalesce(-sum(p * ln(p)), 0) FROM (SELECT count(*)::numeric / (SELECT count(*) FROM adj) AS p
                         FROM adj GROUP BY normalize_company(manufacturer_name)) z) AS h_comp,
                 (SELECT coalesce(-sum(p * ln(p)), 0) FROM (SELECT count(*)::numeric / (SELECT count(*) FROM adj) AS p
                         FROM adj GROUP BY date_trunc('month', expiry_date)) z) AS h_exp,
                 (SELECT coalesce(-sum(p * ln(p)), 0) FROM (SELECT count(*)::numeric / (SELECT count(*) FROM adj) AS p
                         FROM adj GROUP BY date_trunc('month', manufacturing_date)) z) AS h_mfg) e
),
dw AS (
    SELECT round(cfg.w_code * public.asli_reliability(p_source, 'code'), 4)                  AS w_code,
           round(cfg.w_name * disc.d_name * public.asli_reliability(p_source, 'name'), 4)    AS w_name,
           round(cfg.w_exp  * disc.d_exp  * public.asli_reliability(p_source, 'expiry'), 4)  AS w_exp,
           round(cfg.w_comp * disc.d_comp * public.asli_reliability(p_source, 'company'), 4) AS w_comp,
           round(cfg.w_mfg  * disc.d_mfg  * public.asli_reliability(p_source, 'mfg'), 4)     AS w_mfg,
           cfg.w_dist AS w_dist, cfg.w_sup AS w_sup,
           disc.n AS n_candidates
    FROM cfg, disc
),
tot AS (
    SELECT a.*,
           round((dw.w_code * a.code_s
                  + coalesce(dw.w_name * a.name_s, 0) + coalesce(dw.w_exp * a.exp_s, 0)
                  + coalesce(dw.w_comp * a.comp_s, 0) + coalesce(dw.w_mfg * a.mfg_s, 0)
                  + coalesce(dw.w_dist * a.dist_s, 0) + coalesce(dw.w_sup * a.sup_s, 0))
                 / (dw.w_code
                    + CASE WHEN a.name_s IS NULL THEN 0 ELSE dw.w_name END
                    + CASE WHEN a.exp_s  IS NULL THEN 0 ELSE dw.w_exp  END
                    + CASE WHEN a.comp_s IS NULL THEN 0 ELSE dw.w_comp END
                    + CASE WHEN a.mfg_s  IS NULL THEN 0 ELSE dw.w_mfg  END
                    + CASE WHEN a.dist_s IS NULL THEN 0 ELSE dw.w_dist END
                    + CASE WHEN a.sup_s  IS NULL THEN 0 ELSE dw.w_sup  END), 3) AS total,
           round((coalesce(dw.w_name * a.name_s, 0) + coalesce(dw.w_exp * a.exp_s, 0)
                  + coalesce(dw.w_comp * a.comp_s, 0) + coalesce(dw.w_mfg * a.mfg_s, 0)
                  + coalesce(dw.w_dist * a.dist_s, 0) + coalesce(dw.w_sup * a.sup_s, 0))
                 / nullif(CASE WHEN a.name_s IS NULL THEN 0 ELSE dw.w_name END
                          + CASE WHEN a.exp_s  IS NULL THEN 0 ELSE dw.w_exp  END
                          + CASE WHEN a.comp_s IS NULL THEN 0 ELSE dw.w_comp END
                          + CASE WHEN a.mfg_s  IS NULL THEN 0 ELSE dw.w_mfg  END
                          + CASE WHEN a.dist_s IS NULL THEN 0 ELSE dw.w_dist END
                          + CASE WHEN a.sup_s  IS NULL THEN 0 ELSE dw.w_sup  END, 0), 3) AS ctx,
           -- does this candidate's own record contradict the input?
           (coalesce(a.name_s < cfg.c_name, false)
            OR coalesce(a.comp_s < cfg.c_comp, false)
            OR coalesce(a.exp_s = 0, false))                                   AS conflict
    FROM adj a, cfg, dw
),
ranked AS (
    SELECT t.*, row_number() OVER (ORDER BY t.total DESC, t.dist ASC, t.item_code)::int AS rnk
    FROM tot t
),
s AS (   -- facts the verdict needs
    SELECT
      (SELECT item_code FROM ranked WHERE rnk = 1) AS top_code,
      (SELECT total     FROM ranked WHERE rnk = 1) AS top_total,
      (SELECT dist      FROM ranked WHERE rnk = 1) AS top_dist,
      (SELECT ctx       FROM ranked WHERE rnk = 1) AS top_ctx,
      (SELECT total     FROM ranked WHERE rnk = 2) AS second_total,
      (SELECT dist      FROM ranked WHERE rnk = 2) AS second_dist,
      (SELECT ctx       FROM ranked WHERE rnk = 2) AS second_ctx,
      (SELECT item_code FROM ranked WHERE dist = 0 ORDER BY rnk LIMIT 1) AS ex_code,
      (SELECT conflict  FROM ranked WHERE dist = 0 ORDER BY rnk LIMIT 1) AS ex_conflict,
      (SELECT name_s    FROM ranked WHERE dist = 0 ORDER BY rnk LIMIT 1) AS ex_name
),
v AS (
    SELECT s.*,
      CASE
        WHEN s.top_code IS NULL THEN 'NO MATCH'
        -- the code exists exactly (after cleanup)
        WHEN s.ex_code IS NOT NULL AND NOT s.ex_conflict AND p_code = s.ex_code THEN 'EXACT MATCH'
        WHEN s.ex_code IS NOT NULL AND NOT s.ex_conflict                     THEN 'MATCH'
        WHEN s.ex_code IS NOT NULL AND coalesce(s.ex_name, 0) >= 0.8          THEN 'CONTEXT ERROR'
        WHEN s.ex_code IS NOT NULL AND s.top_code <> s.ex_code
             AND s.top_total >= cfg.t_match AND coalesce(s.top_ctx, 0) >= 0.8 THEN 'WRONG CODE'
        WHEN s.ex_code IS NOT NULL AND p_source = 'PACK'                     THEN 'POSSIBLE CLONED CODE'
        WHEN s.ex_code IS NOT NULL                                           THEN 'REVIEW'
        -- the code does not exist: approximate match
        WHEN s.top_total >= cfg.t_match
             AND (s.top_total - coalesce(s.second_total, 0) >= cfg.m_total
                  OR (s.second_dist - s.top_dist >= cfg.m_code
                      AND coalesce(s.second_ctx, -1) <= coalesce(s.top_ctx, -1) + cfg.ctx_tol))
             THEN CASE WHEN maj.on THEN 'NOISY MANUFACTURER RECORD' ELSE 'MATCH' END
        WHEN s.top_total >= cfg.t_review                                      THEN 'REVIEW'
        ELSE 'NO MATCH'
      END AS verdict
    FROM s, cfg, maj
)
SELECT r.rnk, r.item_code::text, r.medicine_name::text, r.manufacturer_name::text,
       r.manufacturing_date, r.expiry_date,
       r.dist, r.code_s, r.name_s, r.comp_s, r.exp_s, r.mfg_s, r.dist_s, r.sup_s, r.swapped,
       r.ctx, r.total,
       v.verdict,
       CASE v.verdict
         WHEN 'EXACT MATCH'   THEN v.ex_code
         WHEN 'CONTEXT ERROR' THEN v.ex_code
         WHEN 'MATCH'         THEN coalesce(CASE WHEN NOT v.ex_conflict THEN v.ex_code END, v.top_code)
         WHEN 'WRONG CODE'    THEN v.top_code
         WHEN 'NOISY MANUFACTURER RECORD' THEN v.top_code
       END,
       (SELECT jsonb_build_object('code', w_code, 'name', w_name, 'expiry', w_exp, 'company', w_comp,
                                  'mfg', w_mfg, 'distributor', w_dist, 'supply', w_sup,
                                  'candidates', n_candidates) FROM dw)
FROM ranked r, v
WHERE r.rnk <= p_limit
ORDER BY r.rnk
$$;

-- ---------------------------------------------------------------------
-- 4. Entry points
-- ---------------------------------------------------------------------

-- Buyer: code + whatever the pack shows (all optional except the code)
CREATE FUNCTION public.search_by_pack(
    p_code    text,
    p_name    text DEFAULT NULL,
    p_company text DEFAULT NULL,
    p_mfg     text DEFAULT NULL,
    p_expiry  text DEFAULT NULL,
    p_limit   int  DEFAULT 10)
RETURNS SETOF public.match_result LANGUAGE sql STABLE AS $$
    SELECT * FROM public.match_candidates('PACK', p_code,
                                         nullif(btrim(p_name), ''),  nullif(btrim(p_company), ''),
                                         nullif(btrim(p_mfg), ''),   nullif(btrim(p_expiry), ''),
                                         NULL, NULL, p_limit)
$$;

-- A stored distributor / vendor row: which real item is it?
--   p_source = 'DISTRIBUTOR' (record_id = inventory_items.inventory_id)
--           or 'VENDOR'      (record_id = vendor_inventory.inventory_id)
CREATE FUNCTION public.match_stored_record(p_source text, p_record_id int, p_limit int DEFAULT 10)
RETURNS SETOF public.match_result LANGUAGE sql STABLE AS $$
    SELECT m.*
    FROM public.v_stored_records r
    CROSS JOIN LATERAL public.match_candidates(r.source, r.stored_code, r.name, r.company,
                                               r.mfg, r.expiry, r.distributor_id, r.vendor_name,
                                               p_limit) m
    WHERE r.source = upper(p_source) AND r.record_id = p_record_id
$$;

-- Vice versa: a real item -> every stored record that is, or looks like, that item
--   relation:
--     EXACT CODE         record carries this code and its context agrees
--     EXACT CODE, CONTEXT ERROR   carries this code, same medicine, some fields wrong
--     NOISY VARIANT      record's code is different, but it resolves to this item
--     POSSIBLE           record is ambiguous and this item is one of its options
--     BELONGS ELSEWHERE  record looks similar (or even carries this code)
--                        but resolves to another item
CREATE FUNCTION public.find_records_for_item(p_item_code text)
RETURNS TABLE (source text, record_id int, stored_code text, relation text,
               record_status text, verdict text, decided_item text,
               item_rank int, item_score numeric, code_edit_cost numeric,
               name text, company text, expiry text,
               distributor_id int, vendor_name text, mfg text)
LANGUAGE sql STABLE AS $$
WITH item AS MATERIALIZED (SELECT * FROM public.v_golden_items WHERE item_code = p_item_code),
-- records near this item, found by the SOURCES themselves (step 6): records one
-- typing error away, the same folded code, and the same medicine + expiry month.
-- No table is read whole.
recs AS MATERIALIZED (
    SELECT c.* FROM public.asli_probe(p_item_code,
                                      (SELECT medicine_name FROM item LIMIT 1),
                                      (SELECT expiry_date::text FROM item LIMIT 1),
                                      ARRAY['DISTRIBUTOR', 'VENDOR'], '{}',
                                      public.match_cfg('probe_k_reverse')::int) c),
-- the manufacturer's item for each record's exact code (for the record status)
gl AS MATERIALIZED (
    SELECT DISTINCT ON (g.stored_code) g.*
    FROM public.asli_probe(NULL, NULL, NULL, ARRAY['MANUFACTURER'],
                           ARRAY(SELECT asli.fold(r.stored_code) FROM recs r)) g
    ORDER BY g.stored_code),
-- same status rules as v_stored_record_flags, on these few records only
flags AS MATERIALIZED (
    SELECT r.kind AS source, r.record_id, r.stored_code, r.distributor_id, r.vendor_id, r.vendor_name,
           r.name, r.company, r.mfg, r.expiry,
           CASE WHEN g.stored_code IS NULL THEN 'UNKNOWN CODE'
                WHEN greatest(medicine_name_similarity(r.name, g.name),
                              medicine_name_similarity(r.name, g.composition)) < match_cfg('conflict_name_below')
                  OR company_similarity(r.company, g.company) < match_cfg('conflict_company_below')
                  OR date_similarity(r.expiry, g.exp_date::text) < 1
                  OR date_similarity(r.mfg, g.mfg_date::text) < 1 THEN 'CONTEXT CONFLICT'
                ELSE 'OK' END AS status
    FROM recs r LEFT JOIN gl g ON g.stored_code = r.stored_code
),
-- rows carrying this exact code, plus rows needing attention whose code is close
-- AND whose stored medicine name does not contradict this item (cheap pre-filter)
related AS (
    SELECT f.* FROM flags f
    WHERE f.stored_code = p_item_code
       OR (f.status <> 'OK'
           AND code_similarity(f.stored_code, p_item_code) >= match_cfg('min_code_similarity')
           AND coalesce((SELECT greatest(medicine_name_similarity(f.name, i.medicine_name),
                                         medicine_name_similarity(f.name, i.composition))
                         FROM item i), 1) >= match_cfg('conflict_name_below'))
),
resolved AS (
    SELECT r.*, m.*
    FROM related r
    CROSS JOIN LATERAL (
        SELECT max(mc.verdict)      AS m_verdict,
               max(mc.decided_item) AS m_decided,
               max(mc.total_score)  AS m_top,
               max(mc.rank)           FILTER (WHERE mc.item_code = p_item_code) AS m_rank,
               max(mc.total_score)    FILTER (WHERE mc.item_code = p_item_code) AS m_score,
               max(mc.code_edit_cost) FILTER (WHERE mc.item_code = p_item_code) AS m_cost
        FROM public.match_candidates(r.source, r.stored_code, r.name, r.company, r.mfg, r.expiry,
                                     r.distributor_id, r.vendor_name, 50) mc
        WHERE r.status <> 'OK'            -- clean exact rows need no search
    ) m
),
labelled AS (
    SELECT r.*,
           CASE
             WHEN r.stored_code = p_item_code AND r.status = 'OK'          THEN 'EXACT CODE'
             WHEN r.m_decided = p_item_code AND r.stored_code = p_item_code THEN 'EXACT CODE, CONTEXT ERROR'
             WHEN r.m_decided = p_item_code                                 THEN 'NOISY VARIANT'
             WHEN r.m_decided IS NULL
                  AND r.m_score >= r.m_top - match_cfg('total_margin')      THEN 'POSSIBLE'
             ELSE 'BELONGS ELSEWHERE'
           END AS rel
    FROM resolved r
)
SELECT l.source, l.record_id, l.stored_code, l.rel,
       l.status, l.m_verdict, coalesce(l.m_decided, CASE WHEN l.status = 'OK' THEN l.stored_code END),
       l.m_rank, l.m_score,
       coalesce(l.m_cost, CASE WHEN l.stored_code = p_item_code THEN 0 END),
       l.name, l.company, l.expiry, l.distributor_id, l.vendor_name, l.mfg
FROM labelled l
-- "belongs elsewhere" is only worth showing for rows that carry this exact code
WHERE l.rel <> 'BELONGS ELSEWHERE' OR l.stored_code = p_item_code
ORDER BY 4, 1, 2
$$;

-- ---------------------------------------------------------------------
-- verify_item: the Phase 1 verification of one item, noise-aware.
-- Same columns and rules as global_medicine_history (the view is not
-- changed), but a distributor / vendor record also counts when it holds
-- this item under a NOISY code (find_records_for_item says NOISY VARIANT,
-- e.g. both hold ITEM00008S for ITEM000085). Exact records come first.
-- ---------------------------------------------------------------------
CREATE FUNCTION public.verify_item(p_item_code text)
RETURNS SETOF public.global_medicine_history
LANGUAGE sql STABLE AS $$
-- the records that hold this item under a noisy code: find_records_for_item
-- already asks the sources for nearby records and resolves each one
WITH noisy AS MATERIALIZED (
    SELECT f.source, f.stored_code FROM public.find_records_for_item(p_item_code) f
    WHERE f.relation = 'NOISY VARIANT'
),
dcodes AS (SELECT p_item_code AS code, 0 AS pref
           UNION SELECT n.stored_code, 1 FROM noisy n WHERE n.source = 'DISTRIBUTOR'),
vcodes AS (SELECT p_item_code AS code, 0 AS pref
           UNION SELECT n.stored_code, 1 FROM noisy n WHERE n.source = 'VENDOR'),
-- exact lookups of these few codes, sent to each source as a list (= ANY)
dinv AS MATERIALIZED (SELECT x.*, dc.pref FROM (SELECT * FROM public.inventory_items
                          WHERE product_code = ANY (ARRAY(SELECT code FROM dcodes))) x
                      JOIN dcodes dc ON x.product_code = dc.code),
vinv AS MATERIALIZED (SELECT x.*, vc.pref FROM (SELECT * FROM public.vendor_inventory
                          WHERE item_identifier = ANY (ARRAY(SELECT code FROM vcodes))) x
                      JOIN vcodes vc ON x.item_identifier = vc.code),
sup  AS MATERIALIZED (SELECT x.* FROM public.supplied_items x WHERE x.product_code = ANY (ARRAY(SELECT code FROM dcodes))),
sal  AS MATERIALIZED (SELECT x.* FROM public.medicine_sales x WHERE x.item_identifier = ANY (ARRAY(SELECT code FROM vcodes)))
SELECT mi.unique_item_code, mi.medicine_code, m.medicine_name, m.composition, m.dosage_form,
       mf.manufacturer_id, mf.manufacturer_name, mi.manufacturing_date, mi.expiry_date,
       CASE WHEN ai.item_code IS NOT NULL THEN 'APPROVED' ELSE 'UNAPPROVED / NAKALI' END,
       ai.approved_at, ai.approved_by,
       vi.inventory_id, vi.item_identifier, vi.vendor_id, v.vendor_name, vi.distributor_id, vi.received_date,
       d.inventory_id, d.product_code, d.distributor_id, dist.distributor_name, d.received_date,
       si.vendor_reference, si.supply_date,
       ms.sale_id, ms.sale_date, ms.customer_reference,
       CASE WHEN mi.expiry_date < CURRENT_DATE THEN 'EXPIRED' ELSE 'VALID' END,
       CASE WHEN ai.item_code IS NULL THEN 'SUSPICIOUS'
            WHEN mi.expiry_date < CURRENT_DATE THEN 'SUSPICIOUS'
            WHEN d.product_code IS NULL THEN 'SUSPICIOUS'
            WHEN d.distributor_id <> vi.distributor_id THEN 'SUSPICIOUS'
            WHEN vi.item_identifier IS NULL THEN 'SUSPICIOUS'
            ELSE 'GENUINE' END,
       CASE WHEN ai.item_code IS NULL THEN 'UNAPPROVED / NAKALI'
            WHEN mi.expiry_date < CURRENT_DATE THEN 'EXPIRED ITEM'
            WHEN d.product_code IS NULL THEN 'DISTRIBUTOR RECORD NOT FOUND'
            WHEN d.distributor_id <> vi.distributor_id THEN 'DISTRIBUTOR ID MISMATCH'
            WHEN vi.item_identifier IS NULL THEN 'VENDOR RECORD NOT FOUND'
            ELSE NULL END
FROM (SELECT * FROM public.manufactured_items WHERE unique_item_code = p_item_code) mi
LEFT JOIN public.medicines m ON mi.medicine_code = m.medicine_code
LEFT JOIN public.manufacturers mf ON m.manufacturer_id = mf.manufacturer_id
LEFT JOIN (SELECT * FROM public.approved_items WHERE item_code = p_item_code) ai ON mi.unique_item_code = ai.item_code
LEFT JOIN dinv d ON true
LEFT JOIN public.distributors dist ON d.distributor_id = dist.distributor_id
LEFT JOIN vinv vi ON true
LEFT JOIN public.vendors v ON vi.vendor_id = v.vendor_id
LEFT JOIN sup si ON si.product_code = d.product_code
LEFT JOIN sal ms ON ms.item_identifier = vi.item_identifier
ORDER BY d.pref NULLS LAST, vi.pref NULLS LAST
$$;

-- =====================================================================
-- Checks: every row should say PASS (takes a few seconds)
-- ---------------------------------------------------------------------
-- record_trust: GENUINE RECORD IDENTIFICATION (requirements 4 and 5).
-- Every record of one item (the manufacturer's + each distributor / vendor
-- record that resolves to it) gets a confidence from six factors:
--   E entity      code similarity to the typed code (no code typed: how close the
--                 stored code is to a valid ITEM + 6 digits code)
--   C context     similarity to the buyer's pack details (no pack: not used)
--   K complete    share of name / company / mfg / expiry that is filled in
--   A attribute   reliability of this source for the attributes it holds
--                 (a code with letters among the digits counts 0 for the code)
--   S source      reliability of this source overall (learned from cleansing)
--   Q consistency agreement with the OTHER records of the item, each weighted
--                 by its own source reliability (no other record: not used)
-- confidence = sum(w_f * f), w_f = beta_f (match_config) for the factors that
-- can be used, renormalised. The top record is accepted only if it reaches
-- trust_accept AND is trust_margin ahead of the next; otherwise REVIEW.
-- ---------------------------------------------------------------------
CREATE FUNCTION public.record_trust(p_item_code text, p_code text DEFAULT NULL, p_name text DEFAULT NULL,
                                    p_company text DEFAULT NULL, p_mfg text DEFAULT NULL, p_expiry text DEFAULT NULL)
RETURNS TABLE (rank int, source text, record_id int, stored_code text, name text, company text,
               mfg text, expiry text,
               entity numeric, context numeric, completeness numeric, attribute_rel numeric,
               source_rel numeric, consistency numeric, confidence numeric, weights jsonb, decision text)
LANGUAGE sql STABLE AS $$
WITH item AS MATERIALIZED (SELECT * FROM public.v_golden_items WHERE item_code = p_item_code),
mem AS MATERIALIZED (
    SELECT 'MANUFACTURER'::text AS source, NULL::int AS record_id, i.item_code AS stored_code,
           i.medicine_name::text AS name, i.manufacturer_name::text AS company,
           i.manufacturing_date::text AS mfg, i.expiry_date::text AS expiry
    FROM item i
    UNION ALL
    SELECT f.source, f.record_id, f.stored_code, f.name, f.company, f.mfg, f.expiry
    FROM public.find_records_for_item(p_item_code) f
    WHERE f.relation IN ('EXACT CODE', 'EXACT CODE, CONTEXT ERROR', 'NOISY VARIANT')
),
-- one comparable value per attribute
vals AS (
    SELECT m.*, x.attr, x.val
    FROM mem m
    CROSS JOIN LATERAL (VALUES
        ('code',    asli.fold(m.stored_code)),
        ('name',    public.normalize_medicine_name(m.name)),
        ('company', public.normalize_company(m.company)),
        ('mfg',     asli.month_key(m.mfg)::text),
        ('expiry',  asli.month_key(m.expiry)::text)) AS x(attr, val)
),
rel AS (
    SELECT DISTINCT v.source, public.asli_reliability(v.source, 'ALL') AS s_rel FROM vals v
),
cons AS (   -- Q: weighted agreement with the other records, per attribute
    SELECT v.source, v.record_id, v.attr,
           coalesce(sum(r2.s_rel) FILTER (WHERE o.val = v.val), 0) / nullif(sum(r2.s_rel), 0) AS agree
    FROM vals v
    JOIN vals o ON o.attr = v.attr AND o.val IS NOT NULL
               AND NOT (o.source = v.source AND o.record_id IS NOT DISTINCT FROM v.record_id)
    JOIN rel r2 ON r2.source = o.source
    WHERE v.val IS NOT NULL
    GROUP BY 1, 2, 3
),
f AS (
    SELECT m.*,
           round(CASE WHEN nullif(btrim(p_code), '') IS NOT NULL THEN public.code_similarity(m.stored_code, p_code)
                      WHEN m.stored_code ~ '^ITEM[0-9]{6}$' THEN 1
                      ELSE public.code_similarity(m.stored_code, asli.fold(m.stored_code)) END, 3) AS e,
           CASE WHEN coalesce(nullif(btrim(p_name), ''), nullif(btrim(p_company), ''),
                              nullif(btrim(p_mfg), ''), nullif(btrim(p_expiry), '')) IS NULL THEN NULL
                ELSE round((coalesce(0.30 * public.medicine_name_similarity(p_name, m.name), 0)
                            + coalesce(0.10 * public.company_similarity(p_company, m.company), 0)
                            + coalesce(0.05 * public.date_similarity(p_mfg, m.mfg), 0)
                            + coalesce(0.15 * public.date_similarity(p_expiry, m.expiry), 0))
                           / nullif(CASE WHEN public.medicine_name_similarity(p_name, m.name) IS NULL THEN 0 ELSE 0.30 END
                                    + CASE WHEN public.company_similarity(p_company, m.company) IS NULL THEN 0 ELSE 0.10 END
                                    + CASE WHEN public.date_similarity(p_mfg, m.mfg) IS NULL THEN 0 ELSE 0.05 END
                                    + CASE WHEN public.date_similarity(p_expiry, m.expiry) IS NULL THEN 0 ELSE 0.15 END, 0), 3)
           END AS c,
           round(((m.name IS NOT NULL)::int + (m.company IS NOT NULL)::int
                  + (asli.month_key(m.mfg) IS NOT NULL)::int + (asli.month_key(m.expiry) IS NOT NULL)::int) / 4.0, 3) AS k,
           round((CASE WHEN m.stored_code ~ '^ITEM[0-9]{6}$' THEN public.asli_reliability(m.source, 'code') ELSE 0 END
                  + CASE WHEN m.name    IS NOT NULL THEN public.asli_reliability(m.source, 'name')    ELSE 0 END
                  + CASE WHEN m.company IS NOT NULL THEN public.asli_reliability(m.source, 'company') ELSE 0 END
                  + CASE WHEN m.mfg     IS NOT NULL THEN public.asli_reliability(m.source, 'mfg')     ELSE 0 END
                  + CASE WHEN m.expiry  IS NOT NULL THEN public.asli_reliability(m.source, 'expiry')  ELSE 0 END)
                 / (1 + (m.name IS NOT NULL)::int + (m.company IS NOT NULL)::int
                      + (m.mfg IS NOT NULL)::int + (m.expiry IS NOT NULL)::int), 3) AS a,
           public.asli_reliability(m.source, 'ALL') AS s,
           (SELECT round(avg(cs.agree), 3) FROM cons cs
            WHERE cs.source = m.source AND cs.record_id IS NOT DISTINCT FROM m.record_id) AS q
    FROM mem m
),
w AS (   -- factor weights that can be used here, renormalised
    SELECT f.*,
           public.match_cfg('beta_entity') AS be,
           CASE WHEN f.c IS NULL THEN 0 ELSE public.match_cfg('beta_context') END AS bc,
           public.match_cfg('beta_completeness') AS bk,
           public.match_cfg('beta_attribute') AS ba,
           public.match_cfg('beta_source') AS bs,
           CASE WHEN f.q IS NULL THEN 0 ELSE public.match_cfg('beta_consistency') END AS bq
    FROM f
),
scored AS (
    SELECT w.*,
           round((w.be * w.e + w.bc * coalesce(w.c, 0) + w.bk * w.k + w.ba * w.a + w.bs * w.s + w.bq * coalesce(w.q, 0))
                 / (w.be + w.bc + w.bk + w.ba + w.bs + w.bq), 3) AS conf,
           jsonb_build_object('entity', round(w.be / (w.be + w.bc + w.bk + w.ba + w.bs + w.bq), 3),
                              'context', round(w.bc / (w.be + w.bc + w.bk + w.ba + w.bs + w.bq), 3),
                              'completeness', round(w.bk / (w.be + w.bc + w.bk + w.ba + w.bs + w.bq), 3),
                              'attribute', round(w.ba / (w.be + w.bc + w.bk + w.ba + w.bs + w.bq), 3),
                              'source', round(w.bs / (w.be + w.bc + w.bk + w.ba + w.bs + w.bq), 3),
                              'consistency', round(w.bq / (w.be + w.bc + w.bk + w.ba + w.bs + w.bq), 3)) AS wts
    FROM w
),
ranked AS (
    SELECT sc.*, row_number() OVER (ORDER BY sc.conf DESC, (sc.source = 'MANUFACTURER') DESC, sc.record_id)::int AS rnk
    FROM scored sc
),
-- does each record agree with the top one on every attribute both hold?
agr AS (
    SELECT r.*,
           NOT EXISTS (SELECT 1 FROM vals v1 JOIN vals v2 ON v2.attr = v1.attr
                       JOIN ranked t ON t.rnk = 1
                       WHERE v1.source = r.source AND v1.record_id IS NOT DISTINCT FROM r.record_id
                         AND v2.source = t.source AND v2.record_id IS NOT DISTINCT FROM t.record_id
                         AND v1.val <> v2.val) AS agrees_top
    FROM ranked r
)
SELECT r.rnk, r.source, r.record_id, r.stored_code, r.name, r.company, r.mfg, r.expiry,
       r.e, r.c, r.k, r.a, r.s, r.q, r.conf, r.wts,
       CASE WHEN (SELECT bool_and(x.agrees_top) FROM agr x)                     THEN 'ALL RECORDS AGREE'
            WHEN r.rnk > 1 AND r.agrees_top                                     THEN 'AGREES WITH THE TOP RECORD'
            WHEN r.rnk > 1                                                      THEN 'LESS RELIABLE'
            -- accepted when it is trusted enough AND clearly ahead of the records that
            -- DISAGREE with it: either by margin, or because the records agreeing with
            -- it carry most of the total confidence (a reliability-weighted vote)
            WHEN r.conf >= public.match_cfg('trust_accept')
                 AND (r.conf - coalesce((SELECT max(x.conf) FROM agr x WHERE NOT x.agrees_top), 0)
                          >= public.match_cfg('trust_margin')
                      OR (SELECT sum(x.conf) FILTER (WHERE x.agrees_top) / sum(x.conf) FROM agr x)
                          >= public.match_cfg('vote_accept_share'))             THEN 'MOST RELIABLE'
            ELSE 'REVIEW' END
FROM agr r
ORDER BY r.rnk
$$;

-- =====================================================================
-- Records that exist only while the step-1 / step-5 noise is present are
-- reported as SKIP once they have been cleansed.
WITH stored AS (
    SELECT r.source, r.stored_code, m.verdict, m.decided_item, m.dates_swapped
    FROM public.v_stored_records r
    CROSS JOIN LATERAL public.match_stored_record(r.source, r.record_id, 1) m
    WHERE (r.source = 'VENDOR'      AND r.stored_code IN ('ITEM000193', 'ITEM00017'))
       OR (r.source = 'DISTRIBUTOR' AND r.stored_code = 'ITEM0002B7')
),
t AS (
    SELECT 1 AS n, 'flags: every stored record checked' AS test,
           ((SELECT count(*) FROM v_stored_record_flags) = (SELECT count(*) FROM v_stored_records))::text AS got,
           'true' AS expected
    UNION ALL
    SELECT 2, 'buyer: noisy code + name gives MATCH ITEM000041',
           (SELECT verdict || ' ' || decided_item FROM search_by_pack('ITEM0O0041', 'Ibuprofen 400mg') LIMIT 1),
           'MATCH ITEM000041'
    UNION ALL
    SELECT 3, 'buyer: real code on wrong pack gives CLONED',
           (SELECT verdict FROM search_by_pack('ITEM000106', 'Amoxicillin 500mg', NULL, NULL, '12/2029') LIMIT 1),
           'POSSIBLE CLONED CODE'
    UNION ALL
    SELECT 4, 'vendor ITEM000193 gives WRONG CODE ITEM000139',
           (SELECT verdict || ' ' || decided_item FROM stored WHERE source = 'VENDOR' AND stored_code = 'ITEM000193'
              AND EXISTS (SELECT 1 FROM v_stored_record_flags WHERE source = 'VENDOR' AND stored_code = 'ITEM000193' AND status <> 'OK')),
           'WRONG CODE ITEM000139'
    UNION ALL
    SELECT 5, 'vendor ITEM00017 gives REVIEW',
           (SELECT verdict FROM stored WHERE stored_code = 'ITEM00017'), 'REVIEW'
    UNION ALL
    SELECT 6, 'distributor ITEM0002B7 gives ITEM000287, dates swapped',
           (SELECT verdict || ' ' || decided_item || ' ' || dates_swapped FROM stored WHERE stored_code = 'ITEM0002B7'),
           'MATCH ITEM000287 true'
)
SELECT test,
       CASE WHEN got IS NULL AND n >= 4 THEN 'SKIP (record already cleansed)'
            WHEN got = expected THEN 'PASS'
            ELSE 'FAIL (got ' || coalesce(got, 'nothing') || ')' END AS result
FROM t ORDER BY n;
