-- =====================================================================
-- Asli-or-Nakli · OPTIONAL scale test · RUN ON: a NEW database scale_db
-- (create it first: CREATE DATABASE scale_db;  then connect to it and Alt+X)
-- One synthetic shop with 1,000,000 records, indexed like vendor_db.
-- Takes about 1-2 minutes. Needs the asli_match extension files installed.
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS asli_match;
DROP TABLE IF EXISTS public.vendor_inventory;
DROP TABLE IF EXISTS public.vendors;
CREATE TABLE public.vendors (vendor_id int PRIMARY KEY, vendor_name varchar(100));
INSERT INTO public.vendors VALUES (1, 'Scale Pharmacy');
CREATE TABLE public.vendor_inventory (
    inventory_id serial PRIMARY KEY, vendor_id int, distributor_id int,
    item_identifier varchar(50) UNIQUE, received_date date,
    medicine_name varchar(100), company varchar(100), mfg varchar(10), expiry varchar(10));
INSERT INTO public.vendor_inventory (vendor_id, distributor_id, item_identifier, received_date, medicine_name, company, mfg, expiry)
SELECT 1, 1 + g % 5, 'ITEM' || lpad(g::text, 7, '0'), DATE '2026-01-01' + (g % 300),
       (ARRAY['Paracetamol 500mg', 'Ibuprofen 400mg', 'Omeprazole 20mg', 'Cetirizine 10mg', 'Metformin 500mg'])[1 + g % 5],
       'Scale Labs', lpad((1 + g % 12)::text, 2, '0') || '/2026', lpad((1 + g % 12)::text, 2, '0') || '/2028'
FROM generate_series(1, 1000000) g;
CREATE INDEX asli_vi_code_keys ON public.vendor_inventory USING gin (asli.keys(item_identifier));
CREATE INDEX asli_vi_code_fold ON public.vendor_inventory (asli.fold(item_identifier));
CREATE INDEX asli_vi_name_month ON public.vendor_inventory (asli.name_key(medicine_name), asli.month_key(expiry));
ANALYZE public.vendor_inventory;
SELECT count(*) AS records FROM public.vendor_inventory;   -- expect 1000000
