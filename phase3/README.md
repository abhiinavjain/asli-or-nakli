# Phase 3 — Integrating unstructured data with federated, FK-driven query context

A buyer or pharmacist asks a question: *"Is Ibuprofen from Sunrise sold at CityCare safe?"*, an item code, or a pack and bill on the Verify tab. The system then:

1. **Splits the question into a sub-query and sends it to the three machines at the same time.** It uses `dblink` asynchronous calls from the mediator.
2. **Each database discovers the context itself.** It walks its own FK → PK graph, read live from `pg_constraint`, and returns only the rows related to the query, ranked by relevance.
3. **Follows cross-database keys in a second round.** For example, the distributor says it shipped to *CityCare*, so the vendor gets a new seed. The vendor says the bill came from *distributor 1*, so the distributor gets one.
4. **Turns the accumulated context into weighted search terms** (batch numbers, item codes, names, shops) and searches the unstructured documents with them. The search is hybrid: full-text, embeddings, and exact mentions of the case's entities.
5. **Integrates everything into one answer.** It gives a risk level, risk signals from both the structured rows and the documents, and a written answer that cites every fact. The answer is AI-written when an API key is set.

No existing table, column or constraint is changed. Phases 1 and 2 keep working; the step 3 checks still pass.

## Rubric map

| Rubric | Where |
|---|---|
| **1. 4–5+ tables per DB, joined by FK–PK (2)** | `sources/<db>_07_tables.sql`. manufacturer: 3 → **7** tables · distributor: 3 → **7** · vendor: 3 → **8**. The GUI draws the live FK graph of every machine (Ask tab → *Source schemas*). |
| **2. Federated context discovery over FK–PK, on different machines, highly related to the query (3)** | `sources/asli_ctx_core.sql` (runs AT each source) + `mediator/mediator_07_federated_context.sql` (parallel dblink, 2 rounds, cross-DB keys, audit). GUI: *Federation* and *Context* tabs. |
| **3. Search unstructured data correlated with the query context and integrate it (3)** | `mediator/mediator_08_documents.sql` (hybrid search) + `app/asli_phase3.py` (signals, assessment) + `app/asli_llm.py` (cited answer). GUI: *Documents*, *Signals*, answer. |
| **4. Prompt, generated code, modified code (2)** | `prompts/PROMPT_phase3.md`, `generated/` (the code exactly as generated), `prompts/MODIFICATIONS.md`. GUI tab **🧾 Prompt & code** shows the prompt and a live diff (generated vs current). |

## New tables (all FK → PK)

```
manuf_db        manufacturers 1─< plants 1─< production_batches >─1 medicines
                  manufactured_items 1─1 batch_items >─1 production_batches 1─< qc_reports
distributor_db    distributors 1─< warehouses 1─< shipments 1─< shipment_lines >─1 inventory_items
                  shipments 1─< temperature_logs
vendor_db         vendors 1─< purchase_invoices 1─< invoice_lines >─1 vendor_inventory
                  vendors 1─< customer_complaints >─1 customers 1─< sale_customers >─1 medicine_sales
                  customer_complaints >─1 vendor_inventory
```

- **Link tables** (`batch_items`, `shipment_lines`, `invoice_lines`, `sale_customers`) connect new data to existing rows without adding a column to an existing table.
- **Cross-database keys** are kept as plain columns and registered in `p3_links` on the mediator: `shipments.shop_name` = vendor name, and `purchase_invoices.distributor_id` = distributor.
- **Free text** lives where it is produced: `qc_reports.remarks`, `temperature_logs.note` and `customer_complaints.complaint_text`, each with a GIN full-text index at its own source.
- **All data is derived** from the rows already in each database, so the scripts work on every team member's copy.

The demo story planted in the data affects **one** batch or shipment each, so other batches of the same medicine stay clean:
- The **Ibuprofen batch of ITEM000041** failed its assay and was *released after retest*. If ITEM000041 doesn't exist, the earliest Ibuprofen batch is used.
- That batch was made at Sunrise's Unit 2, whose GMP certificate expired on 30 Jun 2026.
- The shipment carrying ITEM000041 had a broken carton seal, and the shipment carrying ITEM000035 had a 34.5 °C excursion.
- CityCare customers complained about crumbly tablets with no hologram.
- The **Amoxicillin batch of ITEM000035** failed dissolution, with complaints that the capsules were sticky.

The actual batch numbers depend on your data. Each source stores them in `asli_ctx.demo_story`; the document loader prints them and fills them into the demo documents. To see them:
```sql
SELECT * FROM p3_demo_story();   -- on the mediator
```

**Live rows get context too.** Triggers on `manufactured_items`, `supplied_items`, `vendor_inventory` and `medicine_sales` link every new row to a batch, shipment, bill or customer, creating it if needed. A linking error is only a warning and never blocks the insert.

**The Phase 2 cleansing fix scripts still work.** All new foreign keys cascade, so deleting a duplicate stock record or a look-alike medicine copy also removes or moves its Phase 3 rows.

## How context discovery works (at each source)

`asli_ctx.discover(seeds, depth 3, max_rows 40)`:
- **Seeds enter** through `asli_ctx.entry_points`:
  - item codes, matched by folded code (noisy codes work);
  - batch numbers, matched exactly;
  - names, matched by substring;
  - free-text words, matched by full-text search on the text columns.
- **Foreign keys are followed both ways** (child → parent, and parent → child capped at 10 per row), up to 3 steps. The graph comes from `pg_constraint`, so a new table with a foreign key is picked up automatically.
- **Relevance:**
  - a seed row = seed weight × entry weight;
  - each FK step × 0.6 × the weight of the table reached;
  - a row reached from several parts of the query combines them with noisy-OR, so it ranks above a row only one part leads to. This is what keeps the context *highly related to the query*.
- **Explosion control** (needed for production-size data):
  - never walk straight back down the FK just climbed;
  - hub tables (manufacturers, distributors, vendors) are opened downwards only when the user named the hub, never from a key derived by the mediator;
  - fan-out cap per row, a minimum relevance, and a row limit.

## How federation works (mediator)

`p3_run(question, fields)` does the following:
1. `p3_parse` extracts the seeds.
2. Round 1 sends `asli_ctx.discover` to every enabled source with `dblink_send_query`, then collects the results. The sources work in parallel.
3. Keys from the answers (`p3_links`) become round-2 seeds, sent only to the source they point to and never sent twice.
4. Every call is logged in `p3_source_calls` with seeds, rows, milliseconds, status and error, and every context row is stored in `p3_context`.
5. A source that is down or slower than `p3_timeout_ms` is skipped and shown as ERROR / TIMEOUT. The answer is built from the others; this was tested by pointing the distributor at a non-existent server.

## The item check (Phase 1 + 2 inside Phase 3)

Every item code in the question goes through the same rules as the Verify page:
- `search_by_pack` (noisy code matching) → UNKNOWN CODE, CLONED CODE, PACK MISMATCH, WRONG CODE or AMBIGUOUS.
- `verify_item` → UNAPPROVED, EXPIRED, DISTRIBUTOR MISMATCH or SUPPLY GAP.
- `p3_item_batch` → the item's **own** batch. With a batch number from the pack, it also gives BATCH MISMATCH.

Signals about other batches, plants, shipments or stock records of the same medicine are shown as *context only*. They never decide the level.

The answer then gives **one combined verdict** with a problem type: COUNTERFEIT, UNAPPROVED, EXPIRED, SUBSTANDARD BATCH, TRANSPORT DAMAGE, SUPPLY CHAIN, OUTSIDE REPORTS or CUSTOMER COMPLAINTS. Example: *"The code is genuine (ITEM000041), but: SUBSTANDARD BATCH + TRANSPORT DAMAGE"*. So Verify and Phase 3 never contradict each other without saying why.

## How the documents are searched

`p3_search_documents(query_id, text, query_embedding)`. The terms are the context terms (`p3_context_terms`) plus the free-text words of the question.
- **Full-text score:** sum of term weight × `ts_rank_cd`.
- **Semantic score:** cosine between embeddings. With `sentence-transformers` (all-MiniLM-L6-v2) installed, that model is used. Otherwise LSA (TF-IDF + SVD) is fitted on the documents; it needs no download.
- **Entity bonus:** +0.15 per exact mention of the case's batch, item code, shop, maker or certificate (at most 3).
- **Score** = 0.55 × saturated full-text + 0.30 × cosine + entity bonus, capped at 1. Documents below 0.30 are not shown, so *"Vitamin C 500mg"* returns no documents instead of unrelated ones.
- **Generic names:** each medicine term also searches its generic name ("Paracetamol 500mg" → *paracetamol*), because outside alerts never repeat our pack wording.
- **Real sources kept visible:** of the 8 documents shown, up to 2 places go to real (non-demo) documents that matched. Otherwise the demo documents, which name our own shops and batches, would always push them out.
- **As a risk signal**, a document counts against a specific item only if it names the item's own batch or code (or its own shop) **and** the medicine. Without an item, it counts only if the question's medicine appears in a sentence that reports a problem (*not of standard quality, recall, spurious, excursion…*). *"Telmisartan 40mg: of standard quality"* or *"out of stock"* is information. A document that only names the company is information. Documents older than 2 years count one level less.

**Corpus** (`corpus/documents.json`, 51 documents):
- **26 REAL** public documents, summarised in our own words, each with its URL:
  - WHO alerts: falsified amoxicillin, propylene glycol, the 2025 DEG cough-syrup deaths, falsified SIMULECT, and the "1 in 10" study.
  - CDSCO / state monthly alerts from Aug 2024 to Sep 2026. They name paracetamol, pantoprazole, telmisartan, cefixime, metformin, montelukast, levocetirizine and others, and include the spurious Shelcal 500, Pan D and Telma.
  - The Schedule H2 QR-code rules.
  - US FDA recalls: metformin NDMA and losartan NDEA.
  - Counterfeit busts in Delhi, Pune and Hyderabad, and an unlicensed pharmacy raid in Delhi.
  - Drug labels for ibuprofen, amoxicillin, paracetamol, metformin and azithromycin.
- **25 SYNTHETIC** documents marked **[Demo]**, tied to our own rows:
  - the batch alert, inspection and GMP suspension of Sunrise Unit 2;
  - the amoxicillin recall and lab failure;
  - the broken-seal audit and the excursion quarantine (they name the shipment numbers and vehicle DL1LB1037);
  - fake item codes at Wellness Pharmacy (ITEM583920);
  - a Hinglish consumer post;
  - **negative controls** that must NOT raise risk: a passed lab report, a new pack design, a cold-room audit, a price notice and a refund notice.

To add documents, append to the JSON file and re-run the indexer.

## Install (in this order)

| # | Machine | Run | Expect |
|---|---|---|---|
| 0 | all | backups, as before | |
| 1 | manufacturer | `sources/asli_ctx_core.sql`, then `sources/manufacturer_07_tables.sql` | first line `running_on = manuf_db`; 7 tables with row counts; 2 demo-story rows |
| 2 | distributor | `sources/asli_ctx_core.sql`, then `sources/distributor_07_tables.sql` | `running_on = distributor_db`; 7 tables; 2 demo-story rows |
| 3 | vendor | `sources/asli_ctx_core.sql`, then `sources/vendor_07_tables.sql` | `running_on = vendor_db`; 8 tables |
| 4 | mediator | `mediator/mediator_07_federated_context.sql` | 4 checks PASS (a FAIL names the source that did not answer) |
| 4b | mediator | `phase2_update/mediator_03_candidate_search.sql` (= phase2/step3, updated: Verify about 5× faster) | 8 checks PASS (4–6 may SKIP) |
| 5 | mediator | `mediator/mediator_08_documents.sql` | — |
| 6 | GUI machine | `pip install -r app/requirements.txt`, then `cd app` and `python phase3_index_documents.py` | "Demo story from the sources: …" then "Loaded 51 document(s) … embedded with …" |
| 7 | GUI machine | `cd app` and `streamlit run gui.py` | sidebar with two groups: *Phase 3 · Context → Documents* and *Phase 1–2 · Verify & matching* |

**Already installed the first version?** Run steps 1–6 again in the same order. Every script upgrades an existing install: it changes the foreign keys, keeps the story to one batch and adds the triggers. Re-running the loader (step 6) puts the real batch numbers into the documents.

Notes:
- Each source receives only its own script and the shared engine file, never another source's data.
- **Run each source script in the right database** (`manuf_db`, `distributor_db`, `vendor_db`), not in the default `postgres` database. The first result line shows where it ran.
- `dblink` is included with PostgreSQL 10 and later, so nothing needs installing. It reuses the existing foreign servers and user mappings, so there is no new password or connection setup. Step 4 also adds a 3-second `connect_timeout` to those servers, so a laptop that is off the network is skipped quickly.
- Steps 1–3 need the step 6 extension `asli_match` (for `asli.fold`), which is already installed.
- **Optional AI answer:** set `ANTHROPIC_API_KEY` (and optionally `ASLI_LLM_MODEL`) before `streamlit run`. Without it, a rule-based answer is shown.
- **Optional better embeddings:** `pip install sentence-transformers`, then re-run the indexer.
- **Connection settings:** `app/asli_db.py`, or the environment variables `ASLI_DB_HOST`, `ASLI_DB_PASSWORD`, …

## Demo script (viva)

First run `SELECT * FROM p3_demo_story();` on the mediator. Below, "the Ibuprofen batch" and "the Amoxicillin batch" mean the values it shows.

1. **Ask tab → "Is Ibuprofen from Sunrise sold at CityCare safe?"** → HIGH RISK.
   - *Federation:* round 1 sends 3 word seeds (`citycare`, `ibuprofen`, `sunrise`) to 3 machines (≈0.1 s). In round 2:
     - the distributor receives `distributor_id: 1` and `vendor_name: CityCare Medical Store`, found by the vendor;
     - the vendor receives item codes `ITEM000041…45`, found by the manufacturer and distributor;
     - the manufacturer receives the item codes found at the distributor and vendor.
   - *Step ③:* one card per database (rows found, tables), the keys passed in round 2, and the FK paths, e.g. `manufactured_items → batch_items → production_batches → qc_reports`.
   - *Step ④:* the [Demo] state alert naming the Ibuprofen batch ranks first. Its card says "Matched because it mentions <your batch> from manufacturer.production_batches": that batch number was **not in the question**, it came from the manufacturer's context.
2. **`ITEM000035`** → the item check shows its own batch (the Amoxicillin batch) → the recall notice for that batch ranks first. The verdict also lists any Phase 1 problem (e.g. EXPIRED).
2b. **`ITEM000041`** → "The code is genuine (ITEM000041), but: SUBSTANDARD BATCH + …": a genuine pack from a bad batch, not a counterfeit. Ask about **another Ibuprofen item from a different batch**: its QC is clean, and the failing batch appears only as context.
2c. **A code no manufacturer made, but a shop holds** (e.g. ITEM583920 in our live-noise data) → **HIGH RISK — COUNTERFEIT**.
3. **"Customer says the tablets are crumbly and there is no hologram"** → full-text search at the vendor finds the complaint → its FK path leads to the item → the context finds the batch → the alert and the pharmacovigilance documents follow.
4. **"Tell me about Vitamin C 500mg"** → context found, no risk signal, no documents → NO RED FLAGS FOUND; the only document is a refund notice shown as information (a negative result is also an answer).
5. **Verify page** → verify `ITEM0O0O41` with the bill.
   - Add a **wrong batch number**: you get "this item code belongs to batch …".
   - Choose **Other shop**: you get "not a registered pharmacy".
   - At the end, click *Find context and documents for this item*.
6. **Source down:** in the mediator run `UPDATE p3_endpoints SET enabled = false WHERE source_id = 'distributor';` and ask again. The answer still comes from the other two; set it back to `true` afterwards.
7. **Databases & FK links page** → every machine's tables with row counts (NEW = Phase 3), the FK graph, and the keys that connect the databases.
8. **Prompt & code page** → the prompt, the changed lines per file, and a diff of generated vs our code.

## Scale notes

- **The mediator never reads a source table.** Each source runs its own indexed lookups and returns at most `p3_rows_per_source` rows per round. Adding a source = a row in `asli_sources` + `p3_endpoints` + its `asli_ctx` config.
- **Document vectors** are `real[]` with an SQL cosine. For millions of documents, install pgvector and replace the `sem` CTE in `p3_search_documents` with an HNSW index scan; nothing else changes.
- **Configuration is data, not code.** All weights, limits and rules live in tables: `match_config` `p3_*`, `asli_ctx.settings`, `p3_links`, `p3_signal_rules` and `p3_term_columns`.
