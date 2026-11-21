# Data v2 — rebuilt (21 Nov 2026)

The original data v2 load scripts (`01–04_*_v2.sql`) and the Phase 2 step 1 scripts
(`distributor_01`, `vendor_01`, `mediator_01`) were never saved. These files replace them.
They regenerate the distributor, vendor and mediator data around the **real** `manuf_db`.

| File | What it does |
|---|---|
| `step1_context_columns.sql` | step 1: context columns on `inventory_items` (drug_name, mfr_name, mfg_date, exp_date) and `vendor_inventory` (medicine_name, company, mfg, expiry) |
| `mediator_01_fdw_columns.sql` | step 1: the same columns on the mediator's foreign tables |
| `gen_data.py` | generates the three data scripts below from the manufacturer rows, `TEST_CASES.md` and `noise_catalogue_v2.csv` |
| `distributor_data.sql` / `vendor_data.sql` / `mediator_data.sql` | the generated data (replaces 02–04_*_v2.sql) |

**How close to the original:** every item code listed in `data_v2/TEST_CASES.md` has its
case, all 25 expired items match, V01–V18 and D01–D07 are applied from the noise catalogue,
and the 6 counterfeit codes are in shops (2 sold). Row counts: distributor 5 · 275 · 244,
vendor 10 · 267 · 127, mediator 275 approvals. Phase 1 counts: GENUINE 167, vendor not found 44,
unapproved 30, distributor not found 28, expired 21, ID mismatch 14 (original sheet: 164 / 46 / 29 / 28 / 21 / 13).
Items not listed in the test sheet were assigned to cases at random (seed 231), so their
individual results can differ from the old `test_cases_v2.csv`.

**Build order used (all checks PASS):** Phase 1 schema → step 1 → data → asli_match +
`*_06_candidate_indexes` → `asli_ctx_core` + `*_07_tables` on each source; on the mediator:
step 1 → approvals → step 2 (15 PASS) → step 6 (5 PASS) → step 3 (8 PASS) → step 5 (5 PASS) →
Phase 3 `07` (4 PASS) → step 3 again → `08` → `phase3_index_documents.py` (51 documents).
The resulting dumps are in `deploy/dumps/`.
