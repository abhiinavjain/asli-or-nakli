-- =====================================================================
-- Asli-or-Nakli · one live noisy record · RUN ON: vendor_db
-- Wellness Pharmacy stocks ITEM000055 (Omeprazole 20mg) but types it badly:
--   code      S instead of 5, twice      ->  ITEM0000SS
--   name      misspelt                   ->  Omeprazol 20mg
--   expiry    written as on the strip    ->  NOV-2027
-- (Before this, ITEM000055 was at the distributor but at no shop.)
-- Expected: Data cleansing proposes code -> ITEM000055,
--           name -> Omeprazole 20mg, expiry -> 11/2027.
-- =====================================================================
INSERT INTO public.vendor_inventory (vendor_id, distributor_id, item_identifier, received_date, medicine_name, company, mfg, expiry)
VALUES (3, 1, 'ITEM0000SS', DATE '2026-01-05', 'Omeprazol 20mg', 'Sunrise Pharmaceuticals', '11/2025', 'NOV-2027')
ON CONFLICT (item_identifier) DO NOTHING;

SELECT inventory_id, vendor_id, distributor_id, item_identifier, received_date, medicine_name, company, mfg, expiry
FROM public.vendor_inventory WHERE item_identifier = 'ITEM0000SS';

-- UNDO:  DELETE FROM public.vendor_inventory WHERE item_identifier IN ('ITEM0000SS', 'ITEM000055') AND vendor_id = 3 AND received_date = DATE '2026-01-05';
