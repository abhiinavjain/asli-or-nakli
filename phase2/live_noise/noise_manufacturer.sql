-- =====================================================================
-- Asli-or-Nakli · one live noisy record · RUN ON: manuf_db
-- The manufacturer records ITEM000017 (Monocap 500mg) a second time,
-- with the code misprinted: I instead of 1  ->  ITEM0000I7
-- Expected: Data cleansing proposes DELETE of this duplicate copy.
-- =====================================================================
INSERT INTO public.manufactured_items (medicine_code, unique_item_code, manufacturing_date, expiry_date)
VALUES ('MED002', 'ITEM0000I7', DATE '2025-12-21', DATE '2027-12-21')
ON CONFLICT (unique_item_code) DO NOTHING;

SELECT item_id, medicine_code, unique_item_code, manufacturing_date, expiry_date
FROM public.manufactured_items WHERE unique_item_code IN ('ITEM000017', 'ITEM0000I7') ORDER BY item_id;

-- UNDO:  DELETE FROM public.manufactured_items WHERE unique_item_code = 'ITEM0000I7';
