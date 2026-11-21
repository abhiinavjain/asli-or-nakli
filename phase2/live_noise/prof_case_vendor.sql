-- =====================================================================
-- Asli-or-Nakli · professor's case, part 2 of 2 · RUN ON: vendor_db
-- Same noisy code as the distributor: ITEM00008S for ITEM000085
-- (Diclofenac 50mg), at LifeCare Medical Store, supplied by distributor 2.
-- =====================================================================
INSERT INTO public.vendor_inventory (vendor_id, distributor_id, item_identifier, received_date, medicine_name, company, mfg, expiry)
VALUES (4, 2, 'ITEM00008S', DATE '2026-01-25', 'Diclofenac 50mg', 'MediCare Laboratories', '12/2025', '12/2027')
ON CONFLICT (item_identifier) DO NOTHING;

SELECT inventory_id, vendor_id, distributor_id, item_identifier, medicine_name, mfg, expiry
FROM public.vendor_inventory WHERE item_identifier = 'ITEM00008S';

-- UNDO:  DELETE FROM public.vendor_inventory WHERE item_identifier IN ('ITEM00008S', 'ITEM000085') AND vendor_id = 4 AND received_date = DATE '2026-01-25';
