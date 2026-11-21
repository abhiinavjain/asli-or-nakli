# Asli-or-Nakli · Phase 2 demo test cases (v3)

Every expected value was produced by running the case on a local copy (data v2 + the 22 Oct versions of step 3, step 5 and gui.py). The same cases, with PASS/FAIL columns, are in `Demo_test_cases_v3.xlsx`.

## 1 Setup

Run once, in this order, before anything else. Data v2 loaded (data_v2/01-04).

| ID | Where | Input / edit | What it tests | Expected | Notes |
|---|---|---|---|---|---|
| S01 | Mediator · DBeaver Alt+X | step2/mediator_02_matching_functions.sql | our own matching functions, no extensions | 18 checks PASS |  |
| S02 | Mediator · DBeaver Alt+X | step3/mediator_03_candidate_search.sql (updated 22 Oct) | candidate search, majority rule, verify_item | 6 checks PASS (rows 4-6 say SKIP once data is cleansed) |  |
| S03 | Mediator · DBeaver Alt+X | step5_cleansing/mediator_05_cleansing.sql (updated 22 Oct) | cleansing scan / fix scripts | 5 checks PASS |  |
| S04 | Each owner | SELECT count(*) on the main tables | data v2 is loaded | manufacturer 10 · 30 · 301 / distributor 5 · 275 · 234 / vendor 10 · 264 · 116 / mediator 275 approvals |  |
| S05 | GUI machine | streamlit run gui.py (new gui.py) | GUI starts | 7 tabs: Verify, Find records, Data health, Data cleansing, Reports, Analysis, Matching settings |  |

## 2 Phase 1

🔍 Verify medicine: type the code only. Result line = banner at the top of 'Verification Result'.

| ID | Where | Input / edit | What it tests | Expected | Notes |
|---|---|---|---|---|---|
| P01 | 🔍 Verify | ITEM000003 | genuine, sold | EXACT MATCH · ✅ GENUINE MEDICINE · history table: ✓ Sold · no report |  |
| P02 | 🔍 Verify | ITEM000010 | genuine, still in stock | EXACT MATCH · ✅ GENUINE · Not Sold |  |
| P03 | 🔍 Verify | ITEM000062 | not approved by the mediator | 🚨 NAKALI / UNAPPROVED · 📢 Automatically reported |  |
| P04 | 🔍 Verify | ITEM000054 | unapproved and sold | 🚨 NAKALI / UNAPPROVED · ✓ Sold · reported |  |
| P05 | 🔍 Verify | ITEM000021 | expired | ⚠️ SUSPICIOUS · Expiry Status: EXPIRED · reported |  |
| P06 | 🔍 Verify | ITEM000025 | expired and sold | ⚠️ SUSPICIOUS · EXPIRED · ✓ Sold |  |
| P07 | 🔍 Verify | ITEM000046 | at a shop, no distributor record | ⚠️ SUSPICIOUS · DISTRIBUTOR RECORD NOT FOUND · reported |  |
| P08 | 🔍 Verify | ITEM000009 | made, never shipped | ⚠️ SUSPICIOUS · DISTRIBUTOR RECORD NOT FOUND |  |
| P09 | 🔍 Verify | ITEM000008 | at the distributor, not at a shop yet | ⚠️ SUSPICIOUS · VENDOR RECORD NOT FOUND |  |
| P10 | 🔍 Verify | ITEM000030 | shop names a different distributor | ⚠️ SUSPICIOUS · 🚨 DISTRIBUTOR ID MISMATCH — Distributor says ID 1 but Vendor says ID 2 |  |
| P11 | 🔍 Verify | ITEM000078 | expired + unapproved | 🚨 NAKALI / UNAPPROVED (first rule wins) |  |
| P12 | 🔍 Verify | ITEM000024 | expired + no distributor record | ⚠️ SUSPICIOUS · EXPIRED (first rule wins) |  |
| P13 | 🔍 Verify | ITEM000072 | unapproved + distributor mismatch | 🚨 NAKALI / UNAPPROVED + red mismatch line |  |
| P14 | 🔍 Verify | ITEM583920 | counterfeit code at a shop | ❌ NO MATCH · button 'Report as suspected fake' → 'Reported to Ministry' |  |
| P15 | 📈 Analysis | open the tab (before cleansing) | Phase 1 counts over the global view | GENUINE 164 · DIST NOT FOUND 28 · VENDOR NOT FOUND 46 · ID MISMATCH 13 · EXPIRED 21 · UNAPPROVED 29 |  |
| P16 | 📢 Reports | open the tab | auto reports | one row per suspicious item verified above (P03-P13) |  |
| P17 | Other codes per case | see TEST_CASES.md | more items of each case | e.g. genuine sold ITEM000006/7/13 · unapproved ITEM000071/144 · expired ITEM000022/79 · no distributor ITEM000056/73 · not at shop ITEM000012/14 · mismatch ITEM000048/51 |  |

## 3 Matching

Rubric 1. Fill the pack fields exactly as given (blank = leave empty). 'Expected' = on the noisy data (before sheet 4); the Notes column says what changes once the data is cleansed. Codes are in a fixed-width font: O (letter) vs 0 (zero) matters.

| ID | Where | Input / edit | What it tests | Expected | Notes |
|---|---|---|---|---|---|
| M01 | 🔍 Verify | ITEM0O0041 · Ibuprofen 400mg · exp 11/2027 | O typed for 0 | MATCH → ITEM000041 · 🔁 'the vendor holds it as ITEM0O0041' · ✅ GENUINE | ITEM0O0041: character 6 is the letter O ; After cleansing: same verdict; GENUINE, no 'holds it as' note |
| M02 | 🔍 Verify | 1TEM000098 · Aspirin 75mg · 01/2028 | 1 for I | MATCH → ITEM000098 · vendor holds it as 1TEM000098 · ✅ GENUINE | 1TEM000098: starts with the digit 1 ; After cleansing: same, no note |
| M03 | 🔍 Verify | item-000202 · Naproxen 250mg · 02/2028 | lowercase, dash | 'Code after clean-up: ITEM000202' · MATCH → ITEM000202 · vendor holds it as item-000202 · ✅ GENUINE | After cleansing: same, no note |
| M04 | 🔍 Verify | ITEM214 · Glimepiride 2mg · 02/2028 | zeros missing | MATCH → ITEM000214 · ✅ GENUINE | After cleansing: same, no note |
| M05 | 🔍 Verify | lTEM0OO183 · Doxycycline 100mg · 01/2028 | three look-alike errors | MATCH → ITEM000183 · ✅ GENUINE | lTEM0OO183: starts with a lowercase L, character 6 is the letter O, character 7 is the letter O ; After cleansing: same, no note |
| M06 | 🔍 Verify | ITEM000910 (nothing else) | swapped digits, no context | REVIEW · 'Please choose' · nothing verified or reported until you pick ITEM000190 | After cleansing: same (REVIEW) |
| M07 | 🔍 Verify | ITEM000910 · Doxycycline 100mg · 03/2028 | same code + context | MATCH → ITEM000190 · ✅ GENUINE | After cleansing: same, no note |
| M08 | 🔍 Verify | ITEM000193 · Calcium 500mg · LifeWell Laboratories · 02/2028 | typo lands on another real code | WRONG CODE · 'Did you mean ITEM000139' · ✅ GENUINE (ITEM000139) | After cleansing: same (WRONG CODE → ITEM000139), no note |
| M09 | 🔍 Verify | ITEM000002 · Paracetamol 500mg · 11/2027 | manufacturer's own copy is noisy (ITEM0OO002) | NOISY MANUFACTURER RECORD → ITEM0OO002 · 'Not reported: the suspicion comes from a noisy manufacturer record' | After cleansing: EXACT MATCH · ✅ GENUINE (manufacturer fixed) |
| M10 | 🔍 Verify | ITEM000106 · Amoxicillin 500mg · Sunrise Pharmaceuticals · 12/2029 | real code on the wrong medicine | POSSIBLE CLONED CODE · 'Pack vs manufacturer's record' table · 📢 Automatically reported | After cleansing: same |
| M11 | 🔍 Verify | ITEM000153 · Montelukast 10mg · 01/2029 | right item, pack expiry off by a year | CONTEXT ERROR · comparison table · reported | After cleansing: same |
| M12 | 🔍 Verify | ZZZ-998877 | garbage | ❌ NO MATCH · 'very likely fake' · Report button works | After cleansing: same |
| M13 | 🔍 Verify | ITEM0O0041 → open '🔤 How the typed code matches' | explain the algorithm | edit steps: O→0 look-alike, cost 0.25 (our weighted Damerau-Levenshtein) | ITEM0O0041: character 6 is the letter O ; After cleansing: same |
| F01 | 🔁 Find records | ITEM000106 | reverse direction | Exact records=2 · Noisy records=1: vendor ITEM000l06 (NOISY VARIANT) | After cleansing: Exact records=2 · Noisy records=0 (vendor copy fixed) |
| F02 | 🔁 Find records | item000139 (lowercase) | reverse + clean-up | distributor ITEM000139 (EXACT) · vendor ITEM000193 (NOISY VARIANT) | After cleansing: distributor + vendor ITEM000139 (EXACT) |
| F03 | 🔁 Find records | ITEM000287 | distributor noise | vendor ITEM000287 (EXACT) · distributor ITEM0002B7 (NOISY VARIANT) | After cleansing: distributor + vendor ITEM000287 (EXACT) |
| F04 | 🔁 Find records | ITEM000171 | ambiguous record | distributor ITEM000171 (EXACT) · vendor ITEM00017 (POSSIBLE) | After cleansing: distributor + vendor ITEM000171 (EXACT) |
| F05 | 🔁 Find records | ITEM000255 | duplicate at distributor | distributor + vendor ITEM000255 (EXACT) · distributor ITEM0002S5 (NOISY VARIANT) | After cleansing: distributor + vendor ITEM000255 (EXACT), duplicate deleted |
| F06 | 🔁 Find records | ITEM0O0041 | a noisy code is not an item code | '❌ ITEM0O0041 is not an item code in the manufacturer's records' + 'Closest real item codes' (ITEM000041 first). Typing ITEM000041 with zeros is a real item and lists its records instead | ITEM0O0041: character 6 is the letter O ; After cleansing: same |
| H01 | 🩺 Data health | open the tab | stored records vs manufacturer | 40 record(s) need attention: distributor 10 UNKNOWN CODE + 2 CONTEXT CONFLICT · vendor 23 UNKNOWN CODE + 5 CONTEXT CONFLICT | After cleansing: 6 record(s) need attention: the 6 reported counterfeit codes (vendor UNKNOWN CODE) |
| H02 | 🩺 Data health | Explain 'VENDOR #… · ITEM00017' | record → item | → REVIEW → needs a person to decide | After cleansing: record no longer in the list (fixed to ITEM000171) |
| H03 | 🩺 Data health | Explain 'DISTRIBUTOR #… · ITEM0002B7' | record → item | → MATCH → belongs to ITEM000287 | ITEM0002B7: character 9 is the letter B ; After cleansing: record no longer in the list (fixed to ITEM000287) |
| T01 | ⚙️ Matching settings | match_threshold 0.85 → 0.99, then M01 again | settings are live | M01 becomes REVIEW · set back to 0.85 → MATCH again | After cleansing: same |

## 4 Cleansing

Rubric 2 on plain data v2, in order. Each owner runs their own fix script in DBeaver (Alt+X).

| ID | Where | Input / edit | What it tests | Expected | Notes |
|---|---|---|---|---|---|
| C01 | 🧹 Data cleansing | RUN CLEANSING SCAN | first scan | Fixes to run=40 (3 deletions) · Need a decision=7 · download buttons for manuf_db, distributor_db, vendor_db |  |
| C02 | 🧹 Data cleansing | review 'ITEM00017' → pick ITEM000171 · Rabeprazole 20mg → APPLY CHOICE | 1-to-1 decision | 'Choice applied' |  |
| C03 | 🧹 Data cleansing | 6 counterfeit reviews (ITEM583920 …) → ⭐ Report as counterfeit | counterfeits kept as evidence | 'Choice applied' · 📢 Reports tab: 6 × COUNTERFEIT CODE IN STOCK |  |
| C04 | Owners | download + run fix_<db>_scan1.sql on own DB | mediator never writes to other DBs | each script runs without error |  |
| C05 | 🧹 Data cleansing | CHECK APPLIED FIXES | fixes verified on live data | 41 fix(es) found · Applied=41 · log lists every change old → new |  |
| C06 | 🧹 Data cleansing | RUN CLEANSING SCAN again | nothing left | No anomalies · Need a decision=0 |  |
| C07 | Owners | run the same scripts a second time | idempotent | nothing changes (every UPDATE checks the old value) |  |
| C08 | 🩺 Data health | open the tab | after cleansing | only 6 vendor UNKNOWN CODE left = the reported counterfeits |  |
| C09 | 📈 Analysis | 🔄 REFRESH | Phase 1 after cleansing | GENUINE 187 (was 164) · DIST NOT FOUND 22 · VENDOR NOT FOUND 33 · MISMATCH 12 · EXPIRED 21 · UNAPPROVED 25 = clean answer key |  |
| C10 | 🔍 Verify | ITEM000002 · Paracetamol 500mg | manufacturer noise fixed | EXACT MATCH · ✅ GENUINE |  |
| C11 | 🔍 Verify | ITEM0O0041 · Ibuprofen 400mg · 11/2027 | noisy input still works | MATCH → ITEM000041 · ✅ GENUINE (no noisy-record note any more) | ITEM0O0041: character 6 is the letter O |
| C12 | 🧹 log | point at these lines | kinds of fixes | M01 ITEM0OO002→ITEM000002 · M07 delete ITEM00020l · M08 ITEM0001S0→ITEM000150 (letters among digits never win) · D06 ITEM0002B7→ITEM000287 + swapped dates · V17 duplicate deleted · V18 expiry · date formats MAR-2028 → 03/2028 |  |

## 5 Live edits

What the professor may insert / delete / modify. Load data v2 first; each row is independent unless it says otherwise. 'Scan' = the NEW proposal on top of the usual 40 fixes + 7 decisions.

| ID | Run on | Input / edit | Verify / Find shows | Scan proposes | Notes |
|---|---|---|---|---|---|
| L01 | manuf_db | live_noise/noise_manufacturer.sql (copy of ITEM000017 as ITEM0000I7) | Verify ITEM000017 → EXACT MATCH, GENUINE, ✓ Sold | DELETE ITEM0000I7 (look-alike copy of ITEM000017) | ITEM0000I7: character 9 is the capital i |
| L02 | distributor_db | live_noise/noise_distributor.sql (ITEM0000G7) | Verify ITEM0000G7 · Pantoprazole 40mg → MATCH ITEM000067, GENUINE ('distributor holds it as ITEM0000G7') · Find ITEM000067 → distributor ITEM0000G7 NOISY VARIANT | UPDATE distributor ITEM0000G7 → ITEM000067 | ITEM0000G7: character 9 is the letter G |
| L03 | vendor_db | live_noise/noise_vendor.sql (ITEM0000SS, Omeprazol 20mg, NOV-2027) | Verify ITEM0000SS · Omeprazole 20mg → MATCH ITEM000055, GENUINE | UPDATE code → ITEM000055 · name → Omeprazole 20mg · expiry NOV-2027 → 11/2027 | ITEM0000SS: character 9 is the letter S, character 10 is the letter S |
| L04 | distributor_db + vendor_db | live_noise/prof_case_distributor.sql + prof_case_vendor.sql (both store ITEM00008S) | Verify ITEM00008S (code only) → MATCH ITEM000085, GENUINE, note names both records · Find ITEM000085 → both NOISY VARIANT | UPDATE both → ITEM000085 ('not a valid code: letters among the digits') | ITEM00008S: character 10 is the letter S |
| L05 | distributor_db + vendor_db | both store ITEM000916 for Cefixime 200mg (SQL in sheet notes) | Verify ITEM000916 · Cefixime 200mg → MATCH ITEM000196, GENUINE · code only → REVIEW (ITEM000016 fits the code as well) | UPDATE both → ITEM000196 ('the manufacturer issues item codes, so its code is kept') |  |
| L06 | manuf_db | INSERT ITEM0003O0 (MED030, other dates) | Verify ITEM000300 → EXACT MATCH | REVIEW · ⭐ Delete ITEM0003O0 (misprinted copy of ITEM000300) | ITEM0003O0: character 9 is the letter O |
| L07 | manuf_db | INSERT ITEM0003O1 (MED030) | — | UPDATE formatting only ITEM0003O1 → ITEM000301 | ITEM0003O1: character 9 is the letter O |
| L08 | vendor_db | DELETE FROM vendor_inventory WHERE item_identifier='ITEM000010' | Verify ITEM000010 → ⚠️ VENDOR RECORD NOT FOUND (Phase 1 is right) | nothing (a missing record is not noise) |  |
| L09 | manuf_db | DELETE FROM manufactured_items WHERE unique_item_code='ITEM000011' | Verify ITEM000011 → REVIEW (no such item; closest codes listed) | distributor + vendor ITEM000011 → REVIEW · ⭐ Report as counterfeit (nobody made it) |  |
| L10 | manuf_db | UPDATE expiry of ITEM000026 to 2026-06-30 | Verify ITEM000026 → ⚠️ EXPIRED ITEM | UPDATE manufacturer expiry back to 2027-12-26 (distributor + vendor agree) |  |
| L11 | vendor_db | INSERT clean record: vendor 1, distributor 1, ITEM000008, Paracetamol 500mg, ABC Pharma Ltd, 12/2025, 12/2027 | Verify ITEM000008 → ✅ GENUINE (was VENDOR RECORD NOT FOUND) | nothing (record is clean) |  |
| L12 | manuf_db | anywhere_manufacturer #1: ITEM000015 medicine MED002 → MED003 | — | UPDATE medicine_code MED003 → MED002 (2 other DBs say Monocap) |  |
| L13 | manuf_db | anywhere #2: ITEM000068 → MED009 | — | REVIEW · ⭐ 'Manufacturer is wrong: ITEM000068 is Pantoprazole 40mg (MED007)' |  |
| L14 | manuf_db | anywhere #3: Aspirin 75mg manufacturer_id → 1 | — | UPDATE manufacturer_id 1 → 4 (HealthPlus Pharma) |  |
| L15 | manuf_db | anywhere #4: medicine MED0O7 + ITEM000064 moved to it | — | UPDATE ITEM000064 MED0O7 → MED007 · DELETE medicine MED0O7 | MED0O7: character 5 is the letter O |
| L16 | manuf_db | anywhere #5: ITEM000047 expiry 2082-01-05 | — | UPDATE expiry → 2028-01-05 |  |
| L17 | distributor_db | anywhere_distributor #1: mfr_name SUNRISE PHARMACUETICALS | — | UPDATE → SUNRISE PHARMACEUTICALS |  |
| L18 | distributor_db | anywhere #2: ITEM000113 received 2062-01-21 | — | REVIEW · ⭐ 2026-01-21 (typing slip corrected) |  |
| L19 | distributor_db | anywhere #3: ITEM000131 drug_name NULL | — | UPDATE → CALCIUM 500MG |  |
| L20 | distributor_db | anywhere #4: supply shop 'LifeCare Medcal Store' | — | UPDATE → LifeCare Medical Store |  |
| L21 | distributor_db | anywhere #5: ITEM000283 mfg 2026-12-03 | — | UPDATE → 2026-03-21 |  |
| L22 | distributor_db | anywhere #6: new ITEM0000S6 + supply record | — | UPDATE ITEM0000S6 → ITEM000056 (supply record moves along) | ITEM0000S6: character 9 is the letter S |
| L23 | vendor_db | anywhere_vendor #1: sale under ITEM00O162 | — | UPDATE sale → ITEM000162 (stays Sold) | ITEM00O162: character 7 is the letter O |
| L24 | vendor_db | anywhere #2: ITEM000173 received 2025-03-13 | — | REVIEW 'correct it by hand' → owner sets 2026-03-13, then rescan |  |
| L25 | vendor_db | anywhere #3: company 'WelCare Laboratoreis' | — | UPDATE → WellCare Laboratories |  |
| L26 | vendor_db | anywhere #4: ITEM000239 mfg 40/2026 | — | UPDATE → 04/2026 |  |
| L27 | vendor_db | anywhere #5: ITEM000252 expiry NULL | — | UPDATE → 03/2028 |  |
| L28 | vendor_db | anywhere #6: stock + sale as ITEM00005B | — | UPDATE stock and sale → ITEM000058 | ITEM00005B: character 10 is the letter B |
| L29 | mediator_db | anywhere_mediator: approval under ITEM00O275 | — | UPDATE approved_items → ITEM000275 (fix script for mediator_db) | ITEM00O275: character 7 is the letter O |
| L30 | all four | all anywhere_* together, full cycle | — | scan 57 fixes + 10 decisions → resolve (⭐ options) + by-hand date → 60 logged → rescan 0 anomalies · Analysis GENUINE 188 |  |

SQL for the rows above:

- **L05**: `Distributor: INSERT INTO inventory_items (distributor_id, product_code, received_date, drug_name, mfr_name, mfg_date, exp_date) VALUES (4,'ITEM000916',DATE '2026-04-10','CEFIXIME 200MG','CURELIFE PHARMA',DATE '2026-03-21',DATE '2028-03-21');  Vendor: INSERT INTO vendor_inventory (vendor_id, distributor_id, item_identifier, received_date, medicine_name, company, mfg, expiry) VALUES (7,4,'ITEM000916',DATE '2026-04-25','Cefixime 200mg','CureLife Pharma','03/2026','03/2028');`
- **L06**: `INSERT INTO manufactured_items (medicine_code, unique_item_code, manufacturing_date, expiry_date) VALUES ('MED030','ITEM0003O0',DATE '2025-12-21',DATE '2027-12-21');`
- **L07**: `INSERT INTO manufactured_items (medicine_code, unique_item_code, manufacturing_date, expiry_date) VALUES ('MED030','ITEM0003O1',DATE '2026-05-10',DATE '2028-05-10');`
- **L10**: `UPDATE manufactured_items SET expiry_date = DATE '2026-06-30' WHERE unique_item_code = 'ITEM000026';`
- **L11**: `INSERT INTO vendor_inventory (vendor_id, distributor_id, item_identifier, received_date, medicine_name, company, mfg, expiry) VALUES (1,1,'ITEM000008',DATE '2026-02-20','Paracetamol 500mg','ABC Pharma Ltd','12/2025','12/2027');`

## 6 DB refuses

Changes PostgreSQL itself rejects (so they can never become anomalies). Run inside BEGIN; … ROLLBACK;

| ID | Where | Input / edit | What it tests | Expected | Notes |
|---|---|---|---|---|---|
| R01 | manuf_db | INSERT item with medicine_code 'MED999' | unknown medicine | ERROR foreign key manufactured_items_medicine_code_fkey |  |
| R02 | manuf_db | INSERT item with expiry before mfg | impossible dates | ERROR check constraint chk_item_dates |  |
| R03 | manuf_db | INSERT a second ITEM000001 | duplicate code | ERROR unique manufactured_items_unique_item_code_key |  |
| R04 | distributor_db | INSERT supplied_items for a code the distributor doesn't hold | orphan supply | ERROR foreign key supplied_items_product_code_fkey |  |
| R05 | distributor_db | UPDATE product_code of an item that has a supply record | breaks supply chain | ERROR … violates foreign key supplied_items_product_code_fkey |  |
| R06 | distributor_db | INSERT inventory with distributor_id 9 | unknown distributor | ERROR foreign key inventory_items_distributor_id_fkey |  |
| R07 | vendor_db | INSERT stock with vendor_id 99 | unknown shop | ERROR foreign key vendor_inventory_vendor_id_fkey |  |

## 7 Rubric 3

Vibe-coding evidence to have open on the GUI machine.

| ID | Where | Input / edit | What it tests | Expected | Notes |
|---|---|---|---|---|---|
| V01 | Files | step4_gui/PROMPT_gui.md | the prompt | prompt shown, incl. the cleansing tab and verdict list |  |
| V02 | Files | step4_gui/gui.py | generated code | 7 tabs; verify_item used for verification |  |
| V03 | Explain | our changes | team changes | own matching functions (no fuzzystrmatch / pg_trgm) · majority vote with 'manufacturer issues codes' rule · counterfeit report option · verify_item (noisy records count) · DBeaver-safe SQL |  |

