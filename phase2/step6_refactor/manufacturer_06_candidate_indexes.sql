-- =====================================================================
-- Asli-or-Nakli · Phase 2 refactor · RUN ON: manuf_db  (DBeaver: Alt+X)
-- Lets this database find its own candidate items, so the mediator never has to
-- read the whole table. Adds the asli_match extension (functions only) and
-- expression indexes. NO table, column or constraint is changed.
-- Before running: copy asli_match.control and asli_match--1.0.sql into the
-- PostgreSQL share\extension folder (see INSTALL.md).
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS asli_match;

-- 1. code pass: codes one typing error away from the typed code
CREATE INDEX IF NOT EXISTS asli_mi_code_keys ON public.manufactured_items USING gin (asli.keys(unique_item_code));
-- 2. folded-code lookups (look-alike letters, missing zeros, case, separators)
CREATE INDEX IF NOT EXISTS asli_mi_code_fold ON public.manufactured_items (asli.fold(unique_item_code));
-- 3. context pass: medicine sound key + expiry month
CREATE INDEX IF NOT EXISTS asli_med_name_key ON public.medicines (asli.name_key(medicine_name));
CREATE INDEX IF NOT EXISTS asli_mi_med_month ON public.manufactured_items (medicine_code, asli.month_key(expiry_date));
ANALYZE public.manufactured_items;
ANALYZE public.medicines;

SELECT indexname FROM pg_indexes WHERE indexname LIKE 'asli_%' ORDER BY 1;
-- Expect 4 rows: asli_med_name_key, asli_mi_code_fold, asli_mi_code_keys, asli_mi_med_month
