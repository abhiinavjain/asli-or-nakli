-- Phase 2 step 1 (rebuilt): context columns at the sources.
-- The original distributor_01 / vendor_01 scripts were not kept; this follows the
-- schema mapping in phase2/step1/README.md.
\if :{?is_distributor}
ALTER TABLE public.inventory_items
    ADD COLUMN IF NOT EXISTS drug_name varchar(150),   -- UPPER CASE medicine name
    ADD COLUMN IF NOT EXISTS mfr_name  varchar(150),   -- UPPER CASE manufacturer
    ADD COLUMN IF NOT EXISTS mfg_date  date,
    ADD COLUMN IF NOT EXISTS exp_date  date;
\else
ALTER TABLE public.vendor_inventory
    ADD COLUMN IF NOT EXISTS medicine_name varchar(150),
    ADD COLUMN IF NOT EXISTS company       varchar(150),
    ADD COLUMN IF NOT EXISTS mfg           varchar(20),  -- text, MM/YYYY
    ADD COLUMN IF NOT EXISTS expiry        varchar(20);  -- text, MM/YYYY
\endif
