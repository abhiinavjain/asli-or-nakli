-- Phase 2 step 1 (rebuilt): expose the sources' context columns to the mediator.
ALTER FOREIGN TABLE public.inventory_items
    ADD COLUMN IF NOT EXISTS drug_name varchar(150),
    ADD COLUMN IF NOT EXISTS mfr_name  varchar(150),
    ADD COLUMN IF NOT EXISTS mfg_date  date,
    ADD COLUMN IF NOT EXISTS exp_date  date;
ALTER FOREIGN TABLE public.vendor_inventory
    ADD COLUMN IF NOT EXISTS medicine_name varchar(150),
    ADD COLUMN IF NOT EXISTS company       varchar(150),
    ADD COLUMN IF NOT EXISTS mfg           varchar(20),
    ADD COLUMN IF NOT EXISTS expiry        varchar(20);
