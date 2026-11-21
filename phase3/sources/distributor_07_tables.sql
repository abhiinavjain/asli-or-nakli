-- =====================================================================
-- Asli-or-Nakli · Phase 3 · distributor_db: new tables (FK -> PK) + data
-- RUN ON: distributor_db (NOT the default "postgres" database), after
--         asli_ctx_core.sql.  Alt+X.  Safe to re-run; re-running also upgrades
--         an earlier install of this script.
-- Existing tables are NOT changed: distributors, inventory_items, supplied_items.
-- =====================================================================
--
--   distributors (existing) 1──< warehouses 1──< shipments 1──< shipment_lines >──1 inventory_items (existing)
--                                                   │
--                                                   1──< temperature_logs
--
--   warehouses        where the distributor stores stock (drug licence, cold room)
--   shipments         one dispatch to one shop on one day (vehicle, carrier);
--                     shop_name links to the vendor database (cross-database key)
--   shipment_lines    which item codes travelled in which shipment
--   temperature_logs  readings during transport, with free-text incident notes
--
-- Live data: a trigger puts every new supply record on a shipment (created if
-- needed). The foreign keys cascade, so the Phase 2 fix scripts can still delete
-- a duplicate stock record or rename its code.
-- =====================================================================

SELECT current_database() AS running_on;   -- must say distributor_db

CREATE TABLE IF NOT EXISTS public.warehouses (
    warehouse_id   serial PRIMARY KEY,
    distributor_id int  NOT NULL,
    warehouse_name varchar(150) NOT NULL UNIQUE,
    city           varchar(80)  NOT NULL,
    drug_licence   varchar(40)  NOT NULL,
    has_cold_room  boolean NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.shipments (
    shipment_id   serial PRIMARY KEY,
    shipment_no   varchar(40) NOT NULL UNIQUE,
    warehouse_id  int  NOT NULL,
    shop_name     varchar(150) NOT NULL,      -- = vendor_db.vendors.vendor_name
    dispatched_on date NOT NULL,
    vehicle_no    varchar(20),
    carrier       varchar(80)
);

CREATE TABLE IF NOT EXISTS public.shipment_lines (
    line_id      serial PRIMARY KEY,
    shipment_id  int NOT NULL,
    product_code varchar(50) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS public.temperature_logs (
    log_id      serial PRIMARY KEY,
    shipment_id int NOT NULL,
    logged_at   timestamp NOT NULL,
    temp_c      numeric(4, 1) NOT NULL,
    note        text
);

-- constraints (dropped and re-added, so an earlier install gets the cascades)
ALTER TABLE public.shipments ALTER COLUMN shipment_no TYPE varchar(40);

ALTER TABLE public.warehouses DROP CONSTRAINT IF EXISTS warehouses_distributor_id_fkey;
ALTER TABLE public.warehouses ADD CONSTRAINT warehouses_distributor_id_fkey
    FOREIGN KEY (distributor_id) REFERENCES public.distributors (distributor_id) ON DELETE CASCADE;

ALTER TABLE public.shipments DROP CONSTRAINT IF EXISTS shipments_warehouse_id_fkey;
ALTER TABLE public.shipments ADD CONSTRAINT shipments_warehouse_id_fkey
    FOREIGN KEY (warehouse_id) REFERENCES public.warehouses (warehouse_id) ON DELETE CASCADE;

ALTER TABLE public.shipment_lines DROP CONSTRAINT IF EXISTS shipment_lines_shipment_id_fkey;
ALTER TABLE public.shipment_lines ADD CONSTRAINT shipment_lines_shipment_id_fkey
    FOREIGN KEY (shipment_id) REFERENCES public.shipments (shipment_id) ON DELETE CASCADE;

-- a cleansing fix may rename a stock record's code (follow it) or delete a
-- duplicate stock record (its shipment line goes with it)
ALTER TABLE public.shipment_lines DROP CONSTRAINT IF EXISTS shipment_lines_product_code_fkey;
ALTER TABLE public.shipment_lines ADD CONSTRAINT shipment_lines_product_code_fkey
    FOREIGN KEY (product_code) REFERENCES public.inventory_items (product_code) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE public.temperature_logs DROP CONSTRAINT IF EXISTS temperature_logs_shipment_id_fkey;
ALTER TABLE public.temperature_logs ADD CONSTRAINT temperature_logs_shipment_id_fkey
    FOREIGN KEY (shipment_id) REFERENCES public.shipments (shipment_id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS warehouses_distributor_idx ON public.warehouses (distributor_id);
CREATE INDEX IF NOT EXISTS shipments_warehouse_idx    ON public.shipments (warehouse_id, lower(shop_name), dispatched_on);
CREATE INDEX IF NOT EXISTS lines_shipment_idx         ON public.shipment_lines (shipment_id);
CREATE INDEX IF NOT EXISTS templogs_shipment_idx      ON public.temperature_logs (shipment_id);
CREATE INDEX IF NOT EXISTS templogs_note_fts ON public.temperature_logs USING gin (to_tsvector('english', coalesce(note, '')));
-- indexes for the context entry points (prefix names, folded codes)
CREATE INDEX IF NOT EXISTS inventory_drug_prefix  ON public.inventory_items (lower(drug_name::text) text_pattern_ops);
CREATE INDEX IF NOT EXISTS supplied_code_fold     ON public.supplied_items (asli.fold(product_code::text));

-- ---------------------------------------------------------------------
-- Linking: one function, used by the trigger (live rows) and the refresh
-- ---------------------------------------------------------------------
-- a supply record -> the shipment of (its distributor's warehouse, shop, day)
CREATE OR REPLACE FUNCTION asli_ctx.link_supply(p_product_code text) RETURNS int
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    s     record;
    v_wid int;
    v_sid int;
BEGIN
    SELECT si.product_code, si.vendor_reference, si.supply_date, ii.distributor_id
      INTO s
      FROM public.supplied_items si JOIN public.inventory_items ii ON ii.product_code = si.product_code
     WHERE si.product_code = p_product_code;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT warehouse_id INTO v_wid FROM public.warehouses WHERE distributor_id = s.distributor_id
     ORDER BY warehouse_id LIMIT 1;
    IF v_wid IS NULL THEN
        INSERT INTO public.warehouses (distributor_id, warehouse_name, city, drug_licence, has_cold_room)
        SELECT d.distributor_id, d.distributor_name || ' — Main Warehouse',
               coalesce(nullif(btrim(split_part(d.address, ',', 1)), ''), 'Unknown'),
               'DL-WH-' || lpad(d.distributor_id::text, 3, '0'), d.distributor_id % 2 = 1
        FROM public.distributors d WHERE d.distributor_id = s.distributor_id
        RETURNING warehouse_id INTO v_wid;
    END IF;

    SELECT shipment_id INTO v_sid FROM public.shipments
     WHERE warehouse_id = v_wid AND lower(shop_name) = lower(s.vendor_reference) AND dispatched_on = s.supply_date;
    IF v_sid IS NULL THEN
        INSERT INTO public.shipments (shipment_no, warehouse_id, shop_name, dispatched_on, vehicle_no, carrier)
        VALUES ('SHP-' || to_char(s.supply_date, 'YYMMDD') || '-' || lpad(s.distributor_id::text, 4, '0') || '-'
                  || upper(substr(md5(lower(s.vendor_reference)), 1, 4)),
                v_wid, s.vendor_reference, s.supply_date,
                'DL1L' || chr(65 + s.distributor_id % 26) || lpad((1000 + 37 * s.distributor_id)::text, 4, '0'),
                (ARRAY['SafeRoute Logistics', 'ColdLine Carriers', 'MetroMed Transport'])[1 + s.distributor_id % 3])
        ON CONFLICT (shipment_no) DO UPDATE SET shop_name = EXCLUDED.shop_name
        RETURNING shipment_id INTO v_sid;
        INSERT INTO public.temperature_logs (shipment_id, logged_at, temp_c, note)
        SELECT v_sid, s.supply_date + t.at, t.temp, NULL
        FROM (VALUES (time '08:00', 21.5), (time '11:00', 23.0), (time '14:00', 24.0)) t(at, temp)
        WHERE NOT EXISTS (SELECT 1 FROM public.temperature_logs l WHERE l.shipment_id = v_sid);
    END IF;

    INSERT INTO public.shipment_lines (shipment_id, product_code) VALUES (v_sid, s.product_code)
    ON CONFLICT (product_code) DO UPDATE SET shipment_id = EXCLUDED.shipment_id;
    RETURN v_sid;
END;
$$;

CREATE OR REPLACE FUNCTION asli_ctx.refresh_links() RETURNS int
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    r record;
    n int := 0;
BEGIN
    FOR r IN SELECT si.product_code FROM public.supplied_items si
             LEFT JOIN public.shipment_lines sl ON sl.product_code = si.product_code
             LEFT JOIN public.shipments sh ON sh.shipment_id = sl.shipment_id
             WHERE sh.shipment_id IS NULL
                OR lower(sh.shop_name) <> lower(si.vendor_reference)
                OR sh.dispatched_on <> si.supply_date LOOP
        BEGIN   -- one bad row (e.g. a NULL date) must not stop the whole script
            PERFORM asli_ctx.link_supply(r.product_code);
            n := n + 1;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Phase 3: supply % not linked: %', r.product_code, SQLERRM;
        END;
    END LOOP;
    RETURN n;
END;
$$;

-- live rows: never blocks the insert, a linking problem is only a warning
CREATE OR REPLACE FUNCTION asli_ctx.trg_link_supply() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        PERFORM asli_ctx.link_supply(NEW.product_code);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Phase 3: supply % not put on a shipment: %', NEW.product_code, SQLERRM;
    END;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS asli_link_supply ON public.supplied_items;
CREATE TRIGGER asli_link_supply AFTER INSERT OR UPDATE OF product_code, vendor_reference, supply_date
    ON public.supplied_items FOR EACH ROW EXECUTE FUNCTION asli_ctx.trg_link_supply();

-- ---------------------------------------------------------------------
-- Data, derived from the rows that are already here
-- ---------------------------------------------------------------------
INSERT INTO public.warehouses (distributor_id, warehouse_name, city, drug_licence, has_cold_room)
SELECT d.distributor_id, d.distributor_name || ' — Main Warehouse',
       coalesce(nullif(btrim(split_part(d.address, ',', 1)), ''), 'Unknown'),
       'DL-WH-' || lpad(d.distributor_id::text, 3, '0'), d.distributor_id % 2 = 1
FROM public.distributors d
ON CONFLICT (warehouse_name) DO NOTHING;

SELECT asli_ctx.refresh_links() AS supplies_linked;

-- ---------------------------------------------------------------------
-- The demo story, on ONE shipment each (earlier story notes are reset first):
--   excursion   : the shipment carrying ITEM000035 (Amoxicillin), else the
--                 first shipment carrying Amoxicillin
--   broken seal : the shipment carrying ITEM000041 (Ibuprofen), else the first
--                 shipment carrying Ibuprofen
-- ---------------------------------------------------------------------
UPDATE public.temperature_logs SET temp_c = 24.0, note = NULL WHERE note LIKE 'Temperature excursion: 34.5%';
UPDATE public.temperature_logs SET note = NULL WHERE note LIKE 'Delivery note: outer carton seal found broken%';

INSERT INTO asli_ctx.demo_story (key, value)
SELECT 'excursion_shipment', coalesce(
         (SELECT sh.shipment_no FROM public.shipment_lines sl JOIN public.shipments sh USING (shipment_id)
          JOIN public.inventory_items ii ON ii.product_code = sl.product_code
          WHERE asli.fold(sl.product_code) = asli.fold('ITEM000035') AND upper(ii.drug_name) LIKE 'AMOXICILLIN%' LIMIT 1),
         (SELECT sh.shipment_no FROM public.shipment_lines sl JOIN public.shipments sh USING (shipment_id)
          JOIN public.inventory_items ii ON ii.product_code = sl.product_code
          WHERE upper(ii.drug_name) LIKE 'AMOXICILLIN%' ORDER BY sh.dispatched_on, sh.shipment_id LIMIT 1))
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO asli_ctx.demo_story (key, value)
SELECT 'seal_shipment', coalesce(
         (SELECT sh.shipment_no FROM public.shipment_lines sl JOIN public.shipments sh USING (shipment_id)
          JOIN public.inventory_items ii ON ii.product_code = sl.product_code
          WHERE asli.fold(sl.product_code) = asli.fold('ITEM000041') AND upper(ii.drug_name) LIKE 'IBUPROFEN%' LIMIT 1),
         (SELECT sh.shipment_no FROM public.shipment_lines sl JOIN public.shipments sh USING (shipment_id)
          JOIN public.inventory_items ii ON ii.product_code = sl.product_code
          WHERE upper(ii.drug_name) LIKE 'IBUPROFEN%' ORDER BY sh.dispatched_on, sh.shipment_id LIMIT 1))
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

UPDATE public.temperature_logs l SET temp_c = 34.5,
       note = 'Temperature excursion: 34.5 °C for about 5 hours after the vehicle AC failed near Panipat. '
           || 'Amoxicillin capsules on board are labelled "store below 25 °C". Cartons were not quarantined; '
           || 'stock was delivered to the shop the same evening.'
FROM public.shipments sh
WHERE sh.shipment_id = l.shipment_id AND l.logged_at::time = time '14:00'
  AND sh.shipment_no = (SELECT value FROM asli_ctx.demo_story WHERE key = 'excursion_shipment');

UPDATE public.temperature_logs l SET
       note = 'Delivery note: outer carton seal found broken on arrival at the shop; driver says the carton was '
           || 'repacked at an unscheduled stop. Ibuprofen 400mg strips counted and accepted by the shop.'
FROM public.shipments sh
WHERE sh.shipment_id = l.shipment_id AND l.logged_at::time = time '11:00'
  AND sh.shipment_no = (SELECT value FROM asli_ctx.demo_story WHERE key = 'seal_shipment');

-- ---------------------------------------------------------------------
-- Context-discovery config for this source
-- ---------------------------------------------------------------------
INSERT INTO asli_ctx.entry_points (seed_kind, table_name, column_name, match, weight) VALUES
    ('item_code',        'inventory_items',  'product_code',     'fold',   1.0),
    ('item_code',        'supplied_items',   'product_code',     'fold',   0.9),
    ('distributor_id',   'distributors',     'distributor_id',   'exact',  1.0),
    ('distributor_name', 'distributors',     'distributor_name', 'name',   0.9),
    ('vendor_name',      'shipments',        'shop_name',        'name',   0.6),
    ('vendor_name',      'supplied_items',   'vendor_reference', 'name',   0.5),
    ('medicine_name',    'inventory_items',  'drug_name',        'prefix', 0.5),
    ('text',             'inventory_items',  'drug_name',        'prefix', 0.6),
    ('text',             'distributors',     'distributor_name', 'name',   0.6),
    ('text',             'shipments',        'shop_name',        'name',   0.4),
    ('text',             'temperature_logs', 'note',             'text',   0.6)
ON CONFLICT (seed_kind, table_name, column_name) DO UPDATE SET match = EXCLUDED.match, weight = EXCLUDED.weight;

INSERT INTO asli_ctx.table_roles (table_name, role, weight, label) VALUES
    ('distributors',     'hub',    0.8, 'Distributor'),
    ('warehouses',       'entity', 0.8, 'Warehouse'),
    ('inventory_items',  'entity', 1.0, 'Distributor stock record'),
    ('supplied_items',   'entity', 1.0, 'Supply to a shop'),
    ('shipments',        'entity', 1.0, 'Shipment'),
    ('shipment_lines',   'link',   1.0, 'Item ↔ shipment'),
    ('temperature_logs', 'detail', 1.1, 'Transport log')
ON CONFLICT (table_name) DO UPDATE SET role = EXCLUDED.role, weight = EXCLUDED.weight, label = EXCLUDED.label;

INSERT INTO asli_ctx.private_columns VALUES ('distributors', 'contact_number', 'drop')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- Check
-- ---------------------------------------------------------------------
SELECT table_name, role, fk_links,
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM public.%I', table_name), false, true, '')))[1]::text::int AS row_count
FROM asli_ctx.v_schema ORDER BY fk_links DESC, table_name;

SELECT key, value FROM asli_ctx.demo_story ORDER BY key;
