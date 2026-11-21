# Asli-or-Nakli · Demo-day runbook (Phase 3 final evaluation)

The TA will hand us a **live query** and mark it. This runbook gets all four laptops up, proves they talk to each other, and rehearses the kinds of query the TA is likely to give.

Smoke tests: `demo_check/source_smoke_test.sql` (each source laptop) and `demo_check/mediator_smoke_test.sql` (mediator).

---

## 0. Network first (most demo failures are here, not in SQL)

| # | Check | Why |
|---|---|---|
| N1 | All 4 laptops on the **same network**. Keep a **phone hotspot** ready as plan B. | Campus Wi-Fi often isolates clients from each other. |
| N2 | Write today's IPs on paper: Linux `ip a` (manufacturer), and on the three WSL laptops **both** the Windows IP (`ipconfig`) and the WSL IP (`hostname -I` inside WSL). | IPs change between days and networks. |
| N3 | **WSL laptops (distributor, vendor, mediator):** the WSL IP changes on every restart. Re-do the port forward, as admin in PowerShell: `netsh interface portproxy delete v4tov4 listenport=5432 listenaddress=0.0.0.0` then `netsh interface portproxy add v4tov4 listenport=5432 listenaddress=0.0.0.0 connectport=5432 connectaddress=<WSL IP>`. (Not needed if WSL uses `networkingMode=mirrored`.) | Commonest "it worked yesterday" bug. |
| N4 | Windows Firewall: inbound TCP 5432 allowed (on the network profile in use, Public or Private). Linux: `sudo ufw allow 5432/tcp` if ufw is on. | |
| N5 | From the mediator: `psql -h <source IP> -U <user> -d <source>_db -c "select 1"` for each source. | Proves the network before PostgreSQL-level checks. |
| N6 | If an IP changed, update the mediator's foreign servers: `ALTER SERVER manufacturer_server OPTIONS (SET host '<new IP>');` (same for `distributor_server`, `vendor_server`). | dblink and Phase 1/2 foreign tables both use these. |
| N7 | Turn off sleep / lid-close-sleep on every laptop. Plug in chargers. | A sleeping laptop looks like TIMEOUT. |

## 1. Start everything (in this order)

1. **Each source laptop:** start PostgreSQL (`sudo service postgresql start` in WSL / Linux). Open DBeaver **on the right DB**, run `source_smoke_test.sql`. Expect: right `running_on`, asli_match 1.0, 7 / 7 / 8 tables, discover returns rows, `listen_addresses = *`, a pg_hba `host` line for the mediator's IP.
2. **Mediator:** run `mediator_smoke_test.sql`. Expect: all 3 sources in `p3_source_tables()` (no WARNING), probe shows all 3, `p3_run` round 1 = 3 × OK, signals present, 51 documents embedded.
3. **GUI machine:** `cd phase3/app`, set `ANTHROPIC_API_KEY` if we use the AI answer (else rule-based answer, also fine), `streamlit run gui.py`. Ask the Ibuprofen/Sunrise/CityCare question → HIGH RISK.
4. Note the batch numbers from `SELECT * FROM p3_demo_story();` on paper. The TA may ask "where did that batch number come from?"
5. **Take fresh backups** of all four DBs now (`pg_dump -Fc`), so live edits can be undone in a minute.

## 2. Live query bank: rehearse these before the TA arrives

Run each one once. Tick it off if the result matches.

### A. Questions in the Ask tab (Phase 3)

| # | Query | Expected |
|---|---|---|
| A1 | Is Ibuprofen from Sunrise sold at CityCare safe? | HIGH RISK · round 2 passes keys between DBs · [Demo] documents naming the Ibuprofen batch rank first (the batch was **not** in the question) |
| A2 | ITEM000035 | own batch = Amoxicillin batch · lab failure, quarantine and recall notices first · plus any Phase 1 problem (e.g. EXPIRED) |
| A3 | ITEM000041 | "The code is genuine (ITEM000041), but: SUBSTANDARD BATCH + …" · broken-seal audit names its shipment and the vehicle DL1LB1037 |
| A4 | another Ibuprofen item from a **different** batch | QC clean; the failing batch shows only as context |
| A5 | ITEM583920 | HIGH RISK — COUNTERFEIT (shop holds it, no manufacturer made it) · [Demo] news about fake codes at Wellness Pharmacy |
| A6 | Customer says the tablets are crumbly and there is no hologram | vendor full-text hit on the complaint → item → batch → documents |
| A7 | Tell me about Vitamin C 500mg | NO RED FLAGS FOUND · only a refund notice, shown as information |
| A8 | **Noisy / Hinglish / casual** versions: `kya ITEM0O0041 asli hai?`, `itm-000-041`, `is amoxicillin from sunrise ok`, `ibuprofen ki goli kaam nahi kar rahi CityCare` | still parsed (stop words + look-alike folding); the Hinglish forum post is found |
| A9 | a batch number typed directly (from `p3_demo_story`) | batch seed → plant, QC, items, shipments |
| A10 | a shop name alone: `CityCare` | vendor context + distributor shipments to it in round 2 |
| A11 | Telmisartan 40mg fake? | NO RED FLAGS FOUND · real CDSCO alert about spurious Telma shown as **information** (not our batch) · [Demo] passed lab report |
| A12 | Is ORS Powder safe? | NO RED FLAGS FOUND · ORS campaign notice only |
| A13 | Is metformin safe? | real FDA NDMA recall and MedlinePlus label appear beside the demo documents |

### B. Verify page (Phase 1 + 2 inside Phase 3)

| # | Input | Expected |
|---|---|---|
| B1 | ITEM0O0041 + Ibuprofen 400mg + bill | MATCH → ITEM000041 |
| B2 | same + **wrong batch number** | "this item code belongs to batch …" |
| B3 | same + shop = Other shop | "not a registered pharmacy" |
| B4 | ITEM000106 · Amoxicillin 500mg · Sunrise · 12/2029 | POSSIBLE CLONED CODE |
| B5 | ITEM000910 (code only) | REVIEW, nothing reported until a pick |
| B6 | ZZZ-998877 | NO MATCH · Report works |
| B7 | then click *Find context and documents for this item* | jumps into the Phase 3 answer |

### C. Live SQL edits the TA may make, then ask about

| # | Edit (on the source laptop) | Then | Expected |
|---|---|---|---|
| C1 | manufacturer: `INSERT INTO manufactured_items (medicine_code, unique_item_code, manufacturing_date, expiry_date) VALUES ('MED030','ITEM0003O0',DATE '2025-12-21',DATE '2027-12-21');` | Ask `ITEM0003O0` | trigger links it to a batch (no error); context found; Phase 2 sees a look-alike of ITEM000300 |
| C2 | vendor: L11 insert (clean ITEM000008 record, see TEST_CASES_v4) | Verify / Ask ITEM000008 | GENUINE (was VENDOR RECORD NOT FOUND); trigger links it to a bill |
| C3 | manufacturer: `UPDATE manufactured_items SET expiry_date = DATE '2026-06-30' WHERE unique_item_code = 'ITEM000026';` | Ask ITEM000026 | EXPIRED in the verdict |
| C4 | vendor: `DELETE FROM vendor_inventory WHERE item_identifier='ITEM000010';` | Ask ITEM000010 | VENDOR RECORD NOT FOUND (new FKs cascade, no FK error) |
| C5 | mediator: `UPDATE p3_endpoints SET enabled = false WHERE source_id = 'distributor';` | Ask A1 again | answer from the other two; set back to `true` |
| C6 | physically stop PostgreSQL on one laptop (`sudo service postgresql stop`) | Ask A1 | that source shows ERROR/TIMEOUT within ~3 s, answer still built; restart it |
| C7 | mediator: change a weight, e.g. `UPDATE match_config SET value = 1 WHERE key = 'p3_rounds';` | Ask A1 | no round 2 → fewer context rows, batch may not reach the documents; set back to 2 |
| C8 | add a document live: append one object to `corpus/documents.json` (or a new JSON file), then `python phase3_index_documents.py my_doc.json` | Ask about the medicine / shop it names | the new document appears with "Matched because it mentions …" |

Do C1–C4 inside a transaction during rehearsal (`BEGIN; … ; ROLLBACK;`) or restore from the backup after.

### D. "Show me" questions (rubric evidence)

- **Databases & FK links page:** 7 / 7 / 8 tables with row counts, NEW tags, FK graph, cross-DB keys (`SELECT * FROM p3_links;`).
- **Federation audit for the last query:** `SELECT * FROM p3_source_calls WHERE query_id = (SELECT max(query_id) FROM p3_queries);`
- **Documents:** `SELECT origin, doc_type, count(*) FROM p3_documents GROUP BY 1, 2 ORDER BY 1, 2;` (26 REAL with URLs, 25 [Demo]).
- **Prompt & code page:** prompt, generated vs modified diff, `prompts/MODIFICATIONS.md`.

## 3. If something breaks during the demo

| Symptom | Fix |
|---|---|
| WARNING "source X did not answer" / TIMEOUT | Check that laptop's IP (N2), portproxy (N3), firewall (N4), `ALTER SERVER … SET host` (N6). Meanwhile, demo with the other two: that is itself the "source down" feature. |
| `could not connect` right after a laptop reboot | WSL IP changed → N3. |
| Source script results look empty | DBeaver connected to `postgres`, not `<source>_db`. |
| No documents in the answer | `SELECT count(*) FROM p3_documents;` = 0 → re-run `python phase3_index_documents.py`. |
| Batch numbers in documents don't match | Re-run the indexer (it refills the placeholders from `p3_demo_story`). |
| New documents don't show after re-indexing | Restart Streamlit: the search model is cached per process. |
| AI answer errors | Unset `ANTHROPIC_API_KEY` and restart Streamlit: the rule-based answer is shown. |
| A live edit left a mess | Restore that DB from this morning's `pg_dump`. |

## 4. How to handle an unseen live query

1. Type it **as given** first. Don't rephrase it before the TA has seen what the system does.
2. Walk the TA through the steps in order: **seeds parsed → round 1 on 3 laptops → keys passed in round 2 → FK paths → search terms → documents → verdict**.
3. If the result is surprising, open the Federation/Context tabs and show *why*. A sensible NO RED FLAGS result with an explanation also counts as an answer.
