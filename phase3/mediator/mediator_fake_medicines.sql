-- =====================================================================
-- Asli-or-Nakli · list of FAKE medicines in the supply chain
-- RUN ON: mediator_db (reads the 3 sources through the foreign tables). Read-only.
-- =====================================================================
-- A pack is FAKE when one of these holds:
--   COUNTERFEIT CODE  a shop or distributor stocks a code that no manufacturer made
--                     (compared with asli.fold, so ITEM0O0041 = ITEM000041 is NOT fake)
--   CLONED CODE       the code is real, but the shop / distributor record says a
--                     different medicine than the manufacturer's record of that code
--   UNAPPROVED/NAKALI the manufacturer made the code but never approved it (Phase 1 rule)
-- Expired items and failed QC batches are NOT fake (genuine but unsafe); see the
-- second query.
-- =====================================================================

WITH made AS (            -- every code the manufacturer made, in folded form
    SELECT asli.fold(mi.unique_item_code) AS fcode, mi.unique_item_code AS item_code,
           m.medicine_name, mf.manufacturer_name, mi.expiry_date
    FROM manufactured_items mi
    JOIN medicines m      ON m.medicine_code = mi.medicine_code
    JOIN manufacturers mf ON mf.manufacturer_id = m.manufacturer_id
),
held AS (                 -- every pack held downstream (shop stock + distributor stock)
    SELECT 'vendor' AS held_by, v.vendor_name AS holder, vi.item_identifier AS code,
           vi.medicine_name AS name_on_pack, vi.company AS company_on_pack
    FROM vendor_inventory vi JOIN vendors v USING (vendor_id)
    UNION ALL
    SELECT 'distributor', d.distributor_name, ii.product_code, ii.drug_name, ii.mfr_name
    FROM inventory_items ii JOIN distributors d USING (distributor_id)
)
-- 1. counterfeit code: no manufacturer ever made it
SELECT 'COUNTERFEIT CODE' AS fake_type, h.code AS item_code, h.name_on_pack AS medicine,
       h.company_on_pack AS company, h.held_by, h.holder,
       'no manufacturer made this code' AS reason
FROM held h
WHERE NOT EXISTS (SELECT 1 FROM made m WHERE m.fcode = asli.fold(h.code))

UNION ALL
-- 2. cloned code: real code, but printed on a pack of another medicine
SELECT 'CLONED CODE', h.code, h.name_on_pack, h.company_on_pack, h.held_by, h.holder,
       'code belongs to ' || m.medicine_name || ' (' || m.manufacturer_name || ')'
FROM held h
JOIN made m ON m.fcode = asli.fold(h.code)
WHERE h.name_on_pack IS NOT NULL
  AND asli.name_key(h.name_on_pack) <> asli.name_key(m.medicine_name)   -- spelling noise ignored

UNION ALL
-- 3. unapproved / nakali: made, but never approved by the manufacturer
SELECT 'UNAPPROVED / NAKALI', m.item_code, m.medicine_name, m.manufacturer_name,
       coalesce(string_agg(DISTINCT h.held_by, ', '), 'not in stock'),
       string_agg(DISTINCT h.holder, ', '),
       'not in approved_items'
FROM made m
LEFT JOIN held h ON asli.fold(h.code) = m.fcode
WHERE NOT EXISTS (SELECT 1 FROM approved_items a WHERE asli.fold(a.item_code) = m.fcode)
GROUP BY m.item_code, m.medicine_name, m.manufacturer_name

ORDER BY fake_type, medicine, item_code;


-- ---------------------------------------------------------------------
-- Summary: how many fake packs per medicine
-- ---------------------------------------------------------------------
-- (the same query, grouped: one row per medicine and kind of fake)

SELECT medicine, company, fake_type, count(*) AS fake_packs
FROM (
WITH made AS (            -- every code the manufacturer made, in folded form
    SELECT asli.fold(mi.unique_item_code) AS fcode, mi.unique_item_code AS item_code,
           m.medicine_name, mf.manufacturer_name, mi.expiry_date
    FROM manufactured_items mi
    JOIN medicines m      ON m.medicine_code = mi.medicine_code
    JOIN manufacturers mf ON mf.manufacturer_id = m.manufacturer_id
),
held AS (                 -- every pack held downstream (shop stock + distributor stock)
    SELECT 'vendor' AS held_by, v.vendor_name AS holder, vi.item_identifier AS code,
           vi.medicine_name AS name_on_pack, vi.company AS company_on_pack
    FROM vendor_inventory vi JOIN vendors v USING (vendor_id)
    UNION ALL
    SELECT 'distributor', d.distributor_name, ii.product_code, ii.drug_name, ii.mfr_name
    FROM inventory_items ii JOIN distributors d USING (distributor_id)
)
-- 1. counterfeit code: no manufacturer ever made it
SELECT 'COUNTERFEIT CODE' AS fake_type, h.code AS item_code, h.name_on_pack AS medicine,
       h.company_on_pack AS company, h.held_by, h.holder,
       'no manufacturer made this code' AS reason
FROM held h
WHERE NOT EXISTS (SELECT 1 FROM made m WHERE m.fcode = asli.fold(h.code))

UNION ALL
-- 2. cloned code: real code, but printed on a pack of another medicine
SELECT 'CLONED CODE', h.code, h.name_on_pack, h.company_on_pack, h.held_by, h.holder,
       'code belongs to ' || m.medicine_name || ' (' || m.manufacturer_name || ')'
FROM held h
JOIN made m ON m.fcode = asli.fold(h.code)
WHERE h.name_on_pack IS NOT NULL
  AND asli.name_key(h.name_on_pack) <> asli.name_key(m.medicine_name)   -- spelling noise ignored

UNION ALL
-- 3. unapproved / nakali: made, but never approved by the manufacturer
SELECT 'UNAPPROVED / NAKALI', m.item_code, m.medicine_name, m.manufacturer_name,
       coalesce(string_agg(DISTINCT h.held_by, ', '), 'not in stock'),
       string_agg(DISTINCT h.holder, ', '),
       'not in approved_items'
FROM made m
LEFT JOIN held h ON asli.fold(h.code) = m.fcode
WHERE NOT EXISTS (SELECT 1 FROM approved_items a WHERE asli.fold(a.item_code) = m.fcode)
GROUP BY m.item_code, m.medicine_name, m.manufacturer_name


) f
GROUP BY medicine, company, fake_type
ORDER BY fake_packs DESC, medicine;


-- ---------------------------------------------------------------------
-- (optional) genuine but UNSAFE: expired items and items from a batch that failed QC
-- (the batch part reads the Phase 3 tables at the manufacturer through dblink)
-- ---------------------------------------------------------------------
SELECT 'EXPIRED' AS problem, item_code, medicine_name, manufacturer_name,
       'expired on ' || expiry_date AS reason
FROM global_medicine_history
WHERE expiry_date < CURRENT_DATE
UNION ALL
SELECT 'FAILED QC BATCH', t.item_code, t.medicine_name, t.manufacturer_name,
       'batch ' || t.batch_no || ' failed ' || t.tests
FROM dblink('manufacturer_server', $q$
    SELECT mi.unique_item_code, m.medicine_name, mf.manufacturer_name, pb.batch_no,
           string_agg(DISTINCT q.test_name, ', ')
    FROM manufactured_items mi
    JOIN medicines m          ON m.medicine_code = mi.medicine_code
    JOIN manufacturers mf     ON mf.manufacturer_id = m.manufacturer_id
    JOIN batch_items bi       ON bi.item_id = mi.item_id
    JOIN production_batches pb ON pb.batch_id = bi.batch_id
    JOIN qc_reports q         ON q.batch_id = pb.batch_id AND q.result = 'FAIL'
    GROUP BY 1, 2, 3, 4 $q$)
     AS t(item_code text, medicine_name text, manufacturer_name text, batch_no text, tests text)
ORDER BY problem, medicine_name, item_code;
