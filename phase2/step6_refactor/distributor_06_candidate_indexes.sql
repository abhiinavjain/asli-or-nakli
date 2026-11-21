-- =====================================================================
-- Asli-or-Nakli · Phase 2 refactor · RUN ON: distributor_db  (DBeaver: Alt+X)
-- Lets this database find its own candidate records. Adds the asli_match
-- extension (functions only) and expression indexes. NO table, column or
-- constraint is changed. Copy the extension files first (see INSTALL.md).
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS asli_match;

CREATE INDEX IF NOT EXISTS asli_ii_code_keys ON public.inventory_items USING gin (asli.keys(product_code));
CREATE INDEX IF NOT EXISTS asli_ii_code_fold ON public.inventory_items (asli.fold(product_code));
CREATE INDEX IF NOT EXISTS asli_ii_name_month ON public.inventory_items (asli.name_key(drug_name), asli.month_key(exp_date));
ANALYZE public.inventory_items;

SELECT indexname FROM pg_indexes WHERE indexname LIKE 'asli_%' ORDER BY 1;
-- Expect 3 rows: asli_ii_code_fold, asli_ii_code_keys, asli_ii_name_month
