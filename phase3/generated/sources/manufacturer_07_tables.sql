-- =====================================================================
-- Asli-or-Nakli · Phase 3 · manufacturer_db: new tables (FK -> PK) + data
-- RUN ON: manufacturer_db, after asli_ctx_core.sql.  Alt+X.  Safe to re-run.
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
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.plants (
    plant_id         serial PRIMARY KEY,
    manufacturer_id  int  NOT NULL REFERENCES public.manufacturers (manufacturer_id),
    plant_name       varchar(150) NOT NULL,
    city             varchar(80)  NOT NULL,
    gmp_certificate  varchar(40)  NOT NULL UNIQUE,
    gmp_valid_until  date NOT NULL
);

CREATE TABLE IF NOT EXISTS public.production_batches (
    batch_id       serial PRIMARY KEY,
    batch_no       varchar(30) NOT NULL UNIQUE,
    medicine_code  varchar(30) NOT NULL REFERENCES public.medicines (medicine_code),
    plant_id       int  NOT NULL REFERENCES public.plants (plant_id),
    produced_on    date NOT NULL,
    quantity_units int  NOT NULL CHECK (quantity_units > 0),
    release_status varchar(30) NOT NULL DEFAULT 'RELEASED'
                   CHECK (release_status IN ('RELEASED', 'ON HOLD', 'RECALLED', 'RELEASED AFTER RETEST'))
);

CREATE TABLE IF NOT EXISTS public.batch_items (
    item_id  int PRIMARY KEY REFERENCES public.manufactured_items (item_id) ON DELETE CASCADE,
    batch_id int NOT NULL REFERENCES public.production_batches (batch_id)
);

CREATE TABLE IF NOT EXISTS public.qc_reports (
    report_id       serial PRIMARY KEY,
    batch_id        int  NOT NULL REFERENCES public.production_batches (batch_id),
    tested_on       date NOT NULL,
    test_name       varchar(60) NOT NULL,
    result          varchar(10) NOT NULL CHECK (result IN ('PASS', 'FAIL')),
    measured_value  numeric,
    spec_range      varchar(40),
    analyst         varchar(80),
    remarks         text
);

CREATE INDEX IF NOT EXISTS plants_manufacturer_idx ON public.plants (manufacturer_id);
CREATE INDEX IF NOT EXISTS batches_medicine_idx    ON public.production_batches (medicine_code);
CREATE INDEX IF NOT EXISTS batches_plant_idx       ON public.production_batches (plant_id);
CREATE INDEX IF NOT EXISTS batch_items_batch_idx   ON public.batch_items (batch_id);
CREATE INDEX IF NOT EXISTS qc_batch_idx            ON public.qc_reports (batch_id);
CREATE INDEX IF NOT EXISTS qc_remarks_fts ON public.qc_reports USING gin (to_tsvector('english', coalesce(remarks, '')));

-- ---------------------------------------------------------------------
-- Data, derived from the rows that are already here (works on any copy)
-- ---------------------------------------------------------------------

-- one main plant per manufacturer in its home city, plus a second plant for three of them
INSERT INTO public.plants (manufacturer_id, plant_name, city, gmp_certificate, gmp_valid_until)
SELECT m.manufacturer_id,
       m.manufacturer_name || ' — Unit 1',
       btrim(split_part(m.address, ',', 2)),
       'GMP/' || upper(left(regexp_replace(m.manufacturer_name, '[^A-Za-z]', '', 'g'), 3)) || '/U1',
       DATE '2028-03-31'
FROM public.manufacturers m
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

-- one batch per medicine and production month; batch number = MFR-MEDCODE-YYMM
-- (Sunrise's Ibuprofen and Amoxicillin come from its Unit 2, the rest from Unit 1)
INSERT INTO public.production_batches (batch_no, medicine_code, plant_id, produced_on, quantity_units, release_status)
SELECT upper(left(regexp_replace(mf.manufacturer_name, '[^A-Za-z]', '', 'g'), 3)) || '-'
         || regexp_replace(m.medicine_code, '[^A-Za-z0-9]', '', 'g') || '-' || to_char(b.month, 'YYMM'),
       m.medicine_code,
       coalesce((SELECT p.plant_id FROM public.plants p WHERE p.manufacturer_id = mf.manufacturer_id
                   AND p.plant_name LIKE '%Unit 2' AND m.medicine_code IN ('MED004', 'MED005')),
                (SELECT p.plant_id FROM public.plants p WHERE p.manufacturer_id = mf.manufacturer_id
                   AND p.plant_name LIKE '%Unit 1')),
       b.month,
       5000 + 250 * b.n,
       CASE m.medicine_code WHEN 'MED005' THEN 'RELEASED AFTER RETEST' ELSE 'RELEASED' END
FROM (SELECT mi.medicine_code, date_trunc('month', mi.manufacturing_date)::date AS month, count(*) AS n
      FROM public.manufactured_items mi GROUP BY 1, 2) b
JOIN public.medicines m      ON m.medicine_code = b.medicine_code
JOIN public.manufacturers mf ON mf.manufacturer_id = m.manufacturer_id
ON CONFLICT (batch_no) DO NOTHING;

-- every item belongs to the batch of its medicine and production month
INSERT INTO public.batch_items (item_id, batch_id)
SELECT mi.item_id, pb.batch_id
FROM public.manufactured_items mi
JOIN public.production_batches pb
  ON pb.medicine_code = mi.medicine_code
 AND pb.produced_on = date_trunc('month', mi.manufacturing_date)::date
ON CONFLICT (item_id) DO NOTHING;

-- QC: three tests per batch, all PASS ...
INSERT INTO public.qc_reports (batch_id, tested_on, test_name, result, measured_value, spec_range, analyst, remarks)
SELECT pb.batch_id, pb.produced_on + 6, t.test, 'PASS', t.val, t.spec, 'QC Lab, ' || p.city,
       'Routine release testing of batch ' || pb.batch_no || ': ' || t.test || ' within specification.'
FROM public.production_batches pb
JOIN public.plants p ON p.plant_id = pb.plant_id
CROSS JOIN (VALUES ('Assay', 99.2, '95.0–105.0 %'),
                   ('Dissolution', 92.0, 'NLT 80 % in 30 min'),
                   ('Description', NULL::numeric, 'Conforms')) t(test, val, spec)
WHERE NOT EXISTS (SELECT 1 FROM public.qc_reports q WHERE q.batch_id = pb.batch_id);

-- ... except two batches with real findings (the Phase 3 demo story)
UPDATE public.qc_reports q SET result = 'FAIL', measured_value = 88.4,
       remarks = 'Assay of batch ' || pb.batch_no || ' (Ibuprofen 400mg) found 88.4 % of label claim, below the '
              || '95–105 % limit. Out-of-specification investigation opened; batch released after retest '
              || 'on a second sample (96.1 %). Root cause not confirmed; granulation moisture suspected.'
FROM public.production_batches pb
WHERE pb.batch_id = q.batch_id AND pb.medicine_code = 'MED005' AND q.test_name = 'Assay';

UPDATE public.qc_reports q SET result = 'FAIL', measured_value = 71.0,
       remarks = 'Dissolution of batch ' || pb.batch_no || ' (Amoxicillin 500mg capsules) 71 % in 30 minutes, '
              || 'below the 80 % limit. Capsule shells observed sticky and softened; humidity in the '
              || 'encapsulation room exceeded 65 % RH during the run.'
FROM public.production_batches pb
WHERE pb.batch_id = q.batch_id AND pb.medicine_code = 'MED004' AND q.test_name = 'Dissolution';

-- ---------------------------------------------------------------------
-- Context-discovery config for this source
-- ---------------------------------------------------------------------
INSERT INTO asli_ctx.entry_points (seed_kind, table_name, column_name, match, weight) VALUES
    ('item_code',         'manufactured_items', 'unique_item_code',  'fold',  1.0),
    ('medicine_code',     'medicines',          'medicine_code',     'exact', 1.0),
    ('medicine_name',     'medicines',          'medicine_name',     'name',  0.9),
    ('medicine_name',     'medicines',          'composition',       'name',  0.7),
    ('manufacturer_name', 'manufacturers',      'manufacturer_name', 'name',  0.9),
    ('batch_no',          'production_batches', 'batch_no',          'exact', 1.0),
    ('text',              'medicines',          'medicine_name',     'name',  0.7),
    ('text',              'manufacturers',      'manufacturer_name', 'name',  0.7),
    ('text',              'plants',             'city',              'name',  0.5),
    ('text',              'qc_reports',         'remarks',           'text',  0.6)
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

-- ---------------------------------------------------------------------
-- Check
-- ---------------------------------------------------------------------
SELECT table_name, role, fk_links,
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM public.%I', table_name), false, true, '')))[1]::text::int AS row_count
FROM asli_ctx.v_schema ORDER BY fk_links DESC, table_name;
