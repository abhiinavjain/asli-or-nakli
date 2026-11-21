# Data v2 — fresh test data for Phase 1 + Phase 2

This replaces **all rows** in the four databases. **No table, column or constraint is changed.** Each script only empties the tables and inserts new rows.

## What's in it

| | |
|---|---|
| Manufacturers / medicines / items | 10 / 30 / 300 (`ITEM000001`–`ITEM000300`, 10 per medicine, 2 batches each) |
| Distributor stock / supply records | 275 / 234 |
| Shop stock / **sales** | 264 / **116** (sales now use **item codes**, so "✓ Sold" works) |
| Approved items | 275 |
| Phase 1 cases | every rule, 4–95 items each, plus combinations (see `TEST_CASES.md`) |
| Counterfeit codes in shops | 6 (2 of them sold) |
| Phase 2 noise | the same 33 noisy records we already tested (V01–V18, D01–D07, M01–M08), re-applied to the new data |

**Why "Not Sold" was wrong before:** `medicine_sales` held *medicine* codes (`MED001`…), but verification joins on *item* codes, so nothing ever matched.

## How to load (in this order)

**0. Backups** (Windows: run from the PostgreSQL `bin` folder):
```
pg_dump -U postgres -Fc -d manuf_db -f manuf_db_before_v2.dump
pg_dump -U postgres -Fc -d distributor_db  -f distributor_db_before_v2.dump
pg_dump -U postgres -Fc -d vendor_db       -f vendor_db_before_v2.dump
pg_dump -U postgres -Fc -d mediator_db     -f mediator_db_before_v2.dump
```

| # | Who | Script (DBeaver, Alt+X) | Expect in the last result tab |
|---|---|---|---|
| 1 | Manufacturer | `01_manuf_db_v2.sql` | 10 · 30 · 301 |
| 2 | Distributor | `02_distributor_db_v2.sql` | 5 · 275 · 234 |
| 3 | Vendor | `03_vendor_db_v2.sql` | 10 · 264 · 116 |
| 4 | Mediator, **last** | `04_mediator_db_v2.sql` | 275 approvals · 0 reports · 0 scans · 301 · 275 · 264 |

- Steps 1–3 can run in parallel.
- Every script can be re-run; it gives the same result each time.
- Script 4 keeps all matching and cleansing functions and settings. It replaces the approvals, empties `reports` and the cleansing history, and refreshes the analysis view.

**Do not run the old noise scripts again** (`distributor_02`, `vendor_02`, `manufacturer_02`). The noise is already inside v2.

## Files

| File | Use |
|---|---|
| `01`–`04_*_v2.sql` | **the demo data** (with noise) |
| `clean_answer_key/*_clean.sql` | the same data **without noise**: what the databases should look like after a perfect cleansing. Load instead of 01–03 if you ever want a noise-free system. |
| `TEST_CASES.md` | item codes for every Phase 1 case and every Phase 2 demo, with results checked on the loaded data |
| `test_cases_v2.csv` | every item: its case and its actual Phase 1 result, distributor, shop, Sold / Not Sold |
| `noise_catalogue_v2.csv` | all 33 noisy records: stored value, true value, expected matching and cleansing result |
| `Demo_checklist_v2.xlsx` | 46-step rehearsal checklist with PASS/FAIL columns |

## Checked on a local copy before sending

**Phase 1**
- **Clean answer key:** all 300 items give their case's expected result, *and* Sold / Not Sold is right.
- **Demo data:** all 267 items without noise give the same result.
- **Counterfeit codes** never appear in the Phase 1 view.

**Mediator checks on the demo data**
- Step 2: 18 PASS. Step 3: 6 PASS. Step 5: 4 PASS.
- Code-only benchmark: still 19/20 for ours vs 11/20 plain Levenshtein and 13/20 trigram. Compute it on the clean manufacturer list (the clean key, or before loading the noise); with the noisy manufacturer present it reads 18/20, because D03 then ties with the manufacturer's own noisy code M02.

**Cleansing, full cycle**

| Step | Result |
|---|---|
| Scan 1 | 40 fixes (manufacturer 8, distributor 10, vendor 22; 3 of them deletions) + 7 decisions |
| Decisions | V16 → ITEM000171, and 6 counterfeits → **report as counterfeit (record kept as evidence)**. M08 (`ITEM0001S0`) is now fixed automatically to ITEM000150: a code with letters among the digits never wins |
| Check applied | 41 changes logged |
| Rescan | **0 anomalies** |
| Phase 1 GENUINE | 164 → **187**, exactly the clean answer key's numbers |

Compared row by row with the clean answer key, only 5 rows differ. All 5 are spellings the cleansing deliberately treats as the same: `MediCare Labs`, `PrimeHealth Pharma`, `Cure Life Pharma`, composition used as name, `10 MG` vs `10MG`.

**GUI:** 34 automated scenarios pass on this data, including the whole cleansing flow and the counterfeit reports.

## New in the cleansing (re-run `step5_cleansing/mediator_05_cleansing.sql` once)

- **Counterfeit codes in shops** (codes the manufacturer never made) now come up as a decision whose ⭐ suggested option is **"Report as counterfeit (keep the record as evidence)"**. It files a `COUNTERFEIT CODE IN STOCK` report and keeps the record. Reported codes are no longer treated as anomalies. Deleting them is still offered, but that would destroy evidence.
- `gui.py` was updated slightly: the message after a choice now reads "Choice applied…". Take the new `gui.py`.

## Update (22 Oct): the same noisy code at the distributor AND the vendor

Case raised by the professor: the distributor and the vendor both store the same noisy code (e.g. `ITEM00008S` for ITEM000085); the manufacturer only has the correct one. Before, the majority rule blamed the manufacturer.

- **Matching (step 3):** the majority rule ("manufacturer is the noisy one") now applies only when the distributor/vendor code is in the standard format `ITEM` + 6 digits **and** the manufacturer's copy is a near-identical code that is **not** (e.g. `ITEM0OO002`). Otherwise the shared code is treated as distributor/vendor noise: `ITEM00008S` → **MATCH ITEM000085**.
- **Verification:** new mediator function `verify_item(code)` = the same Phase 1 rules as `global_medicine_history` (the view is unchanged), but records stored under a noisy code of the item also count. The GUI's Verify tab uses it and says which records were matched under noisy codes.
- **Cleansing (step 5):** for item codes, a code with letters among the digits never wins the vote; when two valid-looking codes disagree, the manufacturer's code is kept (it issues the codes). Both stored copies of `ITEM00008S` are fixed to ITEM000085.
- Re-run `step3/mediator_03_candidate_search.sql` and `step5_cleansing/mediator_05_cleansing.sql` (Alt+X), and take the new `gui.py`.
- Rehearsal scripts: `live_noise/prof_case_distributor.sql` + `live_noise/prof_case_vendor.sql`.
- **Deleted manufacturer item:** if the manufacturer's `ITEM000011` is deleted, the distributor/vendor records of `ITEM000011` are no longer re-assigned to its neighbour `ITEM000012`; they come up as "possible counterfeit" (report and keep as evidence).
- Full test list with expected results: `TEST_CASES_v3.md` / `Demo_test_cases_v3.xlsx` (97 cases).
