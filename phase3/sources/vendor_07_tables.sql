-- =====================================================================
-- Asli-or-Nakli · Phase 3 · vendor_db: new tables (FK -> PK) + data
-- RUN ON: vendor_db (NOT the default "postgres" database), after
--         asli_ctx_core.sql.  Alt+X.  Safe to re-run; re-running also upgrades
--         an earlier install of this script.
-- Existing tables are NOT changed: vendors, vendor_inventory, medicine_sales.
-- =====================================================================
--
--   vendors (existing) 1──< purchase_invoices 1──< invoice_lines >──1 vendor_inventory (existing)
--        │
--        1──< customer_complaints >──1 customers 1──< sale_customers >──1 medicine_sales (existing)
--                     │
--                     >──1 vendor_inventory (the pack complained about)
--
--   purchase_invoices    the shop's purchase bill from a distributor;
--                        distributor_id links to distributor_db (cross-database key)
--   invoice_lines        which stock records each bill covers
--   customers            the shop's customers (masked phone)
--   sale_customers       which customer each sale was to (link table, so
--                        medicine_sales keeps its schema)
--   customer_complaints  free-text complaints about a pack / sale
--
-- Live data: triggers put every new stock record on a purchase bill and every
-- new sale on a customer. The foreign keys cascade, so the Phase 2 fix scripts
-- can still delete a stock record. Customer names never leave this database
-- unmasked (asli_ctx.private_columns).
-- =====================================================================

SELECT current_database() AS running_on;   -- must say vendor_db

CREATE TABLE IF NOT EXISTS public.customers (
    customer_id   serial PRIMARY KEY,
    customer_ref  varchar(100) NOT NULL UNIQUE,   -- = medicine_sales.customer_reference
    full_name     varchar(120) NOT NULL,
    phone_masked  varchar(20),
    area          varchar(80)
);

CREATE TABLE IF NOT EXISTS public.sale_customers (
    sale_id     int PRIMARY KEY,
    customer_id int NOT NULL
);

CREATE TABLE IF NOT EXISTS public.purchase_invoices (
    invoice_id     serial PRIMARY KEY,
    invoice_no     varchar(30) NOT NULL UNIQUE,
    vendor_id      int  NOT NULL,
    distributor_id int  NOT NULL,                 -- = distributor_db.distributors.distributor_id
    invoice_date   date NOT NULL,
    total_amount   numeric(10, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.invoice_lines (
    line_id      serial PRIMARY KEY,
    invoice_id   int NOT NULL,
    inventory_id int NOT NULL UNIQUE,
    unit_price   numeric(8, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_complaints (
    complaint_id   serial PRIMARY KEY,
    vendor_id      int  NOT NULL,
    inventory_id   int,
    customer_id    int,
    reported_on    date NOT NULL,
    channel        varchar(20) NOT NULL CHECK (channel IN ('COUNTER', 'PHONE', 'WHATSAPP', 'EMAIL')),
    complaint_text text NOT NULL,
    status         varchar(20) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'FORWARDED', 'CLOSED'))
);

-- constraints (dropped and re-added, so an earlier install gets the cascades)
ALTER TABLE public.sale_customers DROP CONSTRAINT IF EXISTS sale_customers_sale_id_fkey;
ALTER TABLE public.sale_customers ADD CONSTRAINT sale_customers_sale_id_fkey
    FOREIGN KEY (sale_id) REFERENCES public.medicine_sales (sale_id) ON DELETE CASCADE;
ALTER TABLE public.sale_customers DROP CONSTRAINT IF EXISTS sale_customers_customer_id_fkey;
ALTER TABLE public.sale_customers ADD CONSTRAINT sale_customers_customer_id_fkey
    FOREIGN KEY (customer_id) REFERENCES public.customers (customer_id) ON DELETE CASCADE;
ALTER TABLE public.purchase_invoices DROP CONSTRAINT IF EXISTS purchase_invoices_vendor_id_fkey;
ALTER TABLE public.purchase_invoices ADD CONSTRAINT purchase_invoices_vendor_id_fkey
    FOREIGN KEY (vendor_id) REFERENCES public.vendors (vendor_id) ON DELETE CASCADE;
ALTER TABLE public.invoice_lines DROP CONSTRAINT IF EXISTS invoice_lines_invoice_id_fkey;
ALTER TABLE public.invoice_lines ADD CONSTRAINT invoice_lines_invoice_id_fkey
    FOREIGN KEY (invoice_id) REFERENCES public.purchase_invoices (invoice_id) ON DELETE CASCADE;
ALTER TABLE public.invoice_lines DROP CONSTRAINT IF EXISTS invoice_lines_inventory_id_fkey;
ALTER TABLE public.invoice_lines ADD CONSTRAINT invoice_lines_inventory_id_fkey
    FOREIGN KEY (inventory_id) REFERENCES public.vendor_inventory (inventory_id) ON DELETE CASCADE;
ALTER TABLE public.customer_complaints DROP CONSTRAINT IF EXISTS customer_complaints_vendor_id_fkey;
ALTER TABLE public.customer_complaints ADD CONSTRAINT customer_complaints_vendor_id_fkey
    FOREIGN KEY (vendor_id) REFERENCES public.vendors (vendor_id) ON DELETE CASCADE;
ALTER TABLE public.customer_complaints DROP CONSTRAINT IF EXISTS customer_complaints_inventory_id_fkey;
ALTER TABLE public.customer_complaints ADD CONSTRAINT customer_complaints_inventory_id_fkey
    FOREIGN KEY (inventory_id) REFERENCES public.vendor_inventory (inventory_id) ON DELETE SET NULL;
ALTER TABLE public.customer_complaints DROP CONSTRAINT IF EXISTS customer_complaints_customer_id_fkey;
ALTER TABLE public.customer_complaints ADD CONSTRAINT customer_complaints_customer_id_fkey
    FOREIGN KEY (customer_id) REFERENCES public.customers (customer_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS invoices_vendor_idx   ON public.purchase_invoices (vendor_id, distributor_id, invoice_date);

CREATE INDEX IF NOT EXISTS invoices_dist_idx     ON public.purchase_invoices (distributor_id);
CREATE INDEX IF NOT EXISTS inv_lines_invoice_idx ON public.invoice_lines (invoice_id);
CREATE INDEX IF NOT EXISTS sale_cust_idx         ON public.sale_customers (customer_id);
CREATE INDEX IF NOT EXISTS complaints_vendor_idx ON public.customer_complaints (vendor_id);
CREATE INDEX IF NOT EXISTS complaints_inv_idx    ON public.customer_complaints (inventory_id);
CREATE INDEX IF NOT EXISTS complaints_text_fts ON public.customer_complaints
    USING gin (to_tsvector('english', complaint_text));
CREATE INDEX IF NOT EXISTS vendor_inv_name_prefix ON public.vendor_inventory (lower(medicine_name::text) text_pattern_ops);

-- ---------------------------------------------------------------------
-- Linking: used by the triggers (live rows) and the refresh
-- ---------------------------------------------------------------------
-- a stock record -> the purchase bill of (shop, distributor, receiving day)
CREATE OR REPLACE FUNCTION asli_ctx.link_stock(p_inventory_id int) RETURNS int
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v     record;
    v_iid int;
BEGIN
    SELECT inventory_id, vendor_id, distributor_id, received_date INTO v
      FROM public.vendor_inventory WHERE inventory_id = p_inventory_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    -- the bill of this shop, distributor and day (whatever number an earlier version gave it)
    SELECT invoice_id INTO v_iid FROM public.purchase_invoices
     WHERE vendor_id = v.vendor_id AND distributor_id = v.distributor_id AND invoice_date = v.received_date
     ORDER BY invoice_id LIMIT 1;
    IF v_iid IS NULL THEN
        INSERT INTO public.purchase_invoices (invoice_no, vendor_id, distributor_id, invoice_date, total_amount)
        VALUES ('INV-' || lpad(v.vendor_id::text, 4, '0') || '-' || lpad(v.distributor_id::text, 4, '0') || '-'
                  || to_char(v.received_date, 'YYMMDD'), v.vendor_id, v.distributor_id, v.received_date, 0)
        ON CONFLICT (invoice_no) DO UPDATE SET invoice_date = EXCLUDED.invoice_date
        RETURNING invoice_id INTO v_iid;
    END IF;
    INSERT INTO public.invoice_lines (invoice_id, inventory_id, unit_price) VALUES (v_iid, p_inventory_id, 180.00)
    ON CONFLICT (inventory_id) DO UPDATE SET invoice_id = EXCLUDED.invoice_id;
    UPDATE public.purchase_invoices pi
       SET total_amount = (SELECT coalesce(sum(unit_price), 0) FROM public.invoice_lines WHERE invoice_id = v_iid)
     WHERE pi.invoice_id = v_iid;
    RETURN v_iid;
END;
$$;

-- a sale -> its customer (created as a walk-in customer if unknown)
CREATE OR REPLACE FUNCTION asli_ctx.link_sale(p_sale_id int) RETURNS int
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_ref text;
    v_cid int;
BEGIN
    SELECT coalesce(nullif(btrim(customer_reference), ''), 'WALKIN-SALE-' || sale_id) INTO v_ref
      FROM public.medicine_sales WHERE sale_id = p_sale_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    INSERT INTO public.customers (customer_ref, full_name, phone_masked, area)
    VALUES (v_ref, 'Walk-in customer', NULL, NULL)
    ON CONFLICT (customer_ref) DO UPDATE SET customer_ref = EXCLUDED.customer_ref
    RETURNING customer_id INTO v_cid;
    INSERT INTO public.sale_customers (sale_id, customer_id) VALUES (p_sale_id, v_cid)
    ON CONFLICT (sale_id) DO UPDATE SET customer_id = EXCLUDED.customer_id;
    RETURN v_cid;
END;
$$;

CREATE OR REPLACE FUNCTION asli_ctx.refresh_links() RETURNS int
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    r record;
    n int := 0;
BEGIN
    FOR r IN SELECT vi.inventory_id FROM public.vendor_inventory vi
             LEFT JOIN public.invoice_lines il ON il.inventory_id = vi.inventory_id
             LEFT JOIN public.purchase_invoices pi ON pi.invoice_id = il.invoice_id
             WHERE pi.invoice_id IS NULL OR pi.vendor_id <> vi.vendor_id
                OR pi.distributor_id <> vi.distributor_id OR pi.invoice_date <> vi.received_date LOOP
        BEGIN   -- one bad row (e.g. a NULL date) must not stop the whole script
            PERFORM asli_ctx.link_stock(r.inventory_id);
            n := n + 1;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Phase 3: stock record % not linked: %', r.inventory_id, SQLERRM;
        END;
    END LOOP;
    FOR r IN SELECT s.sale_id FROM public.medicine_sales s
             LEFT JOIN public.sale_customers sc ON sc.sale_id = s.sale_id WHERE sc.sale_id IS NULL LOOP
        BEGIN   -- one bad row (e.g. a NULL date) must not stop the whole script
            PERFORM asli_ctx.link_sale(r.sale_id);
            n := n + 1;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Phase 3: sale % not linked: %', r.sale_id, SQLERRM;
        END;
    END LOOP;
    RETURN n;
END;
$$;

-- live rows: never block the insert, a linking problem is only a warning
CREATE OR REPLACE FUNCTION asli_ctx.trg_link_stock() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        PERFORM asli_ctx.link_stock(NEW.inventory_id);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Phase 3: stock record % not put on a bill: %', NEW.inventory_id, SQLERRM;
    END;
    RETURN NEW;
END;
$$;
CREATE OR REPLACE FUNCTION asli_ctx.trg_link_sale() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        PERFORM asli_ctx.link_sale(NEW.sale_id);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Phase 3: sale % not linked to a customer: %', NEW.sale_id, SQLERRM;
    END;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS asli_link_stock ON public.vendor_inventory;
CREATE TRIGGER asli_link_stock AFTER INSERT OR UPDATE OF vendor_id, distributor_id, received_date
    ON public.vendor_inventory FOR EACH ROW EXECUTE FUNCTION asli_ctx.trg_link_stock();
DROP TRIGGER IF EXISTS asli_link_sale ON public.medicine_sales;
CREATE TRIGGER asli_link_sale AFTER INSERT OR UPDATE OF customer_reference
    ON public.medicine_sales FOR EACH ROW EXECUTE FUNCTION asli_ctx.trg_link_sale();


-- ---------------------------------------------------------------------
-- Data, derived from the rows that are already here
-- ---------------------------------------------------------------------
INSERT INTO public.customers (customer_ref, full_name, phone_masked, area)
SELECT r.ref,
       (ARRAY['Aarav Mehta', 'Priya Sharma', 'Rohan Gupta', 'Ananya Singh', 'Vikram Rao', 'Neha Kapoor',
              'Arjun Nair', 'Sneha Iyer', 'Kabir Malhotra', 'Isha Verma', 'Dev Bansal', 'Meera Joshi'])
           [1 + (r.n - 1) % 12],
       '98XXXXX' || lpad((100 + r.n)::text, 3, '0'),
       (ARRAY['Karol Bagh', 'Lajpat Nagar', 'Dwarka', 'Rohini', 'Saket'])[1 + (r.n - 1) % 5]
FROM (SELECT ref, row_number() OVER (ORDER BY ref)::int AS n
      FROM (SELECT DISTINCT customer_reference AS ref FROM public.medicine_sales WHERE customer_reference IS NOT NULL
            UNION SELECT 'WALKIN-' || lpad(g::text, 3, '0') FROM generate_series(1, 6) g) x) r
ON CONFLICT (customer_ref) DO NOTHING;

-- every stock record on a purchase bill, every sale on a customer
SELECT asli_ctx.refresh_links() AS rows_linked;

-- complaints: the demo story (Ibuprofen, Amoxicillin) plus ordinary ones
INSERT INTO public.customer_complaints (vendor_id, inventory_id, customer_id, reported_on, channel, complaint_text, status)
SELECT x.vendor_id, x.inventory_id,
       (SELECT customer_id FROM public.customers ORDER BY customer_id OFFSET x.cust LIMIT 1),
       x.reported_on, x.channel, x.txt, x.status
FROM (
    SELECT coalesce(vi.vendor_id, 1) AS vendor_id, vi.inventory_id, 0 AS cust, DATE '2026-11-02' AS reported_on,
           'COUNTER' AS channel, 'FORWARDED' AS status,
           'Ibuprofen 400mg strip looks different from my usual one: tablets are crumbly and slightly yellow, '
           || 'the foil print is blurred and there is no hologram on the box. Pain did not reduce after two '
           || 'tablets. Customer asked whether the medicine is fake.' AS txt
    FROM (SELECT 1) one
    LEFT JOIN LATERAL (SELECT * FROM public.vendor_inventory WHERE medicine_name ILIKE 'ibuprofen%'
                       ORDER BY (asli.fold(item_identifier) = asli.fold('ITEM000041')) DESC, vendor_id, inventory_id LIMIT 1) vi ON true
    UNION ALL
    SELECT coalesce(vi.vendor_id, 1), vi.inventory_id, 1, DATE '2026-11-06', 'WHATSAPP', 'OPEN',
           'Bought Ibuprofen 400mg here last week. Box batch number is printed with a sticker over another '
           || 'number, and the expiry date looks altered. Stomach pain after taking it.'
    FROM (SELECT 1) one
    LEFT JOIN LATERAL (SELECT * FROM public.vendor_inventory WHERE medicine_name ILIKE 'ibuprofen%'
                       ORDER BY (asli.fold(item_identifier) = asli.fold('ITEM000041')) DESC, vendor_id, inventory_id LIMIT 1) vi ON true
    UNION ALL
    SELECT coalesce(vi.vendor_id, 3), vi.inventory_id, 2, DATE '2026-09-12', 'PHONE', 'CLOSED',
           'Amoxicillin 500mg capsules were sticky and stuck together inside the strip; two capsules had '
           || 'leaked powder. Shop replaced the strip.'
    FROM (SELECT 1) one
    LEFT JOIN LATERAL (SELECT * FROM public.vendor_inventory WHERE medicine_name ILIKE 'amoxicillin%'
                       ORDER BY (asli.fold(item_identifier) = asli.fold('ITEM000035')) DESC, inventory_id LIMIT 1) vi ON true
    UNION ALL
    SELECT 2, NULL, 3, DATE '2026-10-01', 'EMAIL', 'CLOSED',
           'Refund for an unopened pack of Vitamin C 500mg took two weeks. No quality issue with the medicine.'
    UNION ALL
    SELECT 4, NULL, 4, DATE '2026-10-15', 'COUNTER', 'CLOSED',
           'Shop was out of stock of Metformin 500mg for three days; pharmacist suggested another brand.'
) x
WHERE NOT EXISTS (SELECT 1 FROM public.customer_complaints);

-- an earlier install linked the story complaints to other records: re-point them
UPDATE public.customer_complaints c SET inventory_id = vi.inventory_id, vendor_id = vi.vendor_id
FROM (SELECT * FROM public.vendor_inventory WHERE medicine_name ILIKE 'ibuprofen%'
      ORDER BY (asli.fold(item_identifier) = asli.fold('ITEM000041')) DESC, vendor_id, inventory_id LIMIT 1) vi
WHERE c.complaint_text LIKE 'Ibuprofen 400mg strip looks different%'
   OR c.complaint_text LIKE 'Bought Ibuprofen 400mg here last week%';
UPDATE public.customer_complaints c SET inventory_id = vi.inventory_id, vendor_id = vi.vendor_id
FROM (SELECT * FROM public.vendor_inventory WHERE medicine_name ILIKE 'amoxicillin%'
      ORDER BY (asli.fold(item_identifier) = asli.fold('ITEM000035')) DESC, inventory_id LIMIT 1) vi
WHERE c.complaint_text LIKE 'Amoxicillin 500mg capsules were sticky%';

-- ---------------------------------------------------------------------
-- Context-discovery config for this source
-- ---------------------------------------------------------------------
INSERT INTO asli_ctx.entry_points (seed_kind, table_name, column_name, match, weight) VALUES
    ('item_code',      'vendor_inventory',    'item_identifier', 'fold',  1.0),
    ('item_code',      'medicine_sales',      'item_identifier', 'fold',  0.9),
    ('vendor_name',    'vendors',             'vendor_name',     'name',  0.9),
    ('distributor_id', 'purchase_invoices',   'distributor_id',  'exact', 0.4),
    ('medicine_name',  'vendor_inventory',    'medicine_name',   'prefix', 0.5),
    ('text',           'vendors',             'vendor_name',     'name',  0.6),
    ('text',           'vendors',             'address',         'name',  0.4),
    ('text',           'customer_complaints', 'complaint_text',  'text',  0.7)
ON CONFLICT (seed_kind, table_name, column_name) DO UPDATE SET match = EXCLUDED.match, weight = EXCLUDED.weight;

INSERT INTO asli_ctx.table_roles (table_name, role, weight, label) VALUES
    ('vendors',             'hub',    0.8, 'Shop'),
    ('vendor_inventory',    'entity', 1.0, 'Shop stock record'),
    ('medicine_sales',      'entity', 1.0, 'Sale'),
    ('customers',           'entity', 0.7, 'Customer'),
    ('sale_customers',      'link',   1.0, 'Sale ↔ customer'),
    ('purchase_invoices',   'entity', 0.9, 'Purchase bill'),
    ('invoice_lines',       'link',   1.0, 'Bill ↔ stock record'),
    ('customer_complaints', 'detail', 1.3, 'Customer complaint')
ON CONFLICT (table_name) DO UPDATE SET role = EXCLUDED.role, weight = EXCLUDED.weight, label = EXCLUDED.label;

-- personal data never leaves this database as it is
INSERT INTO asli_ctx.private_columns VALUES
    ('customers', 'full_name',    'mask'),
    ('customers', 'phone_masked', 'drop'),
    ('customers', 'customer_ref', 'drop'),
    ('medicine_sales', 'customer_reference', 'drop'),
    ('vendors',   'contact_number', 'drop')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- Check
-- ---------------------------------------------------------------------
SELECT table_name, role, fk_links,
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM public.%I', table_name), false, true, '')))[1]::text::int AS row_count
FROM asli_ctx.v_schema ORDER BY fk_links DESC, table_name;
