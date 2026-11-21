-- =====================================================================
-- Asli-or-Nakli · Phase 3 · manuf_db: new tables (FK -> PK) + data
-- RUN ON: manuf_db (NOT the default "postgres" database), after
--         asli_ctx_core.sql.  Alt+X.  Safe to re-run; re-running also upgrades
--         an earlier install of this script.
-- Existing tables are NOT changed: manufacturers, medicines, manufactured_items.
-- =====================================================================
--
--   manufacturers (existing) 1──< plants 1──< production_batches >──1 medicines (existing)
--                                              │
--                       manufactured_items ──1 batch_items >──1 production_batches
--                       (existing)                             │
--                                              production_batches 1──< qc_reports
--
--   plants              where a medicine is made, with its GMP certificate
--   production_batches  one batch = one medicine made in one plant in one month
--   batch_items         which batch each item code came from (link table,
--                       so manufactured_items keeps its schema)
--   qc_reports          quality-control results per batch, with free-text remarks
--
-- Live data: a trigger links every item that is inserted (or moved to another
-- medicine by a cleansing fix) to its batch, creating the batch if needed. The
-- foreign keys cascade, so the Phase 2 fix scripts can still delete a medicine
-- copy or an item.
-- =====================================================================

SELECT current_database() AS running_on;   -- must say manuf_db

CREATE TABLE IF NOT EXISTS public.plants (
    plant_id         serial PRIMARY KEY,
    manufacturer_id  int  NOT NULL,
    plant_name       varchar(150) NOT NULL,
    city             varchar(80)  NOT NULL,
    gmp_certificate  varchar(40)  NOT NULL UNIQUE,
    gmp_valid_until  date NOT NULL
);

CREATE TABLE IF NOT EXISTS public.production_batches (
    batch_id       serial PRIMARY KEY,
    batch_no       varchar(30) NOT NULL UNIQUE,
    medicine_code  varchar(30) NOT NULL,
    plant_id       int  NOT NULL,
    produced_on    date NOT NULL,
    quantity_units int  NOT NULL CHECK (quantity_units > 0),
    release_status varchar(30) NOT NULL DEFAULT 'RELEASED'
);

CREATE TABLE IF NOT EXISTS public.batch_items (
    item_id  int PRIMARY KEY,
    batch_id int NOT NULL
);

CREATE TABLE IF NOT EXISTS public.qc_reports (
    report_id       serial PRIMARY KEY,
    batch_id        int  NOT NULL,
    tested_on       date NOT NULL,
    test_name       varchar(60) NOT NULL,
    result          varchar(10) NOT NULL CHECK (result IN ('PASS', 'FAIL')),
    measured_value  numeric,
    spec_range      varchar(40),
    analyst         varchar(80),
    remarks         text
);

-- constraints (dropped and re-added, so an earlier install gets the cascades)
ALTER TABLE public.production_batches ALTER COLUMN release_status TYPE varchar(30);
ALTER TABLE public.production_batches DROP CONSTRAINT IF EXISTS production_batches_release_status_check;
ALTER TABLE public.production_batches ADD CONSTRAINT production_batches_release_status_check
    CHECK (release_status IN ('RELEASED', 'ON HOLD', 'RECALLED', 'RELEASED AFTER RETEST'));

ALTER TABLE public.plants DROP CONSTRAINT IF EXISTS plants_manufacturer_id_fkey;
ALTER TABLE public.plants ADD CONSTRAINT plants_manufacturer_id_fkey
    FOREIGN KEY (manufacturer_id) REFERENCES public.manufacturers (manufacturer_id) ON DELETE CASCADE;

ALTER TABLE public.production_batches DROP CONSTRAINT IF EXISTS production_batches_medicine_code_fkey;
ALTER TABLE public.production_batches ADD CONSTRAINT production_batches_medicine_code_fkey
    FOREIGN KEY (medicine_code) REFERENCES public.medicines (medicine_code) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE public.production_batches DROP CONSTRAINT IF EXISTS production_batches_plant_id_fkey;
ALTER TABLE public.production_batches ADD CONSTRAINT production_batches_plant_id_fkey
    FOREIGN KEY (plant_id) REFERENCES public.plants (plant_id) ON DELETE CASCADE;

ALTER TABLE public.batch_items DROP CONSTRAINT IF EXISTS batch_items_item_id_fkey;
ALTER TABLE public.batch_items ADD CONSTRAINT batch_items_item_id_fkey
    FOREIGN KEY (item_id) REFERENCES public.manufactured_items (item_id) ON DELETE CASCADE;

ALTER TABLE public.batch_items DROP CONSTRAINT IF EXISTS batch_items_batch_id_fkey;
ALTER TABLE public.batch_items ADD CONSTRAINT batch_items_batch_id_fkey
    FOREIGN KEY (batch_id) REFERENCES public.production_batches (batch_id) ON DELETE CASCADE;

ALTER TABLE public.qc_reports DROP CONSTRAINT IF EXISTS qc_reports_batch_id_fkey;
ALTER TABLE public.qc_reports ADD CONSTRAINT qc_reports_batch_id_fkey
    FOREIGN KEY (batch_id) REFERENCES public.production_batches (batch_id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS plants_manufacturer_idx ON public.plants (manufacturer_id);
CREATE INDEX IF NOT EXISTS batches_medicine_idx    ON public.production_batches (medicine_code, produced_on);
CREATE INDEX IF NOT EXISTS batches_plant_idx       ON public.production_batches (plant_id);
CREATE INDEX IF NOT EXISTS batch_items_batch_idx   ON public.batch_items (batch_id);
CREATE INDEX IF NOT EXISTS qc_batch_idx            ON public.qc_reports (batch_id);
CREATE INDEX IF NOT EXISTS qc_remarks_fts ON public.qc_reports USING gin (to_tsvector('english', coalesce(remarks, '')));
-- prefix search on names (asli_ctx entry match 'prefix')
CREATE INDEX IF NOT EXISTS medicines_name_prefix ON public.medicines (lower(medicine_name::text) text_pattern_ops);

-- ---------------------------------------------------------------------
-- Linking: one function, used by the trigger (live rows) and the refresh
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION asli_ctx.batch_no_for(p_medicine_code text, p_month date) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT upper(left(regexp_replace(mf.manufacturer_name, '[^A-Za-z]', '', 'g'), 3)) || '-'
           || regexp_replace(m.medicine_code, '[^A-Za-z0-9]', '', 'g') || '-' || to_char(p_month, 'YYMM')
    FROM public.medicines m JOIN public.manufacturers mf ON mf.manufacturer_id = m.manufacturer_id
    WHERE m.medicine_code = p_medicine_code
$$;

-- the item's batch = its medicine + production month; created (with its routine
-- QC) when it does not exist yet. Returns the batch_id.
CREATE OR REPLACE FUNCTION asli_ctx.link_item(p_item_id int) RETURNS int
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    it    record;
    v_mid int;
    v_pid int;
    v_bid int;
    v_no  text;
BEGIN
    SELECT mi.item_id, mi.medicine_code, date_trunc('month', mi.manufacturing_date)::date AS month, m.manufacturer_id
      INTO it
      FROM public.manufactured_items mi JOIN public.medicines m ON m.medicine_code = mi.medicine_code
     WHERE mi.item_id = p_item_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT batch_id INTO v_bid FROM public.production_batches
     WHERE medicine_code = it.medicine_code AND produced_on = it.month;

    IF v_bid IS NULL THEN
        -- the maker's Unit 1 (created if the maker is new)
        SELECT plant_id INTO v_pid FROM public.plants
         WHERE manufacturer_id = it.manufacturer_id ORDER BY plant_name LIMIT 1;
        IF v_pid IS NULL THEN
            INSERT INTO public.plants (manufacturer_id, plant_name, city, gmp_certificate, gmp_valid_until)
            SELECT m.manufacturer_id, m.manufacturer_name || ' — Unit 1',
                   coalesce(nullif(btrim(split_part(m.address, ',', 2)), ''), nullif(btrim(m.address), ''), 'Unknown'),
                   'GMP/' || upper(left(regexp_replace(m.manufacturer_name, '[^A-Za-z]', '', 'g'), 3)) || '/U1/' || m.manufacturer_id,
                   DATE '2028-03-31'
            FROM public.manufacturers m WHERE m.manufacturer_id = it.manufacturer_id
            RETURNING plant_id INTO v_pid;
        END IF;
        v_no := asli_ctx.batch_no_for(it.medicine_code, it.month);
        -- a look-alike medicine copy can produce the same batch number: keep it unique
        IF EXISTS (SELECT 1 FROM public.production_batches WHERE batch_no = v_no) THEN
            v_no := left(v_no, 24) || '-' || it.item_id;
        END IF;
        INSERT INTO public.production_batches (batch_no, medicine_code, plant_id, produced_on, quantity_units)
        VALUES (v_no, it.medicine_code, v_pid, it.month, 5000)
        RETURNING batch_id INTO v_bid;
        INSERT INTO public.qc_reports (batch_id, tested_on, test_name, result, measured_value, spec_range, analyst, remarks)
        SELECT v_bid, it.month + 6, t.test, 'PASS', t.val, t.spec, 'QC Lab, ' || p.city,
               'Routine release testing of batch ' || v_no || ': ' || t.test || ' within specification.'
        FROM public.plants p
        CROSS JOIN (VALUES ('Assay', 99.2, '95.0–105.0 %'),
                           ('Dissolution', 92.0, 'NLT 80 % in 30 min'),
                           ('Description', NULL::numeric, 'Conforms')) t(test, val, spec)
        WHERE p.plant_id = v_pid;
    END IF;

    INSERT INTO public.batch_items (item_id, batch_id) VALUES (p_item_id, v_bid)
    ON CONFLICT (item_id) DO UPDATE SET batch_id = EXCLUDED.batch_id;
    RETURN v_bid;
END;
$$;

-- every item not (correctly) linked yet; returns how many were linked
CREATE OR REPLACE FUNCTION asli_ctx.refresh_links() RETURNS int
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    r record;
    n int := 0;
BEGIN
    FOR r IN SELECT mi.item_id FROM public.manufactured_items mi
             LEFT JOIN public.batch_items bi ON bi.item_id = mi.item_id
             LEFT JOIN public.production_batches pb ON pb.batch_id = bi.batch_id
             WHERE pb.batch_id IS NULL
                OR pb.medicine_code <> mi.medicine_code
                OR pb.produced_on <> date_trunc('month', mi.manufacturing_date)::date LOOP
        BEGIN   -- one bad row (e.g. a NULL date) must not stop the whole script
            PERFORM asli_ctx.link_item(r.item_id);
            n := n + 1;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Phase 3: item % not linked: %', r.item_id, SQLERRM;
        END;
    END LOOP;
    RETURN n;
END;
$$;

-- live rows: the professor inserts an item, or a cleansing fix moves an item to
-- another medicine. Never blocks the insert: a linking problem is only a warning.
CREATE OR REPLACE FUNCTION asli_ctx.trg_link_item() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        PERFORM asli_ctx.link_item(NEW.item_id);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Phase 3: item % not linked to a batch: %', NEW.item_id, SQLERRM;
    END;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS asli_link_item ON public.manufactured_items;
CREATE TRIGGER asli_link_item AFTER INSERT OR UPDATE OF medicine_code, manufacturing_date
    ON public.manufactured_items FOR EACH ROW EXECUTE FUNCTION asli_ctx.trg_link_item();

-- ---------------------------------------------------------------------
-- Data, derived from the rows that are already here (works on any copy)
-- ---------------------------------------------------------------------

-- one main plant per manufacturer in its home city, plus a second plant for three of them
INSERT INTO public.plants (manufacturer_id, plant_name, city, gmp_certificate, gmp_valid_until)
SELECT m.manufacturer_id,
       m.manufacturer_name || ' — Unit 1',
       coalesce(nullif(btrim(split_part(m.address, ',', 2)), ''), nullif(btrim(m.address), ''), 'Unknown'),
       'GMP/' || upper(left(regexp_replace(m.manufacturer_name, '[^A-Za-z]', '', 'g'), 3)) || '/U1',
       DATE '2028-03-31'
FROM public.manufacturers m
WHERE NOT EXISTS (SELECT 1 FROM public.plants p WHERE p.manufacturer_id = m.manufacturer_id AND p.plant_name LIKE '%Unit 1')
ON CONFLICT (gmp_certificate) DO NOTHING;

INSERT INTO public.plants (manufacturer_id, plant_name, city, gmp_certificate, gmp_valid_until)
SELECT m.manufacturer_id, m.manufacturer_name || ' — Unit 2', x.city,
       'GMP/' || upper(left(regexp_replace(m.manufacturer_name, '[^A-Za-z]', '', 'g'), 3)) || '/U2', x.valid
FROM public.manufacturers m
JOIN (VALUES ('Sunrise Pharmaceuticals', 'Baddi', DATE '2026-06-30'),     -- certificate EXPIRED
             ('CureLife Pharma',         'Sikkim', DATE '2027-12-31'),
             ('HealthPlus Pharma',       'Vapi',   DATE '2027-09-30')) x(name, city, valid)
  ON x.name = m.manufacturer_name
ON CONFLICT (gmp_certificate) DO NOTHING;

-- every item -> its batch (batches + routine QC created on the way)
SELECT asli_ctx.refresh_links() AS items_linked;

-- ---------------------------------------------------------------------
-- The demo story: ONE Ibuprofen batch and ONE Amoxicillin batch have findings.
-- The story batch is the batch of ITEM000041 (Ibuprofen) and of ITEM000035
-- (Amoxicillin) when those items exist, otherwise the earliest batch of that
-- medicine. Earlier story rows are reset first, so re-running never spreads it.
-- ---------------------------------------------------------------------
UPDATE public.qc_reports q
   SET result = 'PASS',
       measured_value = CASE q.test_name WHEN 'Assay' THEN 99.2 WHEN 'Dissolution' THEN 92.0 END,
       remarks = 'Routine release testing of batch ' || pb.batch_no || ': ' || q.test_name || ' within specification.'
  FROM public.production_batches pb
 WHERE pb.batch_id = q.batch_id AND q.result = 'FAIL'
   AND (q.remarks LIKE 'Assay of batch % (Ibuprofen 400mg)%' OR q.remarks LIKE 'Dissolution of batch % (Amoxicillin 500mg capsules)%');
UPDATE public.production_batches SET release_status = 'RELEASED' WHERE release_status = 'RELEASED AFTER RETEST';

INSERT INTO asli_ctx.demo_story (key, value)
SELECT 'ibuprofen_batch', coalesce(
         (SELECT pb.batch_no FROM public.manufactured_items mi
          JOIN public.batch_items bi USING (item_id) JOIN public.production_batches pb USING (batch_id)
          WHERE asli.fold(mi.unique_item_code) = asli.fold('ITEM000041') AND mi.medicine_code = 'MED005' LIMIT 1),
         (SELECT batch_no FROM public.production_batches WHERE medicine_code = 'MED005' ORDER BY produced_on, batch_id LIMIT 1))
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO asli_ctx.demo_story (key, value)
SELECT 'amoxicillin_batch', coalesce(
         (SELECT pb.batch_no FROM public.manufactured_items mi
          JOIN public.batch_items bi USING (item_id) JOIN public.production_batches pb USING (batch_id)
          WHERE asli.fold(mi.unique_item_code) = asli.fold('ITEM000035') AND mi.medicine_code = 'MED004' LIMIT 1),
         (SELECT batch_no FROM public.production_batches WHERE medicine_code = 'MED004' ORDER BY produced_on, batch_id LIMIT 1))
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

UPDATE public.production_batches SET release_status = 'RELEASED AFTER RETEST'
 WHERE batch_no = (SELECT value FROM asli_ctx.demo_story WHERE key = 'ibuprofen_batch');

-- every other Sunrise batch belongs to Unit 1 (an earlier install put all Sunrise
-- Ibuprofen / Amoxicillin batches in Unit 2, so clean batches looked substandard)
UPDATE public.production_batches pb
   SET plant_id = (SELECT p1.plant_id FROM public.plants p1
                   WHERE p1.manufacturer_id = p2.manufacturer_id AND p1.plant_name LIKE '%Unit 1'
                   ORDER BY p1.plant_id LIMIT 1)
  FROM public.plants p2
 WHERE p2.plant_id = pb.plant_id AND p2.gmp_certificate = 'GMP/SUN/U2'
   AND pb.batch_no NOT IN (SELECT value FROM asli_ctx.demo_story
                           WHERE key IN ('ibuprofen_batch', 'amoxicillin_batch') AND value IS NOT NULL);

-- Sunrise's two story batches were made in its Unit 2 (the plant whose GMP lapsed)
UPDATE public.production_batches pb SET plant_id = p.plant_id
  FROM public.plants p
 WHERE p.gmp_certificate = 'GMP/SUN/U2'
   AND pb.batch_no IN (SELECT value FROM asli_ctx.demo_story WHERE key IN ('ibuprofen_batch', 'amoxicillin_batch'));

UPDATE public.qc_reports q SET result = 'FAIL', measured_value = 88.4,
       remarks = 'Assay of batch ' || pb.batch_no || ' (Ibuprofen 400mg) found 88.4 % of label claim, below the '
              || '95–105 % limit. Out-of-specification investigation opened; batch released after retest '
              || 'on a second sample (96.1 %). Root cause not confirmed; granulation moisture suspected.'
FROM public.production_batches pb
WHERE pb.batch_id = q.batch_id AND q.test_name = 'Assay'
  AND pb.batch_no = (SELECT value FROM asli_ctx.demo_story WHERE key = 'ibuprofen_batch');

UPDATE public.qc_reports q SET result = 'FAIL', measured_value = 71.0,
       remarks = 'Dissolution of batch ' || pb.batch_no || ' (Amoxicillin 500mg capsules) 71 % in 30 minutes, '
              || 'below the 80 % limit. Capsule shells observed sticky and softened; humidity in the '
              || 'encapsulation room exceeded 65 % RH during the run.'
FROM public.production_batches pb
WHERE pb.batch_id = q.batch_id AND q.test_name = 'Dissolution'
  AND pb.batch_no = (SELECT value FROM asli_ctx.demo_story WHERE key = 'amoxicillin_batch');

-- ---------------------------------------------------------------------
-- Context-discovery config for this source
-- ---------------------------------------------------------------------
INSERT INTO asli_ctx.entry_points (seed_kind, table_name, column_name, match, weight) VALUES
    ('item_code',         'manufactured_items', 'unique_item_code',  'fold',   1.0),
    ('medicine_code',     'medicines',          'medicine_code',     'exact',  1.0),
    ('medicine_name',     'medicines',          'medicine_name',     'prefix', 0.9),
    ('medicine_name',     'medicines',          'composition',       'name',   0.7),
    ('manufacturer_name', 'manufacturers',      'manufacturer_name', 'name',   0.9),
    ('batch_no',          'production_batches', 'batch_no',          'exact',  1.0),
    ('text',              'medicines',          'medicine_name',     'prefix', 0.7),
    ('text',              'manufacturers',      'manufacturer_name', 'name',   0.7),
    ('text',              'plants',             'city',              'name',   0.5),
    ('text',              'qc_reports',         'remarks',           'text',   0.6)
ON CONFLICT (seed_kind, table_name, column_name) DO UPDATE SET match = EXCLUDED.match, weight = EXCLUDED.weight;

INSERT INTO asli_ctx.table_roles (table_name, role, weight, label) VALUES
    ('manufacturers',      'hub',    0.8, 'Manufacturer'),
    ('medicines',          'entity', 0.9, 'Medicine'),
    ('manufactured_items', 'entity', 1.0, 'Item (unit)'),
    ('plants',             'entity', 0.9, 'Plant + GMP certificate'),
    ('production_batches', 'entity', 1.0, 'Production batch'),
    ('batch_items',        'link',   1.0, 'Item ↔ batch'),
    ('qc_reports',         'detail', 1.2, 'QC report')
ON CONFLICT (table_name) DO UPDATE SET role = EXCLUDED.role, weight = EXCLUDED.weight, label = EXCLUDED.label;

-- personal data that must not leave this database (none at the manufacturer;
-- the contact number is a business number but is not needed for context)
INSERT INTO asli_ctx.private_columns VALUES ('manufacturers', 'contact_number', 'drop')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- Check
-- ---------------------------------------------------------------------
SELECT table_name, role, fk_links,
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM public.%I', table_name), false, true, '')))[1]::text::int AS row_count
FROM asli_ctx.v_schema ORDER BY fk_links DESC, table_name;

SELECT key, value FROM asli_ctx.demo_story ORDER BY key;
