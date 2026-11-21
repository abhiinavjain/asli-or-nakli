# Prompt used to generate the Phase 2 GUI (`gui.py`)

*Attached with the prompt: the Phase 1 `gui.py`.*

---

You are extending the Streamlit GUI of our academic project **Asli-or-Nakli**, which checks whether a medicine is genuine by integrating three independent PostgreSQL databases (manufacturer, distributor, vendor). A fourth, **mediator** database reaches them through `postgres_fdw`. The GUI connects only to the mediator.

The attached `gui.py` is our Phase 1 GUI. It verifies an **exact** item code against the view `global_medicine_history`, auto-files a report in the table `reports`, and shows analysis from the materialized view `mv_medicine_analysis`.

**Phase 2** adds entity matching under noisy data. The mediator now has these SQL objects (already created; do not create or change them):

| Object | Returns |
|---|---|
| `search_by_pack(code, name, company, mfg, expiry, limit)` | Ranked candidate items for a noisy code plus optional pack details. Columns: `rank, item_code, medicine_name, manufacturer, mfg_date, expiry_date, code_edit_cost, code_score, name_score, company_score, expiry_score, mfg_score, distributor_score, supply_score, dates_swapped, context_score, total_score, verdict, decided_item`. `verdict` and `decided_item` are the same on every row. Returns **no rows** when nothing resembles the code. |
| verdicts | `EXACT MATCH`, `MATCH`, `NOISY MANUFACTURER RECORD` (the distributor and vendor both hold the typed code exactly but the manufacturer does not; `decided_item` is the manufacturer's noisy record of that item), `WRONG CODE` (typed code is real but belongs to another medicine; `decided_item` is the item that fits the pack), `CONTEXT ERROR` (code is real, medicine agrees, other pack details differ), `POSSIBLE CLONED CODE` (real code, pack contradicts it, nothing else fits), `REVIEW` (several items fit; `decided_item` is NULL), `NO MATCH` |
| `code_edit_steps(noisy, candidate)` | `step, operation, at_position, noisy_char, candidate_char, cost, reason`: the edits that turn the noisy code into the candidate |
| `normalize_code(code)` | The cleaned-up code (upper case, separators removed, look-alike letters from other alphabets fixed) |
| `find_records_for_item(item_code)` | Every distributor/vendor record that is, or looks like, that item. Columns: `source, record_id, stored_code, relation, record_status, verdict, decided_item, item_rank, item_score, code_edit_cost, name, company, expiry, distributor_id, vendor_name`. `relation` is `EXACT CODE`, `EXACT CODE, CONTEXT ERROR`, `NOISY VARIANT`, `POSSIBLE` or `BELONGS ELSEWHERE` |
| `v_golden_items` | Manufacturer reference list: `item_code, medicine_code, medicine_name, composition, manufacturer_name, manufacturing_date, expiry_date` |
| `v_stored_record_flags` | Every distributor/vendor row: `source, record_id, stored_code, distributor_id, vendor_id, vendor_name, name, company, mfg, expiry, received_date, status` (`OK`, `UNKNOWN CODE`, `CONTEXT CONFLICT`), `issues` |
| `match_stored_record(source, record_id, limit)` | Same columns as `search_by_pack`, for a stored distributor/vendor row |
| `match_config` (`key, value, description`), `code_char_costs` (`char_a, char_b, cost, reason`) | The weights, thresholds and character costs |
| `cleansing_scan()` | Runs a cleansing scan (majority vote across the three databases); returns the new `scan_id`. Takes several seconds. |
| `cleansing_scans` (`scan_id, started_at, finished_at`) | One row per scan |
| `v_cleansing_latest` | Proposals of the latest scan: `proposal_id, item_code, source, target_db, target_table, key_column, key_value, field, column_name, old_value, new_value, action` (`UPDATE` / `DELETE` / `REVIEW`), `reason, options` (REVIEW only: JSON object, option label → list of fixes), `suggested` (recommended option label or NULL), `status` (`PROPOSED`, `APPLIED`, `RESOLVED`) |
| `cleansing_resolve(proposal_id, option_label)` | A reviewer picks an option for a REVIEW; adds its fixes; returns how many |
| `cleansing_fix_sql(database)` | The fix script (text) for `manuf_db`, `distributor_db` or `vendor_db` |
| `cleansing_check()` | Detects which fixes the owners have applied, logs them; returns one row `applied, pending` |
| `cleansing_log` | Applied changes: `log_id, detected_at, target_db, target_table, key_column, key_value, column_name, old_value, new_value, action, reason` |

## Build the new `gui.py`

Organise the page into **tabs**:

1. **🔍 Verify medicine**
   - A form with **Item code** (required) and optional pack details: **Medicine name**, **Manufacturer**, **Mfg date**, **Expiry date**. Dates are free text (e.g. `MAR-2028`, `04/2028`). Show the cleaned-up code (`normalize_code`) if it differs from what was typed.
   - Call `search_by_pack` and show the verdict prominently, with a plain-language explanation for each verdict:
     - **EXACT MATCH / MATCH**: identified (for MATCH, say which item the noisy code was resolved to).
     - **WRONG CODE**: "this code belongs to another medicine; the pack matches X, probably mistyped".
     - **CONTEXT ERROR**: the code is real but the pack's details differ from the manufacturer's record, so it is suspicious (possible tampering).
     - **POSSIBLE CLONED CODE**: NAKALI. Show the pack details next to what the manufacturer's record for that code says.
     - **REVIEW**: ask the user to choose among the candidates.
     - **NO MATCH**: nothing resembles the code; offer a button to report it as a suspected fake.
     - **NOISY MANUFACTURER RECORD**: explain that the distributor and vendor both record the typed code but the manufacturer's record of this item reads `decided_item`; verify `decided_item` but do **not** auto-report it (the suspicion comes from our own noisy data; say so and point to the Data cleansing tab).
   - Show the ranked candidates as a table with their scores, and an expander explaining the code edits (`code_edit_steps`) between the typed code and the selected item.
   - Let the user pick which candidate to verify. Default: `decided_item`; for POSSIBLE CLONED CODE and CONTEXT ERROR, the item that carries the exact code; for REVIEW **no default**: nothing is verified or reported until the user chooses. The choice must survive Streamlit reruns (use `st.session_state`).
   - For the chosen item, show the **Phase 1 verification** exactly as today: status banner, medicine / manufacturer / distributor / vendor details, distributor-vendor mismatch, suspicion details, automatic report, complete history. Reuse the existing Phase 1 code.
   - Report automatically to `reports` (same table and constraints as Phase 1; `risk_status` must be `SUSPICIOUS`; `ON CONFLICT (item_identifier) DO NOTHING`) also for **POSSIBLE CLONED CODE** and **CONTEXT ERROR**, with the pack-vs-record evidence. Report **NO MATCH** only when the button is pressed.
2. **🔁 Find records for an item** ("vice versa"): input a real item code. Show the manufacturer's record for it, then `find_records_for_item` as a table with an icon per relation. Summarise how many exact and noisy records were found. If the code is not a real item, say so and show the closest items from `search_by_pack`.
3. **🩺 Data health**: counts per source and status from `v_stored_record_flags`, a table of the rows that are not OK (with their issues), and a way to pick one row and see its `match_stored_record` result plus the code edits to its best candidate. Note that applying fixes is on the Data cleansing tab.
4. **🧹 Data cleansing**:
   - A short explanation (majority vote, ties go to a person, the mediator never edits other databases, owners run their own scripts).
   - **RUN CLEANSING SCAN** (with a spinner) and **CHECK APPLIED FIXES** (show how many were applied and how many are still pending).
   - For the latest scan: metrics (fixes to run, of which deletions, reviews needing a decision, applied). If there are no proposals, say there are no anomalies.
   - Every open REVIEW: what it is about, a selectbox of its options (suggested option first and marked with ⭐, then by score, "Delete this record" last), and an **APPLY CHOICE** button calling `cleansing_resolve`, then rerun.
   - For each of the three databases: a table of its fixes with a ✅ / ⏳ status icon, a **download button** for its fix script, and an expander showing the SQL.
   - The cleansing log table.
5. **📢 Reports**: the existing Phase 1 reports section.
6. **📊 Analysis**: the existing Phase 1 analysis section, unchanged.
7. **⚙️ Matching settings**: read-only view of `match_config` and `code_char_costs`, with a one-line explanation of how the total score and verdict are computed.

## Constraints
- One file, `gui.py`. Use only `streamlit`, `psycopg2` and `pandas` (the libraries Phase 1 already uses), plus Python's built-in `json`.
- Keep `DB_CONFIG`, the connection function and the Phase 1 functions (`verify_medicine`, `file_report`, `get_reports`, the analysis queries) working as they are. Add new functions next to them.
- All SQL must use parameters (`%s`), never string formatting.
- Every database call must be wrapped so that an error shows a clear message in the GUI instead of crashing the page.
- Comment each section briefly so team members can explain it in a viva.

## Follow-up prompt (step 6 refactor: candidates from the sources, dynamic weights, trust)

> The mediator now gets candidates from each source instead of reading whole tables (`asli_probe`, registry `asli_sources`). `search_by_pack` returns an extra `weights` column (jsonb: the attribute weights used for this search and the number of candidates). New function `record_trust(item_code, code, name, company, mfg, expiry)` returns every record of the item with six factors (`entity`, `context`, `completeness`, `attribute_rel`, `source_rel`, `consistency`), a `confidence`, the factor `weights` (jsonb) and a `decision` (MOST RELIABLE, ALL RECORDS AGREE, AGREES WITH THE TOP RECORD, LESS RELIABLE, REVIEW). Update `gui.py`:
> 1. **Verify**: under the candidate table, an expander "How the attributes were weighted" with a table *Attribute · Base weight (from match_config) · Weight used now*, and a caption with the number of candidates and why weights shift. For the chosen item, an expander "Which stored record of this item is most trustworthy" with the `record_trust` table (icon per decision) and the factor weights in a caption.
> 2. **Find records**: below the records table, the same trust table for the item (no pack details).
> 3. **Data health**: an expander "Sources and what the mediator has learned" showing `asli_sources` (id, kind, enabled, description) and the reliability per source and attribute (`asli_reliability`, `source_attribute_reliability`).
> 4. **Matching settings**: extend the explanation with where candidates come from, the dynamic weights and the trust score.
> Keep everything else unchanged; jsonb may arrive as a string, so parse it with `json.loads` when needed.

**What we changed by hand after generation:** the weights table reads the base weights from `match_settings()` instead of hard-coding them; `show_trust` and `show_weights` became helper functions so Verify and Find records share them; the GUI test harness got three new checks (weights + 3-source trust table on Verify, the swapped-dates distributor copy ranked least trustworthy on Find records, the registry on Data health).
