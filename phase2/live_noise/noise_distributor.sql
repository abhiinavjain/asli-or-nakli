-- =====================================================================
-- Asli-or-Nakli · one live noisy record · RUN ON: distributor_db
-- The distributor records receiving ITEM000067 (Pantoprazole 40mg), but the
-- code is keyed in wrongly: G instead of 6  ->  ITEM0000G7
-- (Before this, ITEM000067 had no distributor record at all.)
-- Expected: Data cleansing proposes ITEM0000G7 -> ITEM000067
--           (manufacturer + vendor both say ITEM000067).
-- =====================================================================
INSERT INTO public.inventory_items (distributor_id, product_code, received_date, drug_name, mfr_name, mfg_date, exp_date)
VALUES (2, 'ITEM0000G7', DATE '2026-02-20', 'PANTOPRAZOLE 40MG', 'MEDICARE LABORATORIES', DATE '2026-01-15', DATE '2028-01-15')
ON CONFLICT (product_code) DO NOTHING;

SELECT inventory_id, distributor_id, product_code, received_date, drug_name, mfr_name, mfg_date, exp_date
FROM public.inventory_items WHERE product_code = 'ITEM0000G7';

-- UNDO:  DELETE FROM public.inventory_items WHERE product_code IN ('ITEM0000G7', 'ITEM000067') AND drug_name = 'PANTOPRAZOLE 40MG' AND received_date = DATE '2026-02-20';
