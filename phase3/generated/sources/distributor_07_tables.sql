-- =====================================================================
-- Asli-or-Nakli · Phase 3 · distributor_db: new tables (FK -> PK) + data
-- RUN ON: distributor_db, after asli_ctx_core.sql.  Alt+X.  Safe to re-run.
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
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.warehouses (
    warehouse_id   serial PRIMARY KEY,
    distributor_id int  NOT NULL REFERENCES public.distributors (distributor_id),
    warehouse_name varchar(150) NOT NULL UNIQUE,
    city           varchar(80)  NOT NULL,
    drug_licence   varchar(40)  NOT NULL,
    has_cold_room  boolean NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.shipments (
    shipment_id   serial PRIMARY KEY,
    shipment_no   varchar(30) NOT NULL UNIQUE,
    warehouse_id  int  NOT NULL REFERENCES public.warehouses (warehouse_id),
    shop_name     varchar(150) NOT NULL,      -- = vendor_db.vendors.vendor_name
    dispatched_on date NOT NULL,
    vehicle_no    varchar(20),
    carrier       varchar(80)
);

CREATE TABLE IF NOT EXISTS public.shipment_lines (
    line_id      serial PRIMARY KEY,
    shipment_id  int NOT NULL REFERENCES public.shipments (shipment_id) ON DELETE CASCADE,
    product_code varchar(50) NOT NULL UNIQUE REFERENCES public.inventory_items (product_code) ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS public.temperature_logs (
    log_id      serial PRIMARY KEY,
    shipment_id int NOT NULL REFERENCES public.shipments (shipment_id) ON DELETE CASCADE,
    logged_at   timestamp NOT NULL,
    temp_c      numeric(4, 1) NOT NULL,
    note        text
);

CREATE INDEX IF NOT EXISTS warehouses_distributor_idx ON public.warehouses (distributor_id);
CREATE INDEX IF NOT EXISTS shipments_warehouse_idx    ON public.shipments (warehouse_id);
CREATE INDEX IF NOT EXISTS shipments_shop_idx         ON public.shipments (lower(shop_name));
CREATE INDEX IF NOT EXISTS lines_shipment_idx         ON public.shipment_lines (shipment_id);
CREATE INDEX IF NOT EXISTS templogs_shipment_idx      ON public.temperature_logs (shipment_id);
CREATE INDEX IF NOT EXISTS templogs_note_fts ON public.temperature_logs USING gin (to_tsvector('english', coalesce(note, '')));

-- ---------------------------------------------------------------------
-- Data, derived from the rows that are already here
-- ---------------------------------------------------------------------
INSERT INTO public.warehouses (distributor_id, warehouse_name, city, drug_licence, has_cold_room)
SELECT d.distributor_id, d.distributor_name || ' — Main Warehouse', btrim(split_part(d.address, ',', 1)),
       'DL-WH-' || lpad(d.distributor_id::text, 3, '0'), d.distributor_id % 2 = 1
FROM public.distributors d
ON CONFLICT (warehouse_name) DO NOTHING;

-- one shipment per distributor, shop and supply day
INSERT INTO public.shipments (shipment_no, warehouse_id, shop_name, dispatched_on, vehicle_no, carrier)
SELECT 'SHP-' || to_char(g.supply_date, 'YYMMDD') || '-' || lpad(g.distributor_id::text, 2, '0') || '-'
         || lpad(dense_rank() OVER (PARTITION BY g.supply_date, g.distributor_id ORDER BY g.shop)::text, 2, '0'),
       w.warehouse_id, g.shop, g.supply_date,
       'DL1L' || chr(65 + g.distributor_id) || lpad((1000 + 37 * g.distributor_id)::text, 4, '0'),
       (ARRAY['SafeRoute Logistics', 'ColdLine Carriers', 'MetroMed Transport'])[1 + g.distributor_id % 3]
FROM (SELECT DISTINCT ii.distributor_id, s.vendor_reference AS shop, s.supply_date
      FROM public.supplied_items s JOIN public.inventory_items ii ON ii.product_code = s.product_code) g
JOIN public.warehouses w ON w.distributor_id = g.distributor_id
ON CONFLICT (shipment_no) DO NOTHING;

INSERT INTO public.shipment_lines (shipment_id, product_code)
SELECT sh.shipment_id, s.product_code
FROM public.supplied_items s
JOIN public.inventory_items ii ON ii.product_code = s.product_code
JOIN public.warehouses w ON w.distributor_id = ii.distributor_id
JOIN public.shipments sh ON sh.warehouse_id = w.warehouse_id AND sh.shop_name = s.vendor_reference
                        AND sh.dispatched_on = s.supply_date
ON CONFLICT (product_code) DO NOTHING;

-- three normal readings per shipment
INSERT INTO public.temperature_logs (shipment_id, logged_at, temp_c, note)
SELECT sh.shipment_id, sh.dispatched_on + t.at, t.temp, NULL
FROM public.shipments sh
CROSS JOIN (VALUES (time '08:00', 21.5), (time '11:00', 23.0), (time '14:00', 24.0)) t(at, temp)
WHERE NOT EXISTS (SELECT 1 FROM public.temperature_logs l WHERE l.shipment_id = sh.shipment_id);

-- demo story 1: a temperature excursion on the shipments carrying Amoxicillin
UPDATE public.temperature_logs l SET temp_c = 34.5,
       note = 'Temperature excursion: 34.5 °C for about 5 hours after the vehicle AC failed near Panipat. '
           || 'Amoxicillin capsules on board are labelled "store below 25 °C". Cartons were not quarantined; '
           || 'stock was delivered to the shop the same evening.'
WHERE l.logged_at::time = time '14:00'
  AND l.shipment_id IN (SELECT sl.shipment_id FROM public.shipment_lines sl
                        JOIN public.inventory_items ii ON ii.product_code = sl.product_code
                        WHERE upper(ii.drug_name) LIKE 'AMOXICILLIN%');

-- demo story 2: a broken seal on the shipment carrying Ibuprofen to Karol Bagh
UPDATE public.temperature_logs l SET
       note = 'Delivery note: outer carton seal found broken on arrival at the shop; driver says the carton was '
           || 'repacked at an unscheduled stop. Ibuprofen 400mg strips counted and accepted by the shop.'
WHERE l.logged_at::time = time '11:00'
  AND l.shipment_id IN (SELECT sl.shipment_id FROM public.shipment_lines sl
                        JOIN public.inventory_items ii ON ii.product_code = sl.product_code
                        WHERE upper(ii.drug_name) LIKE 'IBUPROFEN%');

-- ---------------------------------------------------------------------
-- Context-discovery config for this source
-- ---------------------------------------------------------------------
INSERT INTO asli_ctx.entry_points (seed_kind, table_name, column_name, match, weight) VALUES
    ('item_code',        'inventory_items',  'product_code',     'fold',  1.0),
    ('item_code',        'supplied_items',   'product_code',     'fold',  0.9),
    ('distributor_id',   'distributors',     'distributor_id',   'exact', 1.0),
    ('distributor_name', 'distributors',     'distributor_name', 'name',  0.9),
    ('vendor_name',      'shipments',        'shop_name',        'name',  0.6),
    ('vendor_name',      'supplied_items',   'vendor_reference', 'name',  0.5),
    ('medicine_name',    'inventory_items',  'drug_name',        'name',  0.5),
    ('text',             'distributors',     'distributor_name', 'name',  0.6),
    ('text',             'shipments',        'shop_name',        'name',  0.4),
    ('text',             'temperature_logs', 'note',             'text',  0.6)
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

-- ---------------------------------------------------------------------
-- Check
-- ---------------------------------------------------------------------
SELECT table_name, role, fk_links,
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM public.%I', table_name), false, true, '')))[1]::text::int AS row_count
FROM asli_ctx.v_schema ORDER BY fk_links DESC, table_name;
