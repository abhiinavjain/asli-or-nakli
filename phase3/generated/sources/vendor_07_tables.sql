-- =====================================================================
-- Asli-or-Nakli · Phase 3 · vendor_db: new tables (FK -> PK) + data
-- RUN ON: vendor_db, after asli_ctx_core.sql.  Alt+X.  Safe to re-run.
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
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.customers (
    customer_id   serial PRIMARY KEY,
    customer_ref  varchar(100) NOT NULL UNIQUE,   -- = medicine_sales.customer_reference
    full_name     varchar(120) NOT NULL,
    phone_masked  varchar(20),
    area          varchar(80)
);

CREATE TABLE IF NOT EXISTS public.sale_customers (
    sale_id     int PRIMARY KEY REFERENCES public.medicine_sales (sale_id) ON DELETE CASCADE,
    customer_id int NOT NULL REFERENCES public.customers (customer_id)
);

CREATE TABLE IF NOT EXISTS public.purchase_invoices (
    invoice_id     serial PRIMARY KEY,
    invoice_no     varchar(30) NOT NULL UNIQUE,
    vendor_id      int  NOT NULL REFERENCES public.vendors (vendor_id),
    distributor_id int  NOT NULL,                 -- = distributor_db.distributors.distributor_id
    invoice_date   date NOT NULL,
    total_amount   numeric(10, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.invoice_lines (
    line_id      serial PRIMARY KEY,
    invoice_id   int NOT NULL REFERENCES public.purchase_invoices (invoice_id) ON DELETE CASCADE,
    inventory_id int NOT NULL UNIQUE REFERENCES public.vendor_inventory (inventory_id) ON DELETE CASCADE,
    unit_price   numeric(8, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_complaints (
    complaint_id   serial PRIMARY KEY,
    vendor_id      int  NOT NULL REFERENCES public.vendors (vendor_id),
    inventory_id   int  REFERENCES public.vendor_inventory (inventory_id) ON DELETE SET NULL,
    customer_id    int  REFERENCES public.customers (customer_id),
    reported_on    date NOT NULL,
    channel        varchar(20) NOT NULL CHECK (channel IN ('COUNTER', 'PHONE', 'WHATSAPP', 'EMAIL')),
    complaint_text text NOT NULL,
    status         varchar(20) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'FORWARDED', 'CLOSED'))
);

CREATE INDEX IF NOT EXISTS invoices_vendor_idx   ON public.purchase_invoices (vendor_id);
CREATE INDEX IF NOT EXISTS invoices_dist_idx     ON public.purchase_invoices (distributor_id);
CREATE INDEX IF NOT EXISTS inv_lines_invoice_idx ON public.invoice_lines (invoice_id);
CREATE INDEX IF NOT EXISTS sale_cust_idx         ON public.sale_customers (customer_id);
CREATE INDEX IF NOT EXISTS complaints_vendor_idx ON public.customer_complaints (vendor_id);
CREATE INDEX IF NOT EXISTS complaints_inv_idx    ON public.customer_complaints (inventory_id);
CREATE INDEX IF NOT EXISTS complaints_text_fts ON public.customer_complaints
    USING gin (to_tsvector('english', complaint_text));

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

INSERT INTO public.sale_customers (sale_id, customer_id)
SELECT s.sale_id, c.customer_id
FROM public.medicine_sales s JOIN public.customers c ON c.customer_ref = s.customer_reference
ON CONFLICT (sale_id) DO NOTHING;

-- one purchase bill per shop, distributor and receiving day
INSERT INTO public.purchase_invoices (invoice_no, vendor_id, distributor_id, invoice_date, total_amount)
SELECT 'INV-' || lpad(g.vendor_id::text, 2, '0') || '-' || lpad(g.distributor_id::text, 2, '0') || '-'
         || to_char(g.received_date, 'YYMMDD'),
       g.vendor_id, g.distributor_id, g.received_date, 180.00 * g.n
FROM (SELECT vendor_id, distributor_id, received_date, count(*) AS n
      FROM public.vendor_inventory GROUP BY 1, 2, 3) g
ON CONFLICT (invoice_no) DO NOTHING;

INSERT INTO public.invoice_lines (invoice_id, inventory_id, unit_price)
SELECT pi.invoice_id, vi.inventory_id, 180.00
FROM public.vendor_inventory vi
JOIN public.purchase_invoices pi ON pi.vendor_id = vi.vendor_id AND pi.distributor_id = vi.distributor_id
                                AND pi.invoice_date = vi.received_date
ON CONFLICT (inventory_id) DO NOTHING;

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
                       ORDER BY vendor_id, inventory_id LIMIT 1) vi ON true
    UNION ALL
    SELECT coalesce(vi.vendor_id, 1), vi.inventory_id, 1, DATE '2026-11-06', 'WHATSAPP', 'OPEN',
           'Bought Ibuprofen 400mg here last week. Box batch number is printed with a sticker over another '
           || 'number, and the expiry date looks altered. Stomach pain after taking it.'
    FROM (SELECT 1) one
    LEFT JOIN LATERAL (SELECT * FROM public.vendor_inventory WHERE medicine_name ILIKE 'ibuprofen%'
                       ORDER BY vendor_id DESC, inventory_id LIMIT 1) vi ON true
    UNION ALL
    SELECT coalesce(vi.vendor_id, 3), vi.inventory_id, 2, DATE '2026-09-12', 'PHONE', 'CLOSED',
           'Amoxicillin 500mg capsules were sticky and stuck together inside the strip; two capsules had '
           || 'leaked powder. Shop replaced the strip.'
    FROM (SELECT 1) one
    LEFT JOIN LATERAL (SELECT * FROM public.vendor_inventory WHERE medicine_name ILIKE 'amoxicillin%'
                       ORDER BY inventory_id OFFSET 2 LIMIT 1) vi ON true
    UNION ALL
    SELECT 2, NULL, 3, DATE '2026-10-01', 'EMAIL', 'CLOSED',
           'Refund for an unopened pack of Vitamin C 500mg took two weeks. No quality issue with the medicine.'
    UNION ALL
    SELECT 4, NULL, 4, DATE '2026-10-15', 'COUNTER', 'CLOSED',
           'Shop was out of stock of Metformin 500mg for three days; pharmacist suggested another brand.'
) x
WHERE NOT EXISTS (SELECT 1 FROM public.customer_complaints);

-- ---------------------------------------------------------------------
-- Context-discovery config for this source
-- ---------------------------------------------------------------------
INSERT INTO asli_ctx.entry_points (seed_kind, table_name, column_name, match, weight) VALUES
    ('item_code',      'vendor_inventory',    'item_identifier', 'fold',  1.0),
    ('item_code',      'medicine_sales',      'item_identifier', 'fold',  0.9),
    ('vendor_name',    'vendors',             'vendor_name',     'name',  0.9),
    ('distributor_id', 'purchase_invoices',   'distributor_id',  'exact', 0.4),
    ('medicine_name',  'vendor_inventory',    'medicine_name',   'name',  0.5),
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

-- ---------------------------------------------------------------------
-- Check
-- ---------------------------------------------------------------------
SELECT table_name, role, fk_links,
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM public.%I', table_name), false, true, '')))[1]::text::int AS row_count
FROM asli_ctx.v_schema ORDER BY fk_links DESC, table_name;
