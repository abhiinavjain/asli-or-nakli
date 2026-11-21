-- =====================================================================
-- Asli-or-Nakli · rehearsal: noise in OTHER columns · RUN ON: vendor_db
-- =====================================================================
-- 1. sale recorded under a noisy code      expect: UPDATE medicine_sales ITEM00O162 to ITEM000162
UPDATE public.medicine_sales SET item_identifier = 'ITEM00O162' WHERE item_identifier = 'ITEM000162';
-- 2. received before the item was made     expect: REVIEW "correct it by hand" (no typing slip fits)
UPDATE public.vendor_inventory SET received_date = DATE '2025-03-13' WHERE item_identifier = 'ITEM000173';
-- 3. misspelt company                      expect: UPDATE company to WellCare Laboratories
UPDATE public.vendor_inventory SET company = 'WelCare Laboratoreis' WHERE item_identifier = 'ITEM000215';
-- 4. impossible month                      expect: UPDATE mfg 40/2026 to 04/2026
UPDATE public.vendor_inventory SET mfg = '40/2026' WHERE item_identifier = 'ITEM000239';
-- 5. expiry missing                        expect: UPDATE expiry NULL to 03/2028
UPDATE public.vendor_inventory SET expiry = NULL WHERE item_identifier = 'ITEM000252';
-- 6. noisy stock code, and the sale typed the same way
--    expect: UPDATE item_identifier ITEM00005B to ITEM000058 AND the sale to ITEM000058 (stays "Sold")
UPDATE public.vendor_inventory SET item_identifier = 'ITEM00005B' WHERE item_identifier = 'ITEM000058';
UPDATE public.medicine_sales SET item_identifier = 'ITEM00005B' WHERE item_identifier = 'ITEM000058';
