# Phase 2 · Step 5 — Data cleansing (rubric 2), with a noisy manufacturer

> **Noise in other columns (medicine code, manufacturer link, sales, approvals, supply shop, received dates, empty values):** see `live_noise/README.md`.
>
> **Using data v2?** The numbers in this file are from the old data. For v2 (39 fixes, 8 decisions incl. 6 counterfeits, 41 changes, GENUINE 164 → 187) see `data_v2/README.md`. Counterfeit codes in shops are now offered as **Report as counterfeit (keep the record as evidence)**.

## What changed after the professor's feedback

- **The manufacturer can be noisy too**, so no database is treated as automatically correct. For every item the mediator compares what the **manufacturer, distributor and vendor** record and takes a **majority vote (2 of 3)** for each field.
- **No extensions.** Everything is our own SQL / PL/pgSQL (see the step 2 README).

## Files

| File | Run on | By |
|---|---|---|
| `manufacturer_02_noisy_records.sql` | manuf_db | manufacturer owner |
| `../step3/mediator_03_candidate_search.sql` (**updated, re-run it**) | mediator_db | mediator owner |
| `mediator_05_cleansing.sql` | mediator_db | mediator owner |
| `../step4_gui/gui.py` (**updated**: new 🧹 Data cleansing tab) | GUI machine | — |
| `noise_catalogue.csv` | — | ground truth for all 32 noisy records + the fix expected for each |

## How to run (in this order)

**0. Backups first, on every machine.** The cleansing changes real data, so you need these to reset after a rehearsal:
```
pg_dump -U postgres -Fc -d manuf_db -f manufacturer_before_cleansing.dump
pg_dump -U postgres -Fc -d distributor_db  -f distributor_before_cleansing.dump
pg_dump -U postgres -Fc -d vendor_db       -f vendor_before_cleansing.dump
pg_dump -U postgres -Fc -d mediator_db     -f mediator_before_cleansing.dump
```
On Windows, run these from the PostgreSQL `bin` folder, e.g. `C:\Program Files\PostgreSQL\18\bin`.

| # | Who | What | Expect |
|---|---|---|---|
| 1 | Mediator | `step3/mediator_03_candidate_search.sql` (Alt+X) | 6 checks PASS (rows 4–6 may say SKIP once data is cleansed) |
| 2 | Mediator | `mediator_05_cleansing.sql` (Alt+X) | 4 checks PASS |
| 3 | Manufacturer | `manufacturer_02_noisy_records.sql` | 8 rows, each showing the noisy value |
| 4 | GUI | replace `gui.py`, `streamlit run gui.py` | 7 tabs, including 🧹 Data cleansing |

Step 3 must be re-run because matching gained two rules (details below).

**To reset after a rehearsal**, restore all four backups (same folder as above):
```
pg_restore -U postgres -d vendor_db --clean --if-exists vendor_before_cleansing.dump
```
…and the same for the other three databases.

## The noisy manufacturer records

| ID | Change | Noisy value | True value | Expected |
|---|---|---|---|---|
| M01 | item code, O for 0 twice | `ITEM0OO002` | ITEM000002 | fix manufacturer (distributor + vendor agree) |
| M02 | item code, a zero dropped | `ITEM00005` | ITEM000005 | fix manufacturer |
| M03 | medicine name, letters swapped | Metfromin 500mg | Metformin 500mg | fix manufacturer |
| M04 | manufacturer name | CureLyfe Pharma | CureLife Pharma | fix manufacturer |
| M05 | expiry of ITEM000004 | 2027-10-15 | 2027-01-15 | fix manufacturer |
| M06 | mfg date of ITEM000001 | 2025-06-15 | 2025-09-15 | fix manufacturer |
| M07 | same item twice | `ITEM00020l` *and* ITEM000201 | — | delete the copy |
| M08 | item code, S for 5 | `ITEM0001S0` | ITEM000150 | **REVIEW**: only the distributor also has it, so it's 1 to 1. Suggests ITEM000150 |

## How the cleansing decides

1. **Assign every stored record to an item.**
   - If its code (after clean-up) is a real item and the medicine name agrees, assign it directly.
   - Otherwise the step 3 matcher decides.
   - If several items fit, the record goes to REVIEW: choose one, or delete the record.
2. **Duplicates.**
   - Two records of the same item in one database → delete the noisy one (V17).
   - The manufacturer holding a look-alike copy of an item → delete the copy (M07).
3. **Vote per field.**

| Field | Grouped by | Each database votes with | Compared as |
|---|---|---|---|
| Item code | item | its value | after clean-up (case, spaces, dashes, look-alike letters) |
| Expiry, mfg date | item | its value | month (vendors store `MM/YYYY`) |
| Medicine name | medicine | the spelling it uses most | after normalising (`500 mg` = `500mg`; composition counts as agreeing) |
| Manufacturer | manufacturer | the spelling it uses most | after normalising (`Labs` = `Laboratories`, `Ltd` ignored, spaces ignored) |

| Votes | Result |
|---|---|
| 2 or 3 agree | **UPDATE** every value that disagrees, in that database's own format (distributor names in UPPER CASE, vendor dates as `MM/YYYY`) |
| Same value, different format | **UPDATE**, "formatting only" (`item-000202`, `MAR-2028`, `6/28`) |
| 1 to 1, no majority | **REVIEW**: each value is an option; for codes the one in standard format (`ITEM` + 6 digits) is suggested |

Mfg and expiry dates swapped (D06) are detected and explained in one line.

4. **Fix scripts.**
   - The mediator **never writes** to the other databases. It generates one script per database.
   - Every statement only changes a row if it still has the old value, so running a script twice is harmless.
   - Each owner downloads their script from the GUI and runs it on their own database.
5. **Check applied fixes.**
   - The mediator re-reads the live data and marks each fix it finds as APPLIED.
   - Every applied change goes into `cleansing_log` (old → new, reason, time).

**Deliberately not changed:** distributor-ID mismatches between the distributor and vendor (the Phase 1 checks). Those are supply-chain fraud signals, not noise.

## Two matching rules added to step 3

1. **Majority rule for codes.** If the distributor *and* the vendor both hold a code exactly but the manufacturer doesn't, the manufacturer's copy is the noisy one.
   - Only manufacturer items that no other database already holds are eligible.
   - The verdict is **NOISY MANUFACTURER RECORD**.
   - A buyer typing the *correct* code still finds the item. The GUI does **not** report it, because the suspicion comes from our data, not the medicine.
2. **Supply evidence only counts when it agrees.** "Distributor says it supplied this item to this shop" adds support. A different shop no longer counts against an item. (Found by testing an arbitrary shop on a new record: the right item was being pushed down.)

The 24 step-1 records resolve exactly as before (same verdicts, same items).

## Results on the local copy

**First scan: 38 fixes + 2 reviews**

| Database | Fixes | What |
|---|---|---|
| manuf_db | 7 | M01–M06 + delete M07 |
| distributor_db | 9 | D01–D06 codes, D06 swapped dates (2), D02 name |
| vendor_db | 22 | 15 codes (incl. V06/V15 → the right item), delete V17, V18 expiry, 3 date formats, 2 names |
| REVIEW | 2 | V16 (choose ITEM000171), M08 (choose ITEM000150) |

**After running the scripts, resolving the two reviews and running round two:**
- 40 changes logged across the 3 databases.
- A rescan finds **0 anomalies**.
- All 389 stored records check OK against the manufacturer.
- Phase 1 verification: **GENUINE went from 5 to 28 items**.

The same cycle was re-run from a fresh restore with the same result, and running every script twice changed nothing extra.

**A rehearsal with new edits, like the professor might make live:**

| Edit | Result |
|---|---|
| New noisy vendor record (`ITEM00O222`, Glimepiride details) | Resolved to the Glimepiride item, code fixed, date format fixed |
| Manufacturer code `ITEM000106` → `ITEM0001O6` | Fixed back to ITEM000106 |
| Distributor name `CEFIXIM 200MG` | Fixed to `CEFIXIME 200MG` |
| Distributor duplicate `ITEM0002S5` of an existing item | Deleted |
| Manufacturer expiry changed on an item only the distributor also holds | REVIEW (1 to 1), options carry each side's exact date |

**Speed:** a scan takes 2–15 s locally (it only runs the matcher on records that need it). Expect longer across your machines.

## Rubric 2 demo script (GUI)

1. **🩺 Data health:** 33 records need attention.
2. **🔍 Verify:** `ITEM000002` + `Paracetamol 500mg` → **NOISY MANUFACTURER RECORD** (not reported).
3. **🧹 Data cleansing** → **RUN CLEANSING SCAN** → 38 fixes, 2 decisions.
4. Resolve the two reviews: pick the ⭐ suggested ITEM000150, and ITEM000171 for `ITEM00017` → **APPLY CHOICE**.
5. Each owner downloads their script and runs it on their database (DBeaver Alt+X).
6. **CHECK APPLIED FIXES** → 40 applied; the log shows every change.
7. **RUN CLEANSING SCAN** again → "No anomalies".
8. **🔍 Verify** `ITEM000002` → EXACT MATCH, **GENUINE**. **🩺 Data health** → nothing needs attention.

## Known limitations (good to state if asked)

- **A 1-to-1 disagreement is never auto-fixed.** For example, an item that only the manufacturer and distributor hold, with different values. It always goes to a person.
- **Medicine or manufacturer name ties** are listed, but must be corrected by hand.
- **One review choice can fail to apply.** If a reviewer changes a distributor `product_code` that `supplied_items` refers to, the distributor's foreign key blocks the script. Choosing the suggested option avoids this.
