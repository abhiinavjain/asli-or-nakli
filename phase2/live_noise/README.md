# Live noise: what Sir can change, and what the scan does

## Update first (mediator owner + GUI machine)

| File | Where | Expect |
|---|---|---|
| `step5_cleansing/mediator_05_cleansing.sql` (**updated**) | mediator_db, DBeaver Alt+X | **5** checks PASS |
| `step4_gui/gui.py` (**updated**, one line) | GUI machine | the cleansing tab also lists **mediator_db** (for approvals) |

Nothing else changes. The old results are unchanged: on data v2 the first scan still gives 39 fixes + 8 decisions, and the full cycle still ends with 0 anomalies.

## What the database refuses on its own

If Sir tries any of these, PostgreSQL rejects the change, so no anomaly is ever stored:

| Change | Why it's refused |
|---|---|
| an item with a medicine code that isn't in `medicines` (e.g. `MED00002`) | foreign key |
| expiry on or before mfg at the manufacturer | `chk_item_dates` |
| two items or records with the same code | unique |
| a supply record for a code the distributor doesn't hold | foreign key |
| changing a distributor code that a supply record uses | foreign key |
| a shop or distributor id that doesn't exist | foreign key |

## Noise in any column: what the scan proposes

Majority means 2 of the 3 databases agree. 1 to 1 means only two databases hold the value and they disagree.

| Noise | Proposal |
|---|---|
| Item code (any DB, look-alike letters, missing or extra zeros, swaps) | majority wins; 1 to 1 → REVIEW, with the `ITEM`+6-digit code suggested |
| Same item recorded twice | DELETE the extra record. A supply record pointing at the copy is moved. |
| mfg / expiry (wrong, swapped, odd format, `40/2026`, empty) | majority wins, written in each DB's own format |
| Medicine name / company (misspelt or empty) | majority spelling |
| **Item recorded as the wrong medicine** (`medicine_code` set to another real medicine) | majority → fix `medicine_code`. 1 to 1 → REVIEW; the option whose batch dates match is suggested. |
| **Medicine linked to the wrong manufacturer** (`manufacturer_id`) | distributor and vendor agree → fix `manufacturer_id` |
| **Same medicine under a look-alike code** (`MED0O7`) | move its items to `MED007`, then delete the copy (only once no item uses it) |
| **Sale under a noisy code** | follows the shop's stock code, so the item stays "Sold" |
| **Approval under a noisy code** (mediator) | fix `approved_items` (fix script for mediator_db) |
| **Misspelt shop in a supply record** | the closest shop name, preferring the shop that holds the item |
| **Received / supply / sale date** before manufacture or in the future | REVIEW. If a typing slip explains it (two digits swapped, or day and month swapped), that date is suggested; otherwise correct it by hand. |
| Distributor-id mismatch between distributor and vendor | **not changed**: it's a Phase 1 fraud signal, not noise |
| Columns stored in one database only (composition, dosage form, addresses, licence numbers) | nothing to compare against, so they're left as they are |

## Practice scripts (load data v2 first)

- `noise_manufacturer.sql`, `noise_distributor.sql`, `noise_vendor.sql`: one noisy record each.
  - Results: delete `ITEM0000I7`; `ITEM0000G7` → ITEM000067; vendor `ITEM0000SS` → ITEM000055, plus the name and expiry fixes.
- `anywhere_manufacturer.sql`, `anywhere_distributor.sql`, `anywhere_vendor.sql`, `anywhere_mediator.sql`: 18 edits in the other columns. Each line's comment gives the expected proposal.

**Tested locally (all four `anywhere_*` scripts together):**

| Step | Result |
|---|---|
| First scan | 56 fixes + 11 decisions |
| Run the scripts, resolve the decisions (fix the one "by hand" date), run the scripts again | rescan: **0 anomalies** |
| Compared row by row with the clean answer key | only the 5 known equivalent spellings, plus the new distributor record and its supply record, both now under the correct code `ITEM000056` |

Every one of the 18 edits was undone correctly.
