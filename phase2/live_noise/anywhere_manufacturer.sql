-- =====================================================================
-- Asli-or-Nakli · rehearsal: noise in OTHER columns · RUN ON: manuf_db
-- Load data v2 first. Each line is one noisy edit; the comment says what the
-- cleansing scan should propose. Do not combine with anywhere_* on a live demo
-- unless you want to rehearse everything at once.
-- =====================================================================
-- 1. item recorded as the wrong medicine (distributor + vendor both say Monocap)
--    expect: UPDATE manufactured_items.medicine_code MED003 to MED002
UPDATE public.manufactured_items SET medicine_code = 'MED003' WHERE unique_item_code = 'ITEM000015';
-- 2. same, but only the distributor also holds it (1 to 1)
--    expect: REVIEW, suggested "Manufacturer is wrong: ITEM000068 is Pantoprazole 40mg (MED007)" (same batch dates)
UPDATE public.manufactured_items SET medicine_code = 'MED009' WHERE unique_item_code = 'ITEM000068';
-- 3. medicine linked to the wrong manufacturer
--    expect: UPDATE medicines.manufacturer_id 1 to 4 for Aspirin 75mg
UPDATE public.medicines SET manufacturer_id = 1 WHERE medicine_code = 'MED010';
-- 4. the same medicine entered again under a look-alike code, one item moved to it
--    expect: UPDATE ITEM000064 medicine_code MED0O7 to MED007, then DELETE medicine MED0O7
INSERT INTO public.medicines (medicine_code, medicine_name, composition, dosage_form, manufacturer_id)
SELECT 'MED0O7', medicine_name, composition, dosage_form, manufacturer_id FROM public.medicines WHERE medicine_code = 'MED007'
ON CONFLICT (medicine_code) DO NOTHING;
UPDATE public.manufactured_items SET medicine_code = 'MED0O7' WHERE unique_item_code = 'ITEM000064';
-- 5. expiry year typo
--    expect: UPDATE expiry 2082-01-05 to 2028-01-05
UPDATE public.manufactured_items SET expiry_date = DATE '2082-01-05' WHERE unique_item_code = 'ITEM000047';
-- NOT POSSIBLE (the database refuses, nothing to clean): a medicine_code that is not in
-- medicines (foreign key), expiry before mfg (check constraint), a duplicate item code (unique).
