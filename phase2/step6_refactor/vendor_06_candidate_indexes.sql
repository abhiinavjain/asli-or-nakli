-- =====================================================================
-- Asli-or-Nakli · Phase 2 refactor · RUN ON: vendor_db  (DBeaver: Alt+X)
-- Lets this database find its own candidate records. Adds the asli_match
-- extension (functions only) and expression indexes. NO table, column or
-- constraint is changed. Copy the extension files first (see INSTALL.md).
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS asli_match;

CREATE INDEX IF NOT EXISTS asli_vi_code_keys ON public.vendor_inventory USING gin (asli.keys(item_identifier));
CREATE INDEX IF NOT EXISTS asli_vi_code_fold ON public.vendor_inventory (asli.fold(item_identifier));
CREATE INDEX IF NOT EXISTS asli_vi_name_month ON public.vendor_inventory (asli.name_key(medicine_name), asli.month_key(expiry));
CREATE INDEX IF NOT EXISTS asli_ms_code_fold ON public.medicine_sales (asli.fold(item_identifier));
ANALYZE public.vendor_inventory;

SELECT indexname FROM pg_indexes WHERE indexname LIKE 'asli_%' ORDER BY 1;
-- Expect 4 rows: asli_ms_code_fold, asli_vi_code_fold, asli_vi_code_keys, asli_vi_name_month
