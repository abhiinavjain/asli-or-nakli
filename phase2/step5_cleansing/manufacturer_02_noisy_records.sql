-- =====================================================================
-- Asli-or-Nakli · Phase 2 · Step 5
-- Noisy manufacturer records for the cleansing demo
-- RUN ON: manuf_db   (connect DBeaver / psql to manuf_db first)
-- Safe to run more than once: each change only applies to the original value.
-- Take a backup first:  pg_dump -U postgres -d manuf_db -f manufacturer_backup_before_noise.sql
-- =====================================================================
--
-- The manufacturer is no longer assumed to be correct. Each change below is
-- a realistic recording mistake. The true values are NOT stored anywhere in
-- the databases; the cleansing scan must work them out from the distributor
-- and vendor records (majority vote).
--
--  ID   What changes                         Original              Noisy
--  M01  item code (OCR O for 0, twice)       ITEM000002            ITEM0OO002
--  M02  item code (a zero dropped)           ITEM000005            ITEM00005
--  M03  medicine name (letters swapped)      Metformin 500mg       Metfromin 500mg
--  M04  manufacturer name (misspelt)         CureLife Pharma       CureLyfe Pharma
--  M05  expiry date (month 01 -> 10)         ITEM000004 2027-01-15  2027-10-15
--  M06  mfg date (month 09 -> 06)            ITEM000001 2025-09-15  2025-06-15
--  M07  same item recorded twice (l for 1)   ITEM000201            + ITEM00020l
--  M08  item code (S for 5), only the        ITEM000150            ITEM0001S0
--       distributor holds this item -> tie, must go to REVIEW
-- =====================================================================

BEGIN;

-- M01
UPDATE public.manufactured_items SET unique_item_code = 'ITEM0OO002'
WHERE unique_item_code = 'ITEM000002';

-- M02
UPDATE public.manufactured_items SET unique_item_code = 'ITEM00005'
WHERE unique_item_code = 'ITEM000005';

-- M03
UPDATE public.medicines SET medicine_name = 'Metfromin 500mg'
WHERE medicine_code = 'MED011' AND medicine_name = 'Metformin 500mg';

-- M04
UPDATE public.manufacturers SET manufacturer_name = 'CureLyfe Pharma'
WHERE manufacturer_id = 7 AND manufacturer_name = 'CureLife Pharma';

-- M05
UPDATE public.manufactured_items SET expiry_date = DATE '2027-10-15'
WHERE unique_item_code = 'ITEM000004' AND expiry_date = DATE '2027-01-15';

-- M06
UPDATE public.manufactured_items SET manufacturing_date = DATE '2025-06-15'
WHERE unique_item_code = 'ITEM000001' AND manufacturing_date = DATE '2025-09-15';

-- M07
INSERT INTO public.manufactured_items (medicine_code, unique_item_code, manufacturing_date, expiry_date)
VALUES ('MED021', 'ITEM00020l', DATE '2026-04-21', DATE '2028-06-21')
ON CONFLICT (unique_item_code) DO NOTHING;

-- M08
UPDATE public.manufactured_items SET unique_item_code = 'ITEM0001S0'
WHERE unique_item_code = 'ITEM000150';

COMMIT;

-- Check: expect 8 rows, every "now" column showing the noisy value
SELECT 'M01' AS id, unique_item_code AS now FROM public.manufactured_items WHERE item_id = 2
UNION ALL SELECT 'M02', unique_item_code FROM public.manufactured_items WHERE item_id = 5
UNION ALL SELECT 'M03', medicine_name FROM public.medicines WHERE medicine_code = 'MED011'
UNION ALL SELECT 'M04', manufacturer_name FROM public.manufacturers WHERE manufacturer_id = 7
UNION ALL SELECT 'M05', expiry_date::text FROM public.manufactured_items WHERE item_id = 4
UNION ALL SELECT 'M06', manufacturing_date::text FROM public.manufactured_items WHERE item_id = 1
UNION ALL SELECT 'M07', string_agg(unique_item_code, ', ') FROM public.manufactured_items WHERE unique_item_code IN ('ITEM000201', 'ITEM00020l')
UNION ALL SELECT 'M08', unique_item_code FROM public.manufactured_items WHERE item_id = 150;
