# Our modifications to the generated code

The **🧾 Prompt & code** tab compares `generated/` (the code exactly as first generated) with the files we run, and shows the diff.

## Round 1: fixes from our review of the generated code (bug report of 18 Nov)

We tested the generated Phase 3 on our own mediator and machines and wrote a bug report. These are the changes made because of it. IDs refer to that report.

| ID | File(s) | What we changed | Why |
|---|---|---|---|
| C1 | `app/asli_phase3.py` | Every typed item code now goes through the Phase 1/2 checks (`search_by_pack` + `verify_item`). New signals: UNKNOWN CODE, CLONED CODE, PACK MISMATCH, BATCH MISMATCH, UNAPPROVED, EXPIRED, DISTRIBUTOR MISMATCH, SUPPLY GAP. | A counterfeit code held only by a shop (ITEM583920) got "no red flags". Expired and unapproved items were flagged only by luck, through unrelated documents. |
| C2 | `sources/*_07_tables.sql` | All new foreign keys cascade: `shipment_lines` ON UPDATE / ON DELETE CASCADE, `production_batches.medicine_code` ON UPDATE / ON DELETE CASCADE, and so on. Re-running the script upgrades an existing install. | The Phase 2 fix scripts delete duplicate stock records and look-alike medicine copies. The new foreign keys blocked those deletes, which rolled back the whole fix script. |
| C3 | `sources/manufacturer_07_tables.sql`, `distributor_07_tables.sql`; `app/asli_phase3.py` | The demo findings go on **one** batch / shipment only: the batch of ITEM000041 and ITEM000035, or else the earliest batch. Earlier story rows are reset first. For an item query, signals about other batches, plants, shipments or stock records of the same medicine drop to "context only" (severity 1). | Every Ibuprofen and Amoxicillin batch failed QC, and one item was blamed for the QC failures of other batches. |
| C4 | `corpus/documents.json`, `app/phase3_index_documents.py`, `asli_ctx.demo_story`, `p3_demo_story()` | Demo documents use placeholders (`{{ibuprofen_batch}}`). The loader fills in the real batch numbers that each source stored in `asli_ctx.demo_story`. | The documents named batch SUN-MED005-2603, which does not exist in our data (ours is -2511 / -2601), so the batch link never worked. |
| H1 | `app/asli_phase3.py`, `asli_llm.py`, `gui_phase3.py` | One combined verdict with a problem type: COUNTERFEIT, UNAPPROVED, EXPIRED, SUBSTANDARD BATCH, TRANSPORT DAMAGE, SUPPLY CHAIN, OUTSIDE REPORTS, CUSTOMER COMPLAINTS. Wording such as "The code is genuine (ITEM000041), but: SUBSTANDARD BATCH". The item check table is shown above the evidence. | Verify said GENUINE and the Phase 3 panel said HIGH RISK, with no explanation. |
| H2 | `mediator_07` `p3_parse` | Item codes need 3–8 digits or look-alikes after the prefix, separators are allowed, and at least one real digit is required. Stop words moved to a table (`p3_stop_words`), with Hinglish words added. | "item code" became a seed; ITEM-000-106 was cut to ITEM-000. |
| H3 | `app/asli_phase3.py` | A document counts against an item only if it names the item's own batch or code (or its own shop) **and** the medicine. A company-only mention is information. Documents older than 2 years count one level less. | One alert about one product raised CAUTION for every product of that company. |
| H4 | `sources/*_07_tables.sql` | Triggers on `manufactured_items`, `supplied_items`, `vendor_inventory` and `medicine_sales` link every new row (to a batch, shipment, bill or customer, creating it if needed). A linking error is only a warning and never blocks the insert. `asli_ctx.refresh_links()` does the same in bulk. | Rows the professor inserts live would have had no Phase 3 context. |
| H5 | `sources/asli_ctx_core.sql`, `*_07_tables.sql` | FK joins compare typed values (`p.id = (row->>'id')::int`) so indexes are used. New `prefix` match with `text_pattern_ops` indexes for medicine names on large tables. Fold index on `supplied_items`. | Casting the indexed column to text made every hop a sequential scan. |
| H6 | `app/gui.py`, `gui_phase3.py` | A page selector instead of `st.tabs`: only the open page runs. The source-schema panel is behind a toggle and cached for 10 minutes. | Every click re-ran all 9 tabs; one Verify took 1–2.5 minutes. |
| H7 | `mediator_07` | Every source server gets `connect_timeout` (3 s, `p3_connect_timeout_s`). | A laptop off the network froze a query for the TCP timeout (about 2 min). |
| H8 | `sources/asli_ctx_core.sql`, `vendor_07_tables.sql`, `mediator_07` | `asli_ctx.private_columns`: customer names masked, phone numbers dropped before a row leaves the source. Audit rows are deleted after `p3_retention_days` (30). | Personal data was copied to the mediator and kept forever. |
| — | `phase2/step3/mediator_03_candidate_search.sql` | `match_candidates` marked VOLATILE so it is not inlined. | Inlined into `find_records_for_item` / `verify_item`, it made one verification take 8 s instead of 1.5 s; this was the main cause of the slow Verify page. |
| M1, M2 | `asli_ctx_core.sql` | Seed rows ordered by relevance then primary key; child rows ordered by the typed primary key; LIKE wildcards in typed values escaped. | Which 25 rows a seed returned was arbitrary; typing `%` matched every shop. |
| M4, M5, M8 | `asli_phase3.py`, `mediator_07` | Duplicate signals merged (dates ignored); signals read the whole context, not only the top 60 rows; only the top documents' bodies are fetched. | Inflated warning counts; findings ranked 61st were ignored. |
| L4 | `*_07_tables.sql` | `city` falls back to the whole address or 'Unknown'. | A NULL address made the script fail. |
| Verify | `app/gui.py` | New inputs: **batch number** (compared with the code's real batch), **"Other" shop** (an unregistered shop is a red flag). New checks: purchase date in the future or before manufacture, and the item already sold by another shop. Clearer banners: "GENUINE CODE, FAKE PACK" for cloned codes; "CHECK PENDING" when the suspicion comes from our own noisy manufacturer record. The weights table shows "not given" for blank fields. | Review: Verify inputs and confusing banners. |

## Round 2: fixes from our second review (20 Nov) and the new GUI

| ID | File(s) | What we changed | Why |
|---|---|---|---|
| A1 | `sources/manufacturer_07_tables.sql` | Every Sunrise batch except the two story batches is moved back to Unit 1. | v1 put every Sunrise Ibuprofen and Amoxicillin batch in Unit 2, whose GMP had expired, so clean batches (ITEM000046, ITEM000050) showed HIGH RISK. |
| A2, A3 | `app/asli_phase3.py` (`_own_row`) | A batch, shipment or complaint row counts if it belongs to **any** item asked about. If an item's own batch or shipment is unknown, the row is context only. | "ITEM000005 and ITEM000041" hid the bad item; an item with no batch link was blamed for another batch. |
| A4 | `asli_phase3.py`, `gui.py` | Batch numbers are compared without spaces or dashes (SUN MED005 2511 = SUN-MED005-2511). | A correct batch typed with spaces was called COUNTERFEIT. |
| A5 | `mediator_07` (`p3_parse`), `asli_phase3.py` | A code needs at least 3 real digits and at most 2 look-alike letters, and no word right after "item". COUNTERFEIT only when a shop or distributor holds the unknown code; otherwise "check the code" (CODE_NOT_FOUND, warning). | "item is 105 tablets" became the code ITEMIS105 and was called counterfeit. |
| A6 | `asli_phase3.py` | New warning CODE_CORRECTED when the typed code was replaced by a different real code. GENUINE is not shown unless the medicine name or batch confirms the item. | ITEM000341 silently became "ITEM000241 is GENUINE". |
| A7 | `mediator_07`, `distributor_07_tables.sql` | `p3_min_seed_weight` lowered 0.25 → 0.15 (an existing install is updated); new text entry on `inventory_items.drug_name`. | Round 2 never reached the manufacturer, and the distributor never got distributor_id 1. |
| B1 | `mediator_07` (`p3_item_batch`), `asli_phase3.py`, `gui_phase3.py` | With the manufacturer offline the answer still comes, with the warning "item check unavailable"; a code is never called counterfeit then; a failed query clears the old result. | The page showed only "could not establish connection". |
| B2 | `sources/*_07_tables.sql` | Each row in `refresh_links()` is linked on its own; a bad row is a warning. | One NULL date stopped the whole install script. |
| B3 | `gui.py` | NULL manufacturing and expiry dates are skipped in the bill check. | TypeError: Cannot compare NaT. |
| C1 | `vendor_07_tables.sql` | `customers.customer_ref` and `medicine_sales.customer_reference` never leave the vendor. | A name and phone number in customer_reference reached the mediator. |
| D1 | `mediator_07` | A pooled dblink connection is tested with `SELECT 1` and reconnected if broken. | One query took 84 s. |
| D2 + speed | `asli_phase3.py`, `gui_phase3.py`, `gui.py` | The search model loads once per app (not per question). The trust table is computed only when switched on. A model that failed to load is tried again. | Document search took 16.8 s; Verify took 25 s. |
| E | sources, `mediator_07`, `asli_phase3.py` | Exact-code batch first in `p3_item_batch`; `asli.fold('ITEM000041')` literals; 4-digit ids in new bill and shipment numbers (existing bills are found by shop + distributor + day); exact "DISTRIBUTOR ID MISMATCH"; only the asked items' codes and batches are strong document evidence; story shipments checked to carry the right medicine. | Review E. |
| GUI | `gui.py`, `gui_phase3.py` | **New layout.** The sidebar is grouped by phase. Phase 3 is one five-step story: ① question → ② Phase 2 matching → ③ structured context per database (rows, tables, keys passed in round 2, FK paths) → ④ documents with "Matched because it mentions <term> from <database.table>" → ⑤ answer. New page "Databases & FK links" with live row counts and NEW tables. Prompt & code shows changed lines per file. | Make the structured → unstructured link visible and the demo simple. |

## Round 3: more documents (21 Nov)

| ID | File(s) | What we changed | Why |
|---|---|---|---|
| R3-1 | `corpus/documents.json` | 22 → 51 documents. 17 more REAL summaries with URLs (WHO, CDSCO and state alerts to Sep 2026, US FDA recalls, counterfeit busts, drug labels). 12 more [Demo] documents that name our own shipments, vehicle, shops and codes, plus negative controls. | More of our 33 medicines have real outside evidence; the demo shows both a match and a correct "no problem". |
| R3-2 | `mediator_08` (`p3_search_documents`) | Each medicine term also searches its generic name. | "Paracetamol 500mg" found no real alert, because the alerts say just "paracetamol". |
| R3-3 | `asli_phase3.py` (`_pick_documents`) | Up to 2 of the 8 documents shown are real ones that matched. | Demo documents name our own entities and always ranked higher, so real sources were never shown. |
| R3-4 | `asli_phase3.py` (`_problem_mention`) | Without an item, a document counts against a medicine only if a sentence names the medicine **and** a problem; if the question names a medicine, only that medicine counts. | "Telmisartan 40mg: of standard quality" gave CAUTION; ABC's expired cetirizine raised CAUTION for ABC's paracetamol. |
| R3-5 | `mediator_07` (`p3_parse`, `p3_stop_words`) | 3-letter words in capitals are seeds (ORS, ABC). Dosage forms and company words (*powder, syrup, pharma, laboratories…*) are stop words. | "Is ORS Powder safe?" searched only "powder", matched an amoxicillin complaint and said CAUTION; "pharma" matched every "Pharmacy". |

## Not changed (known limits, mention in the viva)

- **Temperature rule:** a fixed 25 °C limit (M6). A real system would read each medicine's storage condition.
- **Reports:** a Phase 1 report is not updated when an item's status changes later (M9).
- **Date-dependent results:** `GMP_EXPIRED` and the expiry checks use today's date, so results change over time (L5).

## Your own changes

Add a row here for every change a team member makes by hand.

| File | What we changed | Why |
|---|---|---|
| | | |
