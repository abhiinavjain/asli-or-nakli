-- =====================================================================
-- Asli-or-Nakli · rehearsal: noise in OTHER columns · RUN ON: distributor_db
-- =====================================================================
-- 1. misspelt manufacturer name            expect: UPDATE mfr_name to SUNRISE PHARMACEUTICALS
UPDATE public.inventory_items SET mfr_name = 'SUNRISE PHARMACUETICALS' WHERE product_code = 'ITEM000057';
-- 2. received date in the future           expect: REVIEW, suggested 2026-01-21 (digits swapped)
UPDATE public.inventory_items SET received_date = DATE '2062-01-21' WHERE product_code = 'ITEM000113';
-- 3. medicine name missing                 expect: UPDATE drug_name NULL to CALCIUM 500MG
UPDATE public.inventory_items SET drug_name = NULL WHERE product_code = 'ITEM000131';
-- 4. misspelt shop in a supply record      expect: UPDATE vendor_reference to LifeCare Medical Store
UPDATE public.supplied_items SET vendor_reference = 'LifeCare Medcal Store' WHERE product_code = 'ITEM000148';
-- 5. mfg date with day and month swapped   expect: UPDATE mfg_date 2026-12-03 to 2026-03-21
UPDATE public.inventory_items SET mfg_date = DATE '2026-12-03' WHERE product_code = 'ITEM000283';
-- 6. new record with a noisy code AND a supply record pointing at it
--    expect: UPDATE product_code ITEM0000S6 to ITEM000056; the fix script moves the supply record along
INSERT INTO public.inventory_items (distributor_id, product_code, received_date, drug_name, mfr_name, mfg_date, exp_date)
VALUES (1, 'ITEM0000S6', DATE '2026-02-10', 'OMEPRAZOLE 20MG', 'SUNRISE PHARMACEUTICALS', DATE '2026-01-10', DATE '2028-01-10')
ON CONFLICT (product_code) DO NOTHING;
INSERT INTO public.supplied_items (product_code, vendor_reference, supply_date)
VALUES ('ITEM0000S6', 'MediTrust Pharmacy', DATE '2026-02-20')
ON CONFLICT (product_code) DO NOTHING;
