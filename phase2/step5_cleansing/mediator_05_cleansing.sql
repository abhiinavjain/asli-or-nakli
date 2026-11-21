-- =====================================================================
-- Asli-or-Nakli · Phase 2 · Step 5
-- Data cleansing: scan -> proposals -> per-database fix scripts -> log
-- RUN ON: mediator_db   (after steps 2 and 3)
-- In DBeaver run as a script: Alt+X.  Safe to run more than once
-- (tables are kept, functions are replaced).
-- =====================================================================
--
-- No database is treated as automatically correct. For every item the
-- mediator gathers what the manufacturer, distributor and vendor record and
-- takes a MAJORITY VOTE (2 of 3) for each field:
--
--   item code      per item (cluster = manufacturer row + the distributor and
--                  vendor records the matcher assigned to it)
--   expiry, mfg    per item, compared at month level (vendors store MM/YYYY)
--   medicine name  per medicine;    each database votes once with its usual value
--   manufacturer   per manufacturer; each database votes once with its usual value
--
--   majority      -> UPDATE every value that disagrees (in that database's own format)
--   no majority   -> REVIEW: options are listed, a person chooses
--   same item twice in one database -> DELETE the extra record
--   record no item fits -> REVIEW (choose an item, or delete the record)
--
-- The mediator never writes to the other databases. It produces a fix
-- script per database; each owner reviews and runs their own script.
-- cleansing_check() then compares the live data with the proposals and
-- writes every applied change to cleansing_log.
--
-- Noise in the other columns, using context:
--   medicine twice under look-alike codes (MED0O7)   -> move items, delete the copy
--   item recorded as the wrong medicine              -> majority of the databases holding its code
--   medicine linked to the wrong manufacturer        -> distributor + vendor agree on another one
--   missing / unreadable mfg, expiry, name, company  -> filled in from the majority
--   sale or approval under a noisy code              -> follows the item's corrected code
--   misspelt shop name in a supply record            -> closest shop (preferring the one holding the item)
--   received / supply / sale date before the item was made or in the future
--                                                    -> REVIEW, offering the typing slip that fits
--
-- Not changed here: distributor-ID mismatches between distributor and
-- vendor (Phase 1 supply-chain checks). They are fraud signals, not noise.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cleansing_scans (
    scan_id     serial PRIMARY KEY,
    started_at  timestamp DEFAULT now(),
    finished_at timestamp
);

CREATE TABLE IF NOT EXISTS public.cleansing_proposals (
    proposal_id  serial PRIMARY KEY,
    scan_id      int  NOT NULL REFERENCES public.cleansing_scans (scan_id),
    item_code    text,                -- the manufacturer item the record belongs to
    source       text NOT NULL,       -- MANUFACTURER / DISTRIBUTOR / VENDOR
    target_db    text NOT NULL,
    target_table text NOT NULL,
    key_column   text NOT NULL,
    key_value    int  NOT NULL,
    field        text NOT NULL,       -- code / name / company / mfg / expiry
    column_name  text NOT NULL,
    old_value    text,
    new_value    text,
    action       text NOT NULL CHECK (action IN ('UPDATE', 'DELETE', 'REVIEW')),
    reason       text NOT NULL,
    options      jsonb,               -- REVIEW only: { "option label": [fix, ...] }
    suggested    text,                -- REVIEW only: recommended option label
    status       text NOT NULL DEFAULT 'PROPOSED'
                 CHECK (status IN ('PROPOSED', 'APPLIED', 'RESOLVED', 'SUPERSEDED')),
    created_at   timestamp DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.cleansing_log (
    log_id       serial PRIMARY KEY,
    proposal_id  int REFERENCES public.cleansing_proposals (proposal_id),
    scan_id      int,
    target_db    text,
    target_table text,
    key_column   text,
    key_value    int,
    column_name  text,
    old_value    text,
    new_value    text,
    action       text,
    reason       text,
    detected_at  timestamp DEFAULT now()
);

-- which item every stored record was assigned to in each scan
CREATE TABLE IF NOT EXISTS public.cleansing_assignments (
    scan_id     int,
    source      text,
    record_id   int,
    stored_code text,
    item_code   text,
    how         text,
    duplicate   boolean,
    PRIMARY KEY (scan_id, source, record_id)
);

-- ---------------------------------------------------------------------
-- 2. Where each field lives in each database (schema mapping)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleansing_fix(
    p_source text, p_field text, p_key int, p_old text, p_new text,
    p_action text, p_reason text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_db text; v_table text; v_key text; v_col text;
BEGIN
    IF p_source = 'MEDIATOR' THEN                         -- the mediator's own approvals
        v_db := 'mediator_db'; v_table := 'approved_items'; v_key := 'approval_id'; v_col := 'item_code';
    ELSIF p_source = 'DISTRIBUTOR' AND p_field IN ('supply_shop', 'supply_date') THEN
        v_db := 'distributor_db'; v_table := 'supplied_items'; v_key := 'supply_item_id';
        v_col := CASE p_field WHEN 'supply_shop' THEN 'vendor_reference' ELSE 'supply_date' END;
    ELSIF p_source = 'DISTRIBUTOR' THEN
        v_db := 'distributor_db'; v_table := 'inventory_items'; v_key := 'inventory_id';
        v_col := CASE p_field WHEN 'code' THEN 'product_code' WHEN 'name' THEN 'drug_name'
                              WHEN 'company' THEN 'mfr_name' WHEN 'mfg' THEN 'mfg_date'
                              WHEN 'expiry' THEN 'exp_date' WHEN 'received' THEN 'received_date' END;
    ELSIF p_source = 'VENDOR' AND p_field IN ('sale_code', 'sale_date') THEN
        v_db := 'vendor_db'; v_table := 'medicine_sales'; v_key := 'sale_id';
        v_col := CASE p_field WHEN 'sale_code' THEN 'item_identifier' ELSE 'sale_date' END;
    ELSIF p_source = 'VENDOR' THEN
        v_db := 'vendor_db'; v_table := 'vendor_inventory'; v_key := 'inventory_id';
        v_col := CASE p_field WHEN 'code' THEN 'item_identifier' WHEN 'name' THEN 'medicine_name'
                              WHEN 'company' THEN 'company' WHEN 'mfg' THEN 'mfg'
                              WHEN 'expiry' THEN 'expiry' WHEN 'received' THEN 'received_date' END;
    ELSE
        v_db := 'manuf_db';
        IF p_field = 'name' THEN
            v_table := 'medicines'; v_key := 'medicine_id'; v_col := 'medicine_name';
        ELSIF p_field = 'maker' THEN                       -- which manufacturer makes a medicine
            v_table := 'medicines'; v_key := 'medicine_id'; v_col := 'manufacturer_id';
        ELSIF p_field = 'medicine_row' THEN                -- a whole (duplicate) medicine row
            v_table := 'medicines'; v_key := 'medicine_id'; v_col := 'medicine_code';
        ELSIF p_field = 'medicine' THEN                    -- which medicine an item is
            v_table := 'manufactured_items'; v_key := 'item_id'; v_col := 'medicine_code';
        ELSIF p_field = 'company' THEN
            v_table := 'manufacturers'; v_key := 'manufacturer_id'; v_col := 'manufacturer_name';
        ELSE
            v_table := 'manufactured_items'; v_key := 'item_id';
            v_col := CASE p_field WHEN 'code' THEN 'unique_item_code'
                                  WHEN 'mfg' THEN 'manufacturing_date'
                                  WHEN 'expiry' THEN 'expiry_date' END;
        END IF;
    END IF;
    RETURN jsonb_build_object(
        'source', p_source, 'target_db', v_db, 'target_table', v_table,
        'key_column', v_key, 'key_value', p_key, 'field', p_field, 'column_name', v_col,
        'old_value', p_old, 'new_value', p_new, 'action', p_action, 'reason', p_reason);
END;
$$;

CREATE OR REPLACE FUNCTION public.cleansing_add(p_scan int, p_item text, p_fix jsonb)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO public.cleansing_proposals
        (scan_id, item_code, source, target_db, target_table, key_column, key_value,
         field, column_name, old_value, new_value, action, reason)
    VALUES (p_scan, p_item, p_fix->>'source', p_fix->>'target_db', p_fix->>'target_table',
            p_fix->>'key_column', (p_fix->>'key_value')::int, p_fix->>'field', p_fix->>'column_name',
            p_fix->>'old_value', p_fix->>'new_value', p_fix->>'action', p_fix->>'reason')
$$;

-- a month as 'YYYY-MM' (how dates are compared: vendors only store month/year)
CREATE OR REPLACE FUNCTION public.cleansing_month(p_text text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT to_char(public.parse_pack_date(p_text), 'YYYY-MM')
$$;

-- dates a typing slip could have turned into p_date (two neighbouring digits
-- swapped, or day and month swapped) that fall between p_lo and p_hi
CREATE OR REPLACE FUNCTION public.cleansing_date_candidates(p_date date, p_lo date, p_hi date)
RETURNS SETOF date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    s  text := to_char(p_date, 'YYYYMMDD');
    t  text;
    d  date;
    i  int;
    seen date[] := '{}';
BEGIN
    FOR i IN 1..8 LOOP
        IF i = 8 THEN
            t := substr(s, 1, 4) || substr(s, 7, 2) || substr(s, 5, 2);       -- day and month swapped
        ELSE                                                                  -- digits i and i+1 swapped
            t := substr(s, 1, i - 1) || substr(s, i + 1, 1) || substr(s, i, 1) || substr(s, i + 2);
        END IF;
        BEGIN
            d := make_date(substr(t, 1, 4)::int, substr(t, 5, 2)::int, substr(t, 7, 2)::int);
        EXCEPTION WHEN others THEN
            CONTINUE;
        END;
        IF d <> p_date AND d BETWEEN p_lo AND p_hi AND NOT d = ANY (seen) THEN
            seen := seen || d;
            RETURN NEXT d;
        END IF;
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. The scan
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleansing_scan()
RETURNS int LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
    sid      int;
    r        record;
    c        record;
    v_verdict text;
    v_item   text;
    v_opts   jsonb;
    v_margin numeric := public.match_cfg('total_margin');
BEGIN
    INSERT INTO public.cleansing_scans DEFAULT VALUES RETURNING scan_id INTO sid;
    UPDATE public.cleansing_proposals SET status = 'SUPERSEDED' WHERE status = 'PROPOSED';
    PERFORM set_config('client_min_messages', 'warning', true);   -- hide 'does not exist, skipping' notices

    DROP TABLE IF EXISTS cs_g, cs_r, cs_map, cs_mem, cs_med, cs_final;

    -- one read of each remote table
    CREATE TEMP TABLE cs_g AS
    SELECT mi.item_id, mi.unique_item_code::text AS code, mi.medicine_code::text AS medicine_code,
           md.medicine_id, md.medicine_name::text AS medicine_name, md.composition::text AS composition,
           mf.manufacturer_id, mf.manufacturer_name::text AS manufacturer_name,
           mi.manufacturing_date AS mfg, mi.expiry_date AS exp
    FROM public.manufactured_items mi
    LEFT JOIN public.medicines md      ON md.medicine_code   = mi.medicine_code
    LEFT JOIN public.manufacturers mf  ON mf.manufacturer_id = md.manufacturer_id;

    CREATE TEMP TABLE cs_r AS
    SELECT s.source, s.record_id, s.stored_code, public.normalize_code(s.stored_code) AS ncode,
           s.name, s.company, s.mfg, s.expiry, s.vendor_id, s.received_date
    FROM public.v_stored_records s;

    -- every medicine with its manufacturer (also medicines no item uses)
    CREATE TEMP TABLE cs_med AS
    SELECT md.medicine_id, md.medicine_code::text AS medicine_code, md.medicine_name::text AS medicine_name,
           md.composition::text AS composition, mf.manufacturer_id, mf.manufacturer_name::text AS manufacturer_name,
           (SELECT count(*) FROM cs_g g WHERE g.medicine_code = md.medicine_code) AS n_items
    FROM public.medicines md
    LEFT JOIN public.manufacturers mf ON mf.manufacturer_id = md.manufacturer_id;

    CREATE TEMP TABLE cs_map (source text, record_id int, item_code text, how text,
                              dup boolean DEFAULT false);

    -- (m1) the same medicine recorded twice under look-alike codes (MED007 / MED0O7):
    --      move its items to the proper code, then remove the copy
    FOR c IN
        SELECT DISTINCT ON (n.medicine_id) n.medicine_id, n.medicine_code AS noisy,
               k.medicine_id AS keep_id, k.medicine_code AS keep
        FROM cs_med n
        JOIN cs_med k ON k.medicine_id <> n.medicine_id
                     AND public.normalize_medicine_name(k.medicine_name) = public.normalize_medicine_name(n.medicine_name)
                     AND k.manufacturer_id IS NOT DISTINCT FROM n.manufacturer_id
                     AND public.code_distance(upper(k.medicine_code), upper(n.medicine_code)) <= 1
        -- keep the one in the standard format MED + 3 digits, then the one with more items
        WHERE ((k.medicine_code ~ '^MED[0-9]{3}$')::int, k.n_items, -k.medicine_id)
            > ((n.medicine_code ~ '^MED[0-9]{3}$')::int, n.n_items, -n.medicine_id)
        ORDER BY n.medicine_id, k.n_items DESC
    LOOP
        PERFORM public.cleansing_add(sid, g.code,
            public.cleansing_fix('MANUFACTURER', 'medicine', g.item_id, c.noisy, c.keep, 'UPDATE',
                'Medicine code ' || c.noisy || ' is a look-alike copy of ' || c.keep
                || ' (same medicine and manufacturer): item moved to ' || c.keep))
        FROM cs_g g WHERE g.medicine_code = c.noisy;
        PERFORM public.cleansing_add(sid, NULL,
            public.cleansing_fix('MANUFACTURER', 'medicine_row', c.medicine_id, c.noisy, NULL, 'DELETE',
                'Same medicine recorded twice: ' || c.noisy || ' is a look-alike copy of ' || c.keep
                || ' (removed once no item uses it)'));
        UPDATE cs_g g
        SET medicine_code = k.medicine_code, medicine_id = k.medicine_id, medicine_name = k.medicine_name,
            composition = k.composition, manufacturer_id = k.manufacturer_id, manufacturer_name = k.manufacturer_name
        FROM cs_med k WHERE k.medicine_id = c.keep_id AND g.medicine_code = c.noisy;
        DELETE FROM cs_med WHERE medicine_id = c.medicine_id;
    END LOOP;

    -- (m2) an item recorded as the wrong medicine: the databases holding its exact
    --      code all name one other medicine, and none agrees with the manufacturer
    FOR c IN
        WITH ev AS (
            SELECT g.item_id, g.code, g.medicine_code AS old_med, g.medicine_name AS old_name,
                   r.source, r.record_id, r.name,
                   m2.medicine_id AS new_id, m2.medicine_code AS new_med, m2.medicine_name AS new_name
            FROM cs_g g
            JOIN cs_r r   ON r.ncode = g.code AND r.name IS NOT NULL
            JOIN cs_med m2 ON m2.medicine_code <> g.medicine_code
                          AND public.normalize_medicine_name(r.name)
                              IN (public.normalize_medicine_name(m2.medicine_name),
                                  public.normalize_medicine_name(m2.composition))
            WHERE greatest(public.medicine_name_similarity(r.name, g.medicine_name),
                           public.medicine_name_similarity(r.name, g.composition))
                  < public.match_cfg('conflict_name_below')
              AND NOT EXISTS (SELECT 1 FROM cs_r r2              -- nobody agrees with the manufacturer
                              WHERE r2.ncode = g.code AND r2.name IS NOT NULL
                                AND greatest(public.medicine_name_similarity(r2.name, g.medicine_name),
                                             public.medicine_name_similarity(r2.name, g.composition))
                                    >= public.match_cfg('conflict_name_below'))
        )
        SELECT item_id, code, old_med, old_name,
               max(new_id) AS new_id, max(new_med) AS new_med, max(new_name) AS new_name,
               count(DISTINCT source) AS n_src, max(source) AS one_source,
               max(record_id) AS one_record, max(name) AS one_name
        FROM ev
        GROUP BY item_id, code, old_med, old_name
        HAVING count(DISTINCT new_med) = 1 AND count(*) = count(DISTINCT source)
    LOOP
        IF c.n_src >= 2 THEN
            PERFORM public.cleansing_add(sid, c.code,
                public.cleansing_fix('MANUFACTURER', 'medicine', c.item_id, c.old_med, c.new_med, 'UPDATE',
                    'Item ' || c.code || ' is recorded as ' || c.old_name || ' (' || c.old_med || '), but '
                    || c.n_src || ' other databases hold it as ' || c.new_name || ' (' || c.new_med || ')'));
            UPDATE cs_g g
            SET medicine_code = k.medicine_code, medicine_id = k.medicine_id, medicine_name = k.medicine_name,
                composition = k.composition, manufacturer_id = k.manufacturer_id, manufacturer_name = k.manufacturer_name
            FROM cs_med k WHERE k.medicine_id = c.new_id AND g.item_id = c.item_id;
        ELSE
            -- 1 to 1: a person decides which side is wrong
            INSERT INTO cs_map (source, record_id, item_code, how)
            VALUES (c.one_source, c.one_record, c.code, 'exact code (medicine disputed)');
            INSERT INTO public.cleansing_proposals
                (scan_id, item_code, source, target_db, target_table, key_column, key_value,
                 field, column_name, old_value, action, reason, suggested, options)
            VALUES (sid, c.code, 'MANUFACTURER', 'manuf_db', 'manufactured_items', 'item_id', c.item_id,
                    'medicine', 'medicine_code', c.old_med, 'REVIEW',
                    'No majority for the medicine of this item: the manufacturer says ' || c.old_name
                    || ', the ' || lower(c.one_source) || ' says ' || c.one_name,
                    -- context: an item of the other medicine was made in the same batch (same dates)
                    CASE WHEN EXISTS (SELECT 1 FROM cs_g g1 JOIN cs_g g2 ON g2.item_id <> g1.item_id
                                      AND g2.mfg = g1.mfg AND g2.exp = g1.exp AND g2.medicine_code = c.new_med
                                      WHERE g1.item_id = c.item_id)
                          AND NOT EXISTS (SELECT 1 FROM cs_g g1 JOIN cs_g g2 ON g2.item_id <> g1.item_id
                                      AND g2.mfg = g1.mfg AND g2.exp = g1.exp AND g2.medicine_code = c.old_med
                                      WHERE g1.item_id = c.item_id)
                         THEN 'Manufacturer is wrong: ' || c.code || ' is ' || c.new_name || ' (' || c.new_med || ')'
                         WHEN EXISTS (SELECT 1 FROM cs_g g1 JOIN cs_g g2 ON g2.item_id <> g1.item_id
                                      AND g2.mfg = g1.mfg AND g2.exp = g1.exp AND g2.medicine_code = c.old_med
                                      WHERE g1.item_id = c.item_id)
                         THEN initcap(c.one_source) || ' is wrong: the medicine is ' || c.old_name END,
                    jsonb_build_object(
                        'Manufacturer is wrong: ' || c.code || ' is ' || c.new_name || ' (' || c.new_med || ')',
                        jsonb_build_array(public.cleansing_fix('MANUFACTURER', 'medicine', c.item_id, c.old_med, c.new_med,
                            'UPDATE', 'Chosen by reviewer: ' || c.code || ' is ' || c.new_name)),
                        initcap(c.one_source) || ' is wrong: the medicine is ' || c.old_name,
                        jsonb_build_array(public.cleansing_fix(c.one_source, 'name', c.one_record, c.one_name,
                            CASE WHEN c.one_source = 'DISTRIBUTOR' THEN upper(c.old_name) ELSE c.old_name END,
                            'UPDATE', 'Chosen by reviewer: the medicine is ' || c.old_name))));
        END IF;
    END LOOP;

    -- (a) code is a real item (after clean-up) and the medicine does not contradict it
    INSERT INTO cs_map (source, record_id, item_code, how)
    SELECT r.source, r.record_id, g.code, 'exact code'
    FROM cs_r r JOIN cs_g g ON g.code = r.ncode
    WHERE r.name IS NULL
       OR greatest(public.medicine_name_similarity(r.name, g.medicine_name),
                   public.medicine_name_similarity(r.name, g.composition))
          >= public.match_cfg('conflict_name_below');

    -- (b) every other record: ask the matcher (step 3)
    FOR r IN SELECT * FROM cs_r x
             WHERE NOT EXISTS (SELECT 1 FROM cs_map m WHERE m.source = x.source AND m.record_id = x.record_id)
               -- already reported as a counterfeit: evidence, not noise
               AND NOT EXISTS (SELECT 1 FROM public.reports rp
                               WHERE public.normalize_code(rp.item_identifier) = x.ncode
                                 AND rp.report_reason IN ('COUNTERFEIT CODE IN STOCK', 'CODE NOT FOUND'))
             ORDER BY x.source, x.record_id
    LOOP
        SELECT max(m.verdict), max(m.decided_item) INTO v_verdict, v_item
        FROM public.match_stored_record(r.source, r.record_id, 10) m;

        -- a valid-looking code (ITEM + 6 digits) the manufacturer does not have is
        -- not a typo of an item this database already holds under its exact code:
        -- e.g. the manufacturer's ITEM000011 was deleted, and ITEM000012 sits next
        -- to it on the same shelf. Treat it as a code nobody made (report / delete).
        -- (a database counts if it holds this exact code too: the distributor and the
        -- vendor then agree on it, and the distributor also holds the neighbour)
        IF v_item IS NOT NULL AND r.ncode ~ '^ITEM[0-9]{6}$'
           AND NOT EXISTS (SELECT 1 FROM cs_g g WHERE g.code = r.ncode)
           AND EXISTS (SELECT 1 FROM cs_r o
                       WHERE o.ncode = v_item AND o.record_id IS NOT NULL
                         AND NOT (o.source = r.source AND o.record_id = r.record_id)
                         AND (o.source = r.source
                              OR EXISTS (SELECT 1 FROM cs_r q WHERE q.source = o.source AND q.ncode = r.ncode))) THEN
            v_item := NULL;
            v_verdict := 'NO MATCH';
        END IF;

        IF v_item IS NOT NULL THEN
            INSERT INTO cs_map (source, record_id, item_code, how)
            VALUES (r.source, r.record_id, v_item, lower(v_verdict));
        ELSE
            -- REVIEW: every close candidate is an option, plus deleting the record
            SELECT coalesce(jsonb_object_agg(
                       x.item_code || ' · ' || x.medicine_name || ' (score ' || x.total_score || ')',
                       jsonb_build_array(public.cleansing_fix(r.source, 'code', r.record_id, r.stored_code,
                           x.item_code, 'UPDATE', 'Chosen by reviewer: record belongs to ' || x.item_code))),
                     '{}'::jsonb)
            INTO v_opts
            FROM (SELECT m.*, max(m.total_score) OVER () AS top
                  FROM public.match_stored_record(r.source, r.record_id, 10) m) x
            WHERE x.total_score >= x.top - v_margin
              AND v_verdict = 'REVIEW';          -- weak candidates of a NO MATCH are not options

            IF v_opts = '{}'::jsonb THEN      -- no item resembles it: counterfeit, keep as evidence
                v_opts := jsonb_build_object('Report as counterfeit (keep the record as evidence)', '[]'::jsonb);
            END IF;
            v_opts := v_opts || jsonb_build_object('Delete this record',
                        jsonb_build_array(public.cleansing_fix(r.source, 'code', r.record_id, r.stored_code,
                            NULL, 'DELETE', 'Chosen by reviewer: record matches no item')));

            INSERT INTO public.cleansing_proposals
                (scan_id, item_code, source, target_db, target_table, key_column, key_value,
                 field, column_name, old_value, action, reason, options, suggested)
            SELECT sid, NULL, f->>'source', f->>'target_db', f->>'target_table', f->>'key_column',
                   r.record_id, 'code', f->>'column_name', r.stored_code, 'REVIEW',
                   CASE WHEN v_verdict = 'REVIEW'
                        THEN 'Several items fit this record equally well (' || r.name || ', exp ' || coalesce(r.expiry, '?') || ')'
                        ELSE 'Code matches no item the manufacturer made: possible counterfeit in stock' END,
                   v_opts,
                   CASE WHEN v_verdict = 'REVIEW' THEN NULL
                        ELSE 'Report as counterfeit (keep the record as evidence)' END
            FROM (SELECT public.cleansing_fix(r.source, 'code', r.record_id, r.stored_code, NULL, 'REVIEW', '') AS f) z;
        END IF;
    END LOOP;

    -- (c) the same item recorded twice in one database: keep the cleanest record
    UPDATE cs_map m SET dup = true
    FROM (SELECT x.source, x.record_id,
                 row_number() OVER (PARTITION BY x.item_code, x.source
                                    ORDER BY (y.stored_code = x.item_code) DESC,
                                             (y.ncode = x.item_code) DESC, x.record_id) AS rn
          FROM cs_map x JOIN cs_r y ON y.source = x.source AND y.record_id = x.record_id) d
    WHERE d.source = m.source AND d.record_id = m.record_id AND d.rn > 1;

    PERFORM public.cleansing_add(sid, m.item_code,
        public.cleansing_fix(m.source, 'code', m.record_id, r2.stored_code, NULL, 'DELETE',
            'Same item recorded twice in this database (keeping record #' || k.record_id
            || ' ' || k.stored_code || ')'))
    FROM cs_map m
    JOIN cs_r r2 ON r2.source = m.source AND r2.record_id = m.record_id
    JOIN LATERAL (SELECT x.record_id, y.stored_code FROM cs_map x
                  JOIN cs_r y ON y.source = x.source AND y.record_id = x.record_id
                  WHERE x.item_code = m.item_code AND x.source = m.source AND NOT x.dup LIMIT 1) k ON true
    WHERE m.dup;

    INSERT INTO public.cleansing_assignments
    SELECT sid, m.source, m.record_id, r3.stored_code, m.item_code, m.how, m.dup
    FROM cs_map m JOIN cs_r r3 ON r3.source = m.source AND r3.record_id = m.record_id;

    -- (m3) a medicine linked to the wrong manufacturer: the distributor and the
    --      vendor both name another manufacturer that exists in manuf_db
    FOR c IN
        WITH recs AS (
            SELECT g.medicine_id, m.source, public.normalize_company(r.company) AS val, count(*) AS n
            FROM cs_map m
            JOIN cs_r r ON r.source = m.source AND r.record_id = m.record_id
            JOIN cs_g g ON g.code = m.item_code
            WHERE NOT m.dup AND m.how NOT LIKE '%disputed%' AND coalesce(r.company, '') <> ''
            GROUP BY 1, 2, 3
        ),
        top AS (
            SELECT DISTINCT ON (medicine_id, source) medicine_id, source, val
            FROM recs ORDER BY medicine_id, source, n DESC, val
        ),
        agreed AS (
            SELECT medicine_id, max(val) AS val FROM top
            GROUP BY medicine_id HAVING count(DISTINCT source) = 2 AND count(DISTINCT val) = 1
        )
        SELECT md.medicine_id, md.medicine_code, md.medicine_name, md.manufacturer_id AS old_id,
               md.manufacturer_name AS old_name, mf.manufacturer_id AS new_id, mf.manufacturer_name::text AS new_name
        FROM agreed a
        JOIN cs_med md ON md.medicine_id = a.medicine_id
        JOIN public.manufacturers mf ON public.normalize_company(mf.manufacturer_name) = a.val
        WHERE a.val <> public.normalize_company(md.manufacturer_name)
          AND (SELECT count(*) FROM public.manufacturers x WHERE public.normalize_company(x.manufacturer_name) = a.val) = 1
    LOOP
        PERFORM public.cleansing_add(sid, NULL,
            public.cleansing_fix('MANUFACTURER', 'maker', c.medicine_id, c.old_id::text, c.new_id::text, 'UPDATE',
                c.medicine_name || ' (' || c.medicine_code || ') is linked to ' || c.old_name
                || ', but the distributor and the vendor both say it is made by ' || c.new_name
                || ' (manufacturer_id ' || c.old_id || ' to ' || c.new_id || ')'));
        UPDATE cs_g SET manufacturer_id = c.new_id, manufacturer_name = c.new_name WHERE medicine_id = c.medicine_id;
        UPDATE cs_med SET manufacturer_id = c.new_id, manufacturer_name = c.new_name WHERE medicine_id = c.medicine_id;
    END LOOP;

    -- (d) the manufacturer recorded the same item twice: an item no database
    --     holds, differing from a held item only by look-alike characters,
    --     with the same medicine and dates
    PERFORM public.cleansing_add(sid, d.code,
        public.cleansing_fix('MANUFACTURER', 'code', d.item_id, d.code, NULL, 'DELETE',
            'Same item recorded twice by the manufacturer: ' || d.code || ' is a look-alike copy of '
            || d.twin || ' (same medicine and dates; only ' || d.twin || ' is held by other databases)'))
    FROM (SELECT DISTINCT ON (g.item_id) g.item_id, g.code, g2.code AS twin
          FROM cs_g g
          JOIN cs_g g2 ON g2.item_id <> g.item_id AND g2.medicine_code = g.medicine_code
                      AND g2.mfg = g.mfg AND g2.exp = g.exp
          WHERE NOT EXISTS (SELECT 1 FROM cs_map m WHERE m.item_code = g.code)
            AND EXISTS (SELECT 1 FROM cs_map m WHERE m.item_code = g2.code AND NOT m.dup)
            AND public.code_distance(g.code, g2.code) < 0.5
          ORDER BY g.item_id, g2.item_id) d;

    -- (d2) a manufacturer code written with look-alike letters (ITEM0003O0) that no
    --      other database holds. Read with the letters as digits it becomes a code
    --      in the standard format (ITEM000300).
    --      * that code is free  -> UPDATE, formatting only
    --      * that code is taken -> REVIEW: two codes that read the same break the
    --        one-code-one-item rule (a buyer cannot tell them apart)
    FOR c IN
        SELECT g.item_id, g.code, t.std,
               (SELECT g2.code FROM cs_g g2 WHERE g2.code = t.std AND g2.item_id <> g.item_id LIMIT 1) AS taken,
               g.mfg, g.exp
        FROM cs_g g,
             LATERAL (SELECT 'ITEM' || translate(substr(public.normalize_code(g.code), 5),
                                                 'OQDILZSGB', '000112568') AS std) t
        WHERE g.code !~ '^ITEM[0-9]{6}$'
          AND t.std ~ '^ITEM[0-9]{6}$'
          AND NOT EXISTS (SELECT 1 FROM cs_map m WHERE m.item_code = g.code)
          AND NOT EXISTS (SELECT 1 FROM public.cleansing_proposals p
                          WHERE p.scan_id = sid AND p.source = 'MANUFACTURER' AND p.key_value = g.item_id)
    LOOP
        IF c.taken IS NULL THEN
            PERFORM public.cleansing_add(sid, c.std,
                public.cleansing_fix('MANUFACTURER', 'code', c.item_id, c.code, c.std, 'UPDATE',
                    'Formatting only: code ' || c.code || ' is written with look-alike letters; standard form ' || c.std));
        ELSE
            INSERT INTO public.cleansing_proposals
                (scan_id, item_code, source, target_db, target_table, key_column, key_value,
                 field, column_name, old_value, action, reason, options, suggested)
            SELECT sid, c.code, 'MANUFACTURER', f->>'target_db', f->>'target_table', f->>'key_column',
                   c.item_id, 'code', f->>'column_name', c.code, 'REVIEW',
                   'Code ' || c.code || ' reads the same as the existing item ' || c.taken
                   || ' (look-alike letters) but has other dates (mfg ' || c.mfg || ', exp ' || c.exp
                   || '). No other database holds ' || c.code || '.',
                   jsonb_build_object(
                       'Delete ' || c.code || ' (misprinted copy of ' || c.taken || ')',
                       jsonb_build_array(public.cleansing_fix('MANUFACTURER', 'code', c.item_id, c.code, NULL, 'DELETE',
                           'Chosen by reviewer: ' || c.code || ' is a misprinted copy of ' || c.taken)),
                       'Keep it for now (manufacturer must issue it a new code by hand)', '[]'::jsonb),
                   'Delete ' || c.code || ' (misprinted copy of ' || c.taken || ')'
            FROM (SELECT public.cleansing_fix('MANUFACTURER', 'code', c.item_id, c.code, NULL, 'REVIEW', '') AS f) z;
        END IF;
    END LOOP;

    -- (e) members of every item: the manufacturer row + its non-duplicate records
    CREATE TEMP TABLE cs_mem AS
    SELECT g.code AS item_code, 'MANUFACTURER'::text AS source, g.item_id AS key,
           g.code AS raw_code, g.code AS code_val,
           g.mfg::text AS raw_mfg, to_char(g.mfg, 'YYYY-MM') AS mfg_val,
           g.exp::text AS raw_exp, to_char(g.exp, 'YYYY-MM') AS exp_val
    FROM cs_g g
    WHERE EXISTS (SELECT 1 FROM cs_map m WHERE m.item_code = g.code AND NOT m.dup)
    UNION ALL
    SELECT m.item_code, m.source, m.record_id,
           r4.stored_code, r4.ncode,
           r4.mfg, public.cleansing_month(r4.mfg),
           r4.expiry, public.cleansing_month(r4.expiry)
    FROM cs_map m JOIN cs_r r4 ON r4.source = m.source AND r4.record_id = m.record_id
    WHERE NOT m.dup;

    -- (f) item code, mfg date, expiry date: majority per item
    FOR c IN
        WITH v AS (
            SELECT item_code, 'code' AS field, source, key, raw_code AS raw, code_val AS val FROM cs_mem
            UNION ALL SELECT item_code, 'mfg',    source, key, raw_mfg, mfg_val FROM cs_mem
            UNION ALL SELECT item_code, 'expiry', source, key, raw_exp, exp_val FROM cs_mem
        ),
        -- each database's opinion is weighted by how reliable that database has been
        -- for this field (learned from earlier fixes; 0.9 for everyone without history)
        cnt AS (
            SELECT item_code, field, val, count(*) AS n,
                   sum(public.asli_reliability(source, field)) AS w
            FROM v WHERE val IS NOT NULL GROUP BY 1, 2, 3
        ),
        ranked AS (
            SELECT cnt.*, rank() OVER (PARTITION BY item_code, field ORDER BY w DESC) AS rk,
                   w / sum(w) OVER (PARTITION BY item_code, field) AS share
            FROM cnt
        ),
        verdict AS (
            SELECT item_code, field,
                   max(val)   FILTER (WHERE rk = 1)                        AS top_val,
                   max(n)     FILTER (WHERE rk = 1)                        AS top_n,
                   max(share) FILTER (WHERE rk = 1)                        AS top_share,
                   count(*)   FILTER (WHERE rk = 1)                        AS n_top,
                   count(*)                                                AS n_vals
            FROM ranked GROUP BY 1, 2
        )
        SELECT vd.*,
               CASE
                 -- a code with letters among the digits (ITEM00008S) is never a valid
                 -- code: if exactly one value is in the standard format ITEM + 6 digits,
                 -- it wins, even against two databases holding the same noisy code
                 WHEN vd.field = 'code' AND vd.n_vals > 1
                      AND (SELECT count(DISTINCT x.val) FROM cnt x WHERE x.item_code = vd.item_code
                             AND x.field = 'code' AND x.val ~ '^ITEM[0-9]{6}$') = 1
                   THEN (SELECT max(x.val) FROM cnt x WHERE x.item_code = vd.item_code
                           AND x.field = 'code' AND x.val ~ '^ITEM[0-9]{6}$')
                 -- two valid-looking codes disagree: the manufacturer issues the codes,
                 -- so its code is kept (distributor + vendor sharing a typo is their noise)
                 WHEN vd.field = 'code' AND vd.n_vals > 1
                      AND (SELECT max(x.val) FROM v x WHERE x.item_code = vd.item_code AND x.field = 'code'
                             AND x.source = 'MANUFACTURER') ~ '^ITEM[0-9]{6}$'
                   THEN (SELECT max(x.val) FROM v x WHERE x.item_code = vd.item_code AND x.field = 'code'
                           AND x.source = 'MANUFACTURER')
                 -- the value with most reliability-weighted support wins when its share is
                 -- high enough (equal reliability: 2 of 3 = 0.67 wins, 1 to 1 = 0.5 goes to REVIEW)
                 WHEN vd.n_top = 1 AND vd.top_share >= public.match_cfg('vote_accept_share')
                      AND (vd.field <> 'code' OR vd.top_val ~ '^ITEM[0-9]{6}$') THEN vd.top_val
               END AS winner
        FROM verdict vd
        WHERE vd.n_vals > 1
           OR EXISTS (SELECT 1 FROM v                      -- formatting differences only
                      WHERE v.item_code = vd.item_code AND v.field = vd.field AND v.val IS NOT NULL
                        AND ((v.field = 'code' AND v.raw <> v.val)
                          OR (v.field <> 'code' AND v.source = 'VENDOR' AND v.raw !~ '^\d{2}/\d{4}$')))
           OR EXISTS (SELECT 1 FROM v                      -- a date that is missing or unreadable (40/2026)
                      WHERE v.item_code = vd.item_code AND v.field = vd.field
                        AND v.field <> 'code' AND v.val IS NULL)
    LOOP
        IF c.winner IS NOT NULL THEN
            -- majority: fix every value that differs, in that database's own format
            PERFORM public.cleansing_add(sid, c.item_code,
                public.cleansing_fix(v.source, c.field, v.key, v.raw,
                    CASE WHEN c.field = 'code' THEN c.winner
                         WHEN v.source = 'VENDOR' THEN to_char(to_date(c.winner, 'YYYY-MM'), 'MM/YYYY')
                         ELSE coalesce(        -- an exact date from a database that has the right month
                              (SELECT CASE c.field WHEN 'mfg' THEN m2.raw_mfg ELSE m2.raw_exp END
                               FROM cs_mem m2
                               WHERE m2.item_code = c.item_code AND m2.source = 'DISTRIBUTOR'
                                 AND CASE c.field WHEN 'mfg' THEN m2.mfg_val ELSE m2.exp_val END = c.winner
                               LIMIT 1),
                              (SELECT CASE c.field WHEN 'mfg' THEN m2.raw_mfg ELSE m2.raw_exp END
                               FROM cs_mem m2
                               WHERE m2.item_code = c.item_code AND m2.source = 'MANUFACTURER'
                                 AND CASE c.field WHEN 'mfg' THEN m2.mfg_val ELSE m2.exp_val END = c.winner
                               LIMIT 1),
                              to_date(c.winner, 'YYYY-MM')::text)
                    END,
                    'UPDATE',
                    CASE
                      WHEN v.val = c.winner AND c.field = 'code'
                        THEN 'Formatting only: stored as ''' || v.raw || ''''
                      WHEN c.field = 'code' AND v.val !~ '^ITEM[0-9]{6}$'
                        THEN 'Code ' || v.raw || ' is not a valid code (letters among the digits); '
                             || 'the only code in the standard format for this item is ' || c.winner
                      WHEN c.field = 'code' AND c.winner IS DISTINCT FROM c.top_val
                        THEN 'Codes disagree (' || lower(v.source) || ' has ' || v.raw || '); the manufacturer '
                             || 'issues item codes, so its code ' || c.winner || ' is kept'
                      WHEN v.val = c.winner
                        THEN 'Formatting only: date written as ''' || v.raw || ''''
                      WHEN v.raw IS NULL
                        THEN 'Missing ' || c.field || ': filled in from the ' || c.top_n || ' databases that agree'
                      WHEN v.val IS NULL
                        THEN 'Impossible ' || c.field || ' ''' || v.raw || ''' (not a real date): '
                             || c.top_n || ' databases record ' || c.winner
                      WHEN c.top_n >= 2 THEN c.top_n || ' of the databases record ' || c.field || ' = ' || c.winner
                           || ', ' || lower(v.source) || ' has ' || v.raw
                      ELSE 'The more reliable database (' || round(100 * c.top_share) || '% of the weighted support) records '
                           || c.field || ' = ' || c.winner
                           || ', ' || lower(v.source) || ' has ' || v.raw
                    END))
            FROM (SELECT m.source, m.key,
                         CASE c.field WHEN 'code' THEN m.raw_code WHEN 'mfg' THEN m.raw_mfg ELSE m.raw_exp END AS raw,
                         CASE c.field WHEN 'code' THEN m.code_val WHEN 'mfg' THEN m.mfg_val ELSE m.exp_val END AS val
                  FROM cs_mem m WHERE m.item_code = c.item_code) v
            WHERE (v.raw IS NOT NULL OR c.field <> 'code')
              AND (v.val IS DISTINCT FROM c.winner
                   OR (c.field = 'code' AND v.raw <> c.winner)
                   OR (c.field <> 'code' AND v.source = 'VENDOR' AND v.raw !~ '^\d{2}/\d{4}$'));
        ELSE
            -- no majority: one option per value; each option fixes everything else
            SELECT jsonb_object_agg(o.val || ' (' || o.held_by || ')', o.fixes) INTO v_opts
            FROM (
                SELECT ov.val,
                       string_agg(DISTINCT lower(ov2.source), ' + ') AS held_by,
                       (SELECT jsonb_agg(public.cleansing_fix(x.source, c.field, x.key, x.raw,
                                   CASE WHEN c.field = 'code' THEN ov.val
                                        WHEN x.source = 'VENDOR' THEN to_char(to_date(ov.val, 'YYYY-MM'), 'MM/YYYY')
                                        ELSE coalesce(      -- the exact date held by a database with this month
                                             (SELECT CASE c.field WHEN 'mfg' THEN m3.raw_mfg ELSE m3.raw_exp END
                                              FROM cs_mem m3
                                              WHERE m3.item_code = c.item_code AND m3.source <> 'VENDOR'
                                                AND CASE c.field WHEN 'mfg' THEN m3.mfg_val ELSE m3.exp_val END = ov.val
                                              ORDER BY (m3.source = 'DISTRIBUTOR') DESC LIMIT 1),
                                             to_date(ov.val, 'YYYY-MM')::text) END,
                                   'UPDATE', 'Chosen by reviewer: ' || c.field || ' = ' || ov.val))
                        FROM (SELECT m.source, m.key,
                                     CASE c.field WHEN 'code' THEN m.raw_code WHEN 'mfg' THEN m.raw_mfg ELSE m.raw_exp END AS raw,
                                     CASE c.field WHEN 'code' THEN m.code_val WHEN 'mfg' THEN m.mfg_val ELSE m.exp_val END AS val
                              FROM cs_mem m WHERE m.item_code = c.item_code) x
                        WHERE x.val IS DISTINCT FROM ov.val) AS fixes
                FROM (SELECT DISTINCT CASE c.field WHEN 'code' THEN m.code_val WHEN 'mfg' THEN m.mfg_val ELSE m.exp_val END AS val
                      FROM cs_mem m WHERE m.item_code = c.item_code) ov
                JOIN cs_mem ov2 ON ov2.item_code = c.item_code
                 AND CASE c.field WHEN 'code' THEN ov2.code_val WHEN 'mfg' THEN ov2.mfg_val ELSE ov2.exp_val END = ov.val
                WHERE ov.val IS NOT NULL
                GROUP BY ov.val
            ) o;

            INSERT INTO public.cleansing_proposals
                (scan_id, item_code, source, target_db, target_table, key_column, key_value,
                 field, column_name, old_value, action, reason, options, suggested)
            SELECT sid, c.item_code, 'MANUFACTURER', f->>'target_db', f->>'target_table', f->>'key_column',
                   g.item_id, c.field, f->>'column_name',
                   CASE c.field WHEN 'code' THEN g.code WHEN 'mfg' THEN g.mfg::text ELSE g.exp::text END,
                   'REVIEW',
                   'No majority for ' || c.field || ' of this item: the databases disagree 1 to 1',
                   v_opts,
                   -- for codes, recommend the one value in the standard format ITEM + 6 digits
                   CASE WHEN c.field = 'code' THEN
                       (SELECT max(k) FROM jsonb_object_keys(v_opts) k
                        WHERE k ~ '^ITEM[0-9]{6} '
                        HAVING count(*) = 1)
                   END
            FROM cs_g g, LATERAL (SELECT public.cleansing_fix('MANUFACTURER', c.field, g.item_id, NULL, NULL, 'REVIEW', '') AS f) z
            WHERE g.code = c.item_code;
        END IF;
    END LOOP;

    -- (g) medicine name per medicine and manufacturer name per manufacturer:
    --     each database votes once with the value it uses most often
    FOR c IN
        WITH recs AS (
            SELECT m.source, m.record_id, g.medicine_id, g.manufacturer_id,
                   r5.name, r5.company,
                   CASE WHEN public.normalize_medicine_name(r5.name) = public.normalize_medicine_name(g.composition)
                        THEN public.normalize_medicine_name(g.medicine_name)       -- composition used as name: agrees
                        ELSE public.normalize_medicine_name(r5.name) END            AS name_val,
                   public.normalize_company(r5.company)                             AS company_val
            FROM cs_map m
            JOIN cs_r r5 ON r5.source = m.source AND r5.record_id = m.record_id
            JOIN cs_g g  ON g.code = m.item_code
            WHERE NOT m.dup AND m.how NOT LIKE '%disputed%'
        ),
        opinions AS (       -- the manufacturer, and each other database's most common value
            SELECT DISTINCT 'name' AS field, g.medicine_id AS grp, 'MANUFACTURER' AS source,
                   public.normalize_medicine_name(g.medicine_name) AS val
            FROM cs_g g WHERE g.medicine_id IN (SELECT medicine_id FROM recs)
            UNION ALL
            (SELECT DISTINCT ON (medicine_id, source) 'name', medicine_id, source, name_val
             FROM (SELECT medicine_id, source, name_val, count(*) AS n FROM recs
                   WHERE name_val <> '' GROUP BY 1, 2, 3) x
             ORDER BY medicine_id, source, n DESC, name_val)
        ),
        opinions2 AS (
            SELECT * FROM opinions
            UNION ALL
            SELECT DISTINCT 'company', g.manufacturer_id, 'MANUFACTURER', public.normalize_company(g.manufacturer_name)
            FROM cs_g g WHERE g.manufacturer_id IN (SELECT manufacturer_id FROM recs)
            UNION ALL
            (SELECT DISTINCT ON (manufacturer_id, source) 'company', manufacturer_id, source, company_val
             FROM (SELECT manufacturer_id, source, company_val, count(*) AS n FROM recs
                   WHERE company_val <> '' GROUP BY 1, 2, 3) x
             ORDER BY manufacturer_id, source, n DESC, company_val)
        ),
        cnt AS (SELECT field, grp, val, count(*) AS n FROM opinions2 GROUP BY 1, 2, 3),
        ranked AS (SELECT cnt.*, rank() OVER (PARTITION BY field, grp ORDER BY n DESC) AS rk FROM cnt)
        SELECT field, grp,
               CASE WHEN count(*) FILTER (WHERE rk = 1) = 1 AND max(n) FILTER (WHERE rk = 1) >= 2
                    THEN max(val) FILTER (WHERE rk = 1) END AS winner,
               count(*) AS n_vals,
               max(n) FILTER (WHERE rk = 1) AS top_n
        FROM ranked GROUP BY field, grp
    LOOP
        IF c.winner IS NULL AND c.n_vals > 1 THEN
            -- no majority: list the values for a person to decide (fix by hand)
            INSERT INTO public.cleansing_proposals
                (scan_id, item_code, source, target_db, target_table, key_column, key_value,
                 field, column_name, old_value, action, reason, options)
            SELECT sid, NULL, 'MANUFACTURER', 'manuf_db',
                   CASE c.field WHEN 'name' THEN 'medicines' ELSE 'manufacturers' END,
                   CASE c.field WHEN 'name' THEN 'medicine_id' ELSE 'manufacturer_id' END,
                   c.grp, c.field,
                   CASE c.field WHEN 'name' THEN 'medicine_name' ELSE 'manufacturer_name' END,
                   CASE c.field WHEN 'name' THEN (SELECT max(medicine_name) FROM cs_g WHERE medicine_id = c.grp)
                                ELSE (SELECT max(manufacturer_name) FROM cs_g WHERE manufacturer_id = c.grp) END,
                   'REVIEW',
                   'No majority for the ' || CASE c.field WHEN 'name' THEN 'medicine name' ELSE 'manufacturer name' END
                   || ': the databases disagree 1 to 1 - correct it by hand in the database that is wrong',
                   NULL;
            CONTINUE;
        END IF;
        CONTINUE WHEN c.winner IS NULL;

        -- the winning value written out: manufacturer's own spelling if it agrees,
        -- otherwise the most common spelling in mixed case among the records
        PERFORM public.cleansing_add(sid, NULL, fx)
        FROM (
            WITH recs AS (
                SELECT m.source, m.record_id, g.medicine_id, g.manufacturer_id, g.medicine_name,
                       g.composition, g.manufacturer_name, r6.name, r6.company
                FROM cs_map m
                JOIN cs_r r6 ON r6.source = m.source AND r6.record_id = m.record_id
                JOIN cs_g g  ON g.code = m.item_code
                WHERE NOT m.dup AND m.how NOT LIKE '%disputed%'
                  AND ((c.field = 'name' AND g.medicine_id = c.grp)
                    OR (c.field = 'company' AND g.manufacturer_id = c.grp))
            ),
            vals AS (
                SELECT source, record_id,
                       CASE c.field WHEN 'name' THEN name ELSE company END AS raw,
                       CASE WHEN c.field = 'name' AND public.normalize_medicine_name(name) = public.normalize_medicine_name(composition)
                            THEN public.normalize_medicine_name(medicine_name)
                            WHEN c.field = 'name' THEN public.normalize_medicine_name(name)
                            ELSE public.normalize_company(company) END AS val
                FROM recs
            ),
            mfr AS (
                SELECT CASE c.field WHEN 'name' THEN max(medicine_name) ELSE max(manufacturer_name) END AS raw
                FROM cs_g g WHERE (c.field = 'name' AND g.medicine_id = c.grp)
                               OR (c.field = 'company' AND g.manufacturer_id = c.grp)
            ),
            rep AS (
                SELECT coalesce(
                    (SELECT raw FROM mfr
                     WHERE (c.field = 'name' AND public.normalize_medicine_name(raw) = c.winner)
                        OR (c.field = 'company' AND public.normalize_company(raw) = c.winner)),
                    (SELECT raw FROM vals WHERE val = c.winner AND raw <> upper(raw)
                     GROUP BY raw ORDER BY count(*) DESC, raw LIMIT 1),
                    (SELECT raw FROM vals WHERE val = c.winner
                     GROUP BY raw ORDER BY count(*) DESC, raw LIMIT 1)) AS raw
            )
            -- the manufacturer, if it lost
            SELECT public.cleansing_fix('MANUFACTURER', c.field, c.grp, mfr.raw, rep.raw, 'UPDATE',
                       c.top_n || ' of the databases spell the ' || CASE c.field WHEN 'name' THEN 'medicine' ELSE 'manufacturer' END
                       || ' ''' || rep.raw || ''', the manufacturer has ''' || mfr.raw || '''') AS fx
            FROM mfr, rep
            WHERE (c.field = 'name' AND public.normalize_medicine_name(mfr.raw) <> c.winner)
               OR (c.field = 'company' AND public.normalize_company(mfr.raw) <> c.winner)
            UNION ALL
            -- every record that disagrees, in its database's own style
            SELECT public.cleansing_fix(v.source, c.field, v.record_id, v.raw,
                       CASE WHEN v.source = 'DISTRIBUTOR' THEN upper(rep.raw) ELSE rep.raw END, 'UPDATE',
                       CASE WHEN coalesce(btrim(v.raw), '') = ''
                            THEN 'Missing ' || CASE c.field WHEN 'name' THEN 'medicine' ELSE 'manufacturer' END
                                 || ' name: filled in as ''' || rep.raw || ''' (what the other databases record)'
                            ELSE 'Misspelt ' || CASE c.field WHEN 'name' THEN 'medicine' ELSE 'manufacturer' END
                                 || ' name: ''' || v.raw || ''' should be ''' || rep.raw || '''' END)
            FROM vals v, rep
            WHERE coalesce(btrim(v.raw), '') = '' OR v.val <> c.winner
        ) z;
    END LOOP;

    -- (h) explain swapped dates in one line
    UPDATE public.cleansing_proposals p
    SET reason = 'Manufacturing and expiry dates swapped (' || p.old_value || ' should be ' || p.new_value || ')'
    WHERE p.scan_id = sid AND p.action = 'UPDATE' AND p.field IN ('mfg', 'expiry')
      AND EXISTS (SELECT 1 FROM public.cleansing_proposals q
                  WHERE q.scan_id = sid AND q.source = p.source AND q.key_value = p.key_value
                    AND q.action = 'UPDATE' AND q.field IN ('mfg', 'expiry') AND q.field <> p.field
                    AND public.cleansing_month(q.old_value) = public.cleansing_month(p.new_value)
                    AND public.cleansing_month(p.old_value) = public.cleansing_month(q.new_value));

    -- every item's code and mfg date once this scan's fixes are applied
    CREATE TEMP TABLE cs_final AS
    SELECT g.item_id, g.code AS item_code,
           coalesce((SELECT p.new_value FROM public.cleansing_proposals p
                     WHERE p.scan_id = sid AND p.source = 'MANUFACTURER' AND p.field = 'code'
                       AND p.action = 'UPDATE' AND p.key_value = g.item_id LIMIT 1), g.code) AS final_code,
           coalesce((SELECT p.new_value::date FROM public.cleansing_proposals p
                     WHERE p.scan_id = sid AND p.source = 'MANUFACTURER' AND p.field = 'mfg'
                       AND p.action = 'UPDATE' AND p.key_value = g.item_id LIMIT 1), g.mfg) AS mfg
    FROM cs_g g
    WHERE NOT EXISTS (SELECT 1 FROM public.cleansing_proposals p
                      WHERE p.scan_id = sid AND p.source = 'MANUFACTURER' AND p.field = 'code'
                        AND p.action = 'DELETE' AND p.key_value = g.item_id);

    -- (i) sales recorded under a code that is being corrected in the shop's stock
    PERFORM public.cleansing_add(sid, f.item_code,
        public.cleansing_fix('VENDOR', 'sale_code', s.sale_id, s.item_identifier, f.final_code, 'UPDATE',
            'Sale recorded under the stock code ' || s.item_identifier || ', which is being corrected to '
            || f.final_code || ' (otherwise the item would no longer show as sold)'))
    FROM public.medicine_sales s
    JOIN cs_r r     ON r.source = 'VENDOR' AND r.stored_code = s.item_identifier AND r.vendor_id = s.vendor_id
    JOIN cs_map m   ON m.source = 'VENDOR' AND m.record_id = r.record_id
    JOIN cs_final f ON f.item_code = m.item_code
    WHERE s.item_identifier <> f.final_code
      AND NOT EXISTS (SELECT 1 FROM public.medicine_sales s2 WHERE s2.item_identifier = f.final_code);

    -- (j) sales whose code the shop never stocked: the closest unsold code in that shop's stock
    FOR c IN
        SELECT s.sale_id, s.item_identifier, s.vendor_id, x.final_code, x.item_code, x.sim, x.sim2
        FROM public.medicine_sales s
        LEFT JOIN LATERAL (
            SELECT f.final_code, f.item_code,
                   public.code_similarity(public.normalize_code(s.item_identifier), f.final_code) AS sim,
                   lead(public.code_similarity(public.normalize_code(s.item_identifier), f.final_code))
                       OVER (ORDER BY public.code_similarity(public.normalize_code(s.item_identifier), f.final_code) DESC) AS sim2
            FROM cs_map m
            JOIN cs_r r     ON r.source = m.source AND r.record_id = m.record_id
            JOIN cs_final f ON f.item_code = m.item_code
            WHERE m.source = 'VENDOR' AND NOT m.dup AND r.vendor_id = s.vendor_id
              AND NOT EXISTS (SELECT 1 FROM public.medicine_sales s2
                              WHERE s2.item_identifier IN (f.final_code, r.stored_code))
            ORDER BY 3 DESC LIMIT 1) x ON true
        WHERE NOT EXISTS (SELECT 1 FROM cs_r r WHERE r.source = 'VENDOR' AND r.vendor_id = s.vendor_id
                                                 AND r.stored_code = s.item_identifier)
    LOOP
        IF c.sim >= public.match_cfg('min_code_similarity') AND (c.sim2 IS NULL OR c.sim2 < c.sim) THEN
            PERFORM public.cleansing_add(sid, c.item_code,
                public.cleansing_fix('VENDOR', 'sale_code', c.sale_id, c.item_identifier, c.final_code, 'UPDATE',
                    'Sale code ' || c.item_identifier || ' is not in this shop''s stock; the closest unsold item it stocks is '
                    || c.final_code || ' (code similarity ' || round(c.sim, 2) || ')'));
        ELSE
            INSERT INTO public.cleansing_proposals
                (scan_id, item_code, source, target_db, target_table, key_column, key_value,
                 field, column_name, old_value, action, reason, options)
            VALUES (sid, NULL, 'VENDOR', 'vendor_db', 'medicine_sales', 'sale_id', c.sale_id, 'sale_code',
                    'item_identifier', c.item_identifier, 'REVIEW',
                    'Sale of a code this shop never stocked and no stocked code is close enough: correct it by hand',
                    NULL);
        END IF;
    END LOOP;

    -- (k) the shop named in a supply record is misspelt
    FOR c IN
        SELECT s.supply_item_id, s.product_code, s.vendor_reference, b.vendor_name, b.sim
        FROM public.supplied_items s
        LEFT JOIN LATERAL (
            SELECT v.vendor_name::text AS vendor_name,
                   public.trigram_similarity(lower(v.vendor_name), lower(s.vendor_reference)) AS sim,
                   EXISTS (SELECT 1 FROM cs_r rd
                           JOIN cs_map md ON md.source = rd.source AND md.record_id = rd.record_id
                           JOIN cs_map mv ON mv.item_code = md.item_code AND mv.source = 'VENDOR'
                           JOIN cs_r rv   ON rv.source = mv.source AND rv.record_id = mv.record_id
                           WHERE rd.source = 'DISTRIBUTOR' AND rd.stored_code = s.product_code
                             AND rv.vendor_id = v.vendor_id) AS holds
            FROM public.vendors v
            ORDER BY (public.trigram_similarity(lower(v.vendor_name), lower(s.vendor_reference)) >= 0.4
                      AND EXISTS (SELECT 1 FROM cs_r rd
                                  JOIN cs_map md ON md.source = rd.source AND md.record_id = rd.record_id
                                  JOIN cs_map mv ON mv.item_code = md.item_code AND mv.source = 'VENDOR'
                                  JOIN cs_r rv   ON rv.source = mv.source AND rv.record_id = mv.record_id
                                  WHERE rd.source = 'DISTRIBUTOR' AND rd.stored_code = s.product_code
                                    AND rv.vendor_id = v.vendor_id)) DESC,
                     2 DESC
            LIMIT 1) b ON true
        WHERE NOT EXISTS (SELECT 1 FROM public.vendors v
                          WHERE lower(btrim(v.vendor_name)) = lower(btrim(s.vendor_reference)))
    LOOP
        IF c.sim >= 0.4 THEN
            PERFORM public.cleansing_add(sid, NULL,
                public.cleansing_fix('DISTRIBUTOR', 'supply_shop', c.supply_item_id, c.vendor_reference, c.vendor_name,
                    'UPDATE', 'Misspelt shop name in the supply record: ''' || c.vendor_reference
                    || ''' should be ''' || c.vendor_name || ''''));
        ELSE
            INSERT INTO public.cleansing_proposals
                (scan_id, item_code, source, target_db, target_table, key_column, key_value,
                 field, column_name, old_value, action, reason, options)
            VALUES (sid, NULL, 'DISTRIBUTOR', 'distributor_db', 'supplied_items', 'supply_item_id', c.supply_item_id,
                    'supply_shop', 'vendor_reference', c.vendor_reference, 'REVIEW',
                    'Supply record names a shop that does not exist: correct it by hand', NULL);
        END IF;
    END LOOP;

    -- (l) approvals (mediator's own table) recorded under a code that is not an item
    FOR c IN
        SELECT a.approval_id, a.item_code AS approved,
               coalesce((SELECT f.final_code FROM cs_final f WHERE f.item_code = a.item_code),   -- manufacturer's noisy copy is being fixed
                        x.final_code) AS target, x.sim, x.sim2
        FROM public.approved_items a
        LEFT JOIN LATERAL (
            SELECT f.final_code,
                   public.code_similarity(public.normalize_code(a.item_code), f.final_code) AS sim,
                   lead(public.code_similarity(public.normalize_code(a.item_code), f.final_code))
                       OVER (ORDER BY public.code_similarity(public.normalize_code(a.item_code), f.final_code) DESC) AS sim2
            FROM cs_final f
            WHERE NOT EXISTS (SELECT 1 FROM public.approved_items a2 WHERE a2.item_code = f.final_code)
            ORDER BY 2 DESC LIMIT 1) x ON true
        WHERE NOT EXISTS (SELECT 1 FROM cs_final f WHERE f.final_code = a.item_code)
          -- a code the distributor or vendor holds is a real item whose code is still under review
          AND NOT EXISTS (SELECT 1 FROM cs_r r WHERE r.ncode = a.item_code)
    LOOP
        IF c.target IS NOT NULL AND c.target <> c.approved
           AND ((SELECT count(*) FROM cs_final f WHERE f.item_code = c.approved) = 1
                OR (c.sim >= public.match_cfg('min_code_similarity') AND (c.sim2 IS NULL OR c.sim2 < c.sim)))
           AND NOT EXISTS (SELECT 1 FROM public.approved_items a2 WHERE a2.item_code = c.target) THEN
            PERFORM public.cleansing_add(sid, c.target,
                public.cleansing_fix('MEDIATOR', 'approval', c.approval_id, c.approved, c.target, 'UPDATE',
                    'Approval recorded under ' || c.approved || ', which is not an item code; the item is '
                    || c.target));
        ELSIF NOT EXISTS (SELECT 1 FROM cs_g g WHERE g.code = c.approved) THEN
            INSERT INTO public.cleansing_proposals
                (scan_id, item_code, source, target_db, target_table, key_column, key_value,
                 field, column_name, old_value, action, reason, options)
            VALUES (sid, NULL, 'MEDIATOR', 'mediator_db', 'approved_items', 'approval_id', c.approval_id,
                    'approval', 'item_code', c.approved, 'REVIEW',
                    'Approval for a code the manufacturer never made, and no unapproved item is close enough: correct it by hand',
                    NULL);
        END IF;
    END LOOP;

    -- (m) impossible dates: received / supplied / sold before the item was made, or in the future
    FOR c IN
        WITH d AS (
            SELECT r.source, 'received' AS field, r.record_id AS key, r.received_date AS d, f.mfg, f.item_code
            FROM cs_map m
            JOIN cs_r r     ON r.source = m.source AND r.record_id = m.record_id
            JOIN cs_final f ON f.item_code = m.item_code
            WHERE NOT m.dup
            UNION ALL
            SELECT 'DISTRIBUTOR', 'supply_date', s.supply_item_id, s.supply_date, f.mfg, f.item_code
            FROM public.supplied_items s
            JOIN cs_r r     ON r.source = 'DISTRIBUTOR' AND r.stored_code = s.product_code
            JOIN cs_map m   ON m.source = r.source AND m.record_id = r.record_id
            JOIN cs_final f ON f.item_code = m.item_code
            UNION ALL
            SELECT 'VENDOR', 'sale_date', s.sale_id, s.sale_date, f.mfg, f.item_code
            FROM public.medicine_sales s
            JOIN cs_r r     ON r.source = 'VENDOR' AND r.stored_code = s.item_identifier AND r.vendor_id = s.vendor_id
            JOIN cs_map m   ON m.source = r.source AND m.record_id = r.record_id
            JOIN cs_final f ON f.item_code = m.item_code
        )
        SELECT d.*, date_trunc('month', d.mfg)::date AS lo, current_date AS hi,
               (SELECT jsonb_object_agg(to_char(x, 'YYYY-MM-DD') || ' (typing slip corrected)',
                       jsonb_build_array(public.cleansing_fix(d.source, d.field, d.key, d.d::text, x::text, 'UPDATE',
                           'Chosen by reviewer: ' || d.field || ' = ' || x)))
                FROM public.cleansing_date_candidates(d.d, date_trunc('month', d.mfg)::date, current_date) x) AS opts
        FROM d
        WHERE d.d IS NOT NULL AND (d.d < date_trunc('month', d.mfg) OR d.d > current_date)
    LOOP
        INSERT INTO public.cleansing_proposals
            (scan_id, item_code, source, target_db, target_table, key_column, key_value,
             field, column_name, old_value, action, reason, options, suggested)
        SELECT sid, c.item_code, c.source, f->>'target_db', f->>'target_table', f->>'key_column', c.key,
               c.field, f->>'column_name', c.d::text, 'REVIEW',
               'Impossible ' || replace(c.field, '_', ' ') || ' ' || c.d || ': '
               || CASE WHEN c.d > current_date THEN 'it is in the future'
                       ELSE 'it is before the item was made (' || c.mfg || ')' END
               || CASE WHEN c.opts IS NULL THEN ' - correct it by hand' ELSE '' END,
               c.opts,
               CASE WHEN (SELECT count(*) FROM jsonb_object_keys(c.opts)) = 1
                    THEN (SELECT k FROM jsonb_object_keys(c.opts) k) END
        FROM (SELECT public.cleansing_fix(c.source, c.field, c.key, NULL, NULL, 'REVIEW', '') AS f) z;
    END LOOP;

    UPDATE public.cleansing_scans SET finished_at = now() WHERE scan_id = sid;
    DROP TABLE IF EXISTS cs_g, cs_r, cs_map, cs_mem, cs_med, cs_final;
    RETURN sid;
END;
$$;

-- ---------------------------------------------------------------------
-- 4. Latest scan, as the GUI shows it
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_cleansing_latest AS
SELECT p.*
FROM public.cleansing_proposals p
WHERE p.scan_id = (SELECT max(scan_id) FROM public.cleansing_scans);

-- ---------------------------------------------------------------------
-- 5. A reviewer chooses an option for a REVIEW proposal
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleansing_resolve(p_proposal_id int, p_option text)
RETURNS int LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
    p   public.cleansing_proposals%ROWTYPE;
    fx  jsonb;
    n   int := 0;
BEGIN
    SELECT * INTO p FROM public.cleansing_proposals WHERE proposal_id = p_proposal_id;
    IF p.proposal_id IS NULL OR p.action <> 'REVIEW' OR p.status <> 'PROPOSED' THEN
        RAISE EXCEPTION 'Proposal % is not an open review', p_proposal_id;
    END IF;
    IF p.options IS NULL OR (p.options -> p_option) IS NULL THEN
        RAISE EXCEPTION 'Option "%" is not offered for proposal %', p_option, p_proposal_id;
    END IF;
    IF p_option LIKE 'Report as counterfeit%' THEN
        INSERT INTO public.reports (item_identifier, manufacturer, distributor, vendor,
                                    report_reason, risk_status, evidence)
        SELECT p.old_value, NULL, NULL, s.vendor_name, 'COUNTERFEIT CODE IN STOCK', 'SUSPICIOUS',
               'Found by data cleansing (scan #' || p.scan_id || '): ' || p.source || ' record '
               || p.key_value || ' holds code ' || p.old_value
               || ', which matches no item the manufacturer made. Record kept as evidence.'
        FROM (SELECT max(vendor_name) AS vendor_name FROM public.v_stored_records
              WHERE source = p.source AND record_id = p.key_value) s
        ON CONFLICT (item_identifier) DO NOTHING;
    END IF;
    FOR fx IN SELECT jsonb_array_elements(p.options -> p_option) LOOP
        PERFORM public.cleansing_add(p.scan_id, p.item_code, fx);
        n := n + 1;
    END LOOP;
    UPDATE public.cleansing_proposals
    SET status = 'RESOLVED', suggested = p_option
    WHERE proposal_id = p_proposal_id;
    RETURN n;      -- number of fixes added
END;
$$;

-- ---------------------------------------------------------------------
-- 6. Fix script for one database (owner reviews and runs it there)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleansing_fix_sql(p_db text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
    sid   int := (SELECT max(scan_id) FROM public.cleansing_scans);
    p     record;
    out   text;
    n     int := 0;
BEGIN
    out := '-- =====================================================================' || E'\n'
        || '-- Asli-or-Nakli · cleansing fixes for ' || p_db || E'\n'
        || '-- RUN ON: ' || p_db || '   (generated by the mediator, scan #' || sid || ', '
        || to_char(now(), 'YYYY-MM-DD HH24:MI') || ')' || E'\n'
        || '-- Each statement only changes the row if it still has the old value,' || E'\n'
        || '-- so running this twice is harmless.' || E'\n'
        || '-- =====================================================================' || E'\n\n'
        || 'BEGIN;' || E'\n\n';

    FOR p IN
        SELECT * FROM public.cleansing_proposals
        WHERE scan_id = sid AND target_db = p_db AND status = 'PROPOSED' AND action IN ('UPDATE', 'DELETE')
        ORDER BY CASE WHEN action = 'DELETE' AND target_table = 'medicines' THEN 2     -- after its items moved
                      WHEN action = 'DELETE' THEN 0 ELSE 1 END,
                 (field = 'code') DESC, target_table, key_value, field
    LOOP
        out := out || '-- #' || p.proposal_id || ' ' || replace(p.reason, E'\n', ' ') || E'\n';
        IF p.action = 'DELETE' AND p.target_table = 'medicines' THEN
            -- only once no item uses it (deleting a medicine would also delete its items)
            out := out || format('DELETE FROM public.medicines WHERE medicine_id = %s AND medicine_code = %L'
                                 || ' AND NOT EXISTS (SELECT 1 FROM public.manufactured_items WHERE medicine_code = %L);',
                                 p.key_value, p.old_value, p.old_value);
        ELSIF p.action = 'DELETE' AND p.target_table = 'inventory_items' THEN
            -- a supply record pointing at the duplicate moves to the record that is kept
            out := out || coalesce(format('UPDATE public.supplied_items SET product_code = %L WHERE product_code = %L'
                                 || ' AND NOT EXISTS (SELECT 1 FROM public.supplied_items WHERE product_code = %L);' || E'\n',
                                 substring(p.reason FROM 'keeping record #[0-9]+ (.*)\)$'), p.old_value,
                                 substring(p.reason FROM 'keeping record #[0-9]+ (.*)\)$'))
                                 || CASE WHEN substring(p.reason FROM 'keeping record #[0-9]+ (.*)\)$') IS NULL THEN NULL ELSE '' END, '')
                       || format('DELETE FROM public.supplied_items WHERE product_code = %L;' || E'\n', p.old_value)
                       || format('DELETE FROM public.inventory_items WHERE inventory_id = %s AND product_code = %L;',
                                 p.key_value, p.old_value);
        ELSIF p.action = 'UPDATE' AND p.target_table = 'inventory_items' AND p.column_name = 'product_code' THEN
            -- supplied_items refers to product_code: move its supply record along in the same statement
            out := out || format('WITH moved AS (DELETE FROM public.supplied_items WHERE product_code = %L'
                                 || ' AND EXISTS (SELECT 1 FROM public.inventory_items WHERE inventory_id = %s AND product_code = %L)'
                                 || ' RETURNING supply_item_id, vendor_reference, supply_date),' || E'\n'
                                 || '     fixed AS (UPDATE public.inventory_items SET product_code = %L WHERE inventory_id = %s AND product_code = %L RETURNING 1)' || E'\n'
                                 || 'INSERT INTO public.supplied_items (supply_item_id, product_code, vendor_reference, supply_date)'
                                 || ' SELECT supply_item_id, %L, vendor_reference, supply_date FROM moved WHERE EXISTS (SELECT 1 FROM fixed);',
                                 p.old_value, p.key_value, p.old_value, p.new_value, p.key_value, p.old_value, p.new_value);
        ELSIF p.action = 'DELETE' THEN
            out := out || format('DELETE FROM public.%I WHERE %I = %s AND %I = %L;',
                                 p.target_table, p.key_column, p.key_value, p.column_name, p.old_value);
        ELSE
            out := out || format('UPDATE public.%I SET %I = %L WHERE %I = %s AND %I::text IS NOT DISTINCT FROM %L;',
                                 p.target_table, p.column_name, p.new_value, p.key_column, p.key_value,
                                 p.column_name, p.old_value);
        END IF;
        out := out || E'\n\n';
        n := n + 1;
    END LOOP;

    IF n = 0 THEN
        RETURN '-- Nothing to fix in ' || p_db || ' (scan #' || coalesce(sid::text, '-') || ').' || E'\n';
    END IF;
    RETURN out || 'COMMIT;' || E'\n\n' || '-- ' || n || ' change(s). Then click "Check applied fixes" in the GUI.' || E'\n';
END;
$$;

-- ---------------------------------------------------------------------
-- 7. After owners ran their scripts: detect applied fixes and log them
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleansing_check()
RETURNS TABLE (applied int, pending int)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
    p     record;
    cur   text;
    found boolean;
    a     int := 0;
    w     int := 0;
BEGIN
    FOR p IN
        SELECT * FROM public.cleansing_proposals
        WHERE status = 'PROPOSED' AND action IN ('UPDATE', 'DELETE')
          AND scan_id = (SELECT max(scan_id) FROM public.cleansing_scans)
    LOOP
        EXECUTE format('SELECT %I::text, true FROM public.%I WHERE %I = $1',
                       p.column_name, p.target_table, p.key_column)
        INTO cur, found USING p.key_value;

        IF (p.action = 'DELETE' AND found IS NULL)
           OR (p.action = 'UPDATE' AND cur IS NOT DISTINCT FROM p.new_value) THEN
            UPDATE public.cleansing_proposals SET status = 'APPLIED' WHERE proposal_id = p.proposal_id;
            INSERT INTO public.cleansing_log
                (proposal_id, scan_id, target_db, target_table, key_column, key_value,
                 column_name, old_value, new_value, action, reason)
            VALUES (p.proposal_id, p.scan_id, p.target_db, p.target_table, p.key_column, p.key_value,
                    p.column_name, p.old_value, p.new_value, p.action, p.reason);
            a := a + 1;
        ELSE
            w := w + 1;
        END IF;
    END LOOP;
    applied := a; pending := w;
    -- every checked fix teaches the mediator how reliable each source is (step 6)
    PERFORM public.refresh_reliability();
    RETURN NEXT;
END;
$$;

-- =====================================================================
-- Checks: every row should say PASS (quick; does not run a scan)
-- =====================================================================
SELECT 'cleansing tables present' AS test,
       CASE WHEN (SELECT count(*) FROM pg_tables WHERE schemaname = 'public'
                  AND tablename IN ('cleansing_scans', 'cleansing_proposals', 'cleansing_log', 'cleansing_assignments')) = 4
            THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'scan / resolve / fix script / check functions present',
       CASE WHEN (SELECT count(*) FROM pg_proc WHERE proname IN
                  ('cleansing_scan', 'cleansing_resolve', 'cleansing_fix_sql', 'cleansing_check')) = 4
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'date months compared: 6/28 = 2028-06',
       CASE WHEN cleansing_month('6/28') = '2028-06' THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'fix script generator works',
       CASE WHEN cleansing_fix_sql('vendor_db') LIKE '--%' THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'typing slip in a date: 2062-01-21 could be 2026-01-21',
       CASE WHEN (SELECT string_agg(d::text, ',') FROM cleansing_date_candidates(DATE '2062-01-21', DATE '2025-01-01', DATE '2026-10-01') d)
                 = '2026-01-21' THEN 'PASS' ELSE 'FAIL' END;
