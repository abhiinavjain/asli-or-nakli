-- =====================================================================
-- Asli-or-Nakli · professor's case, part 1 of 2 · RUN ON: distributor_db
-- The SAME noisy code is stored by the distributor AND the vendor, the
-- manufacturer only has the correct one.
--   ITEM000085 (Diclofenac 50mg, MediCare Laboratories) stored as ITEM00008S
-- Run prof_case_vendor.sql on vendor_db as well.
-- =====================================================================
INSERT INTO public.inventory_items (distributor_id, product_code, received_date, drug_name, mfr_name, mfg_date, exp_date)
VALUES (2, 'ITEM00008S', DATE '2026-01-10', 'DICLOFENAC 50MG', 'MEDICARE LABORATORIES', DATE '2025-12-11', DATE '2027-12-11')
ON CONFLICT (product_code) DO NOTHING;

SELECT inventory_id, distributor_id, product_code, drug_name, mfg_date, exp_date
FROM public.inventory_items WHERE product_code = 'ITEM00008S';

-- UNDO:  DELETE FROM public.inventory_items WHERE product_code IN ('ITEM00008S', 'ITEM000085') AND received_date = DATE '2026-01-10';
