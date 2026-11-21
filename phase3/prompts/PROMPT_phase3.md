# Prompt used to generate Phase 3

*Attached with the prompt: the Phase 2 project (the four database dumps, the step 1–6 SQL scripts, `gui.py`) and the professor's Phase 3 rubric.*

---

You are extending our academic project **Asli-or-Nakli**, which checks whether a medicine is genuine.

**Setup.** Three independent PostgreSQL databases run on three different laptops:
- `manufacturer_db`: manufacturers, medicines, manufactured_items
- `distributor_db`: distributors, inventory_items, supplied_items
- `vendor_db`: vendors, vendor_inventory, medicine_sales

A fourth laptop runs `mediator_db`. It reaches the three through `postgres_fdw`, and Phase 2 added the `asli_match` extension and a source registry (`asli_sources`). The GUI is one Streamlit file, `gui.py`.

**Phase 3 rubric (from the professor).** Seamless integration of unstructured data with structured query results:
1. Expand each database to at least 4–5 tables, so that entity information is spread over several tables joined by FK → PK. *(2 marks)*
2. Discover the context from the query results and beyond across databases by exploiting the FK–PK relationships. *(3 marks)*
   - The database instances run on different machines.
   - The user (sub)query is federated to these databases, and each database discovers the context.
   - The overall context must be highly related to the user query.
3. Using the query context, search unstructured data that is highly correlated to it, and integrate it. *(3 marks)*
4. Show the prompt, the generated code and our modified code. *(2 marks)*

**Our decisions:**
- Real + synthetic documents. Real public documents are summarised in our own words with their URL. Synthetic ones are clearly marked as fictional demo data.
- `dblink` is allowed, for truly parallel federated sub-queries.
- Semantic search is allowed (embeddings), together with full-text search.
- An LLM summary is allowed, with a fallback when no API key is set.
- Users ask in two ways: a free-text question tab, and the existing Verify flow gets context and documents automatically.
- **New tables only.** No existing table, column or constraint may change; the Phase 1 and 2 code must keep working.
- Each owner runs scripts only on their own machine. A source must not receive another source's data files.
- It must be production quality and scale to many sources and large tables: no full-table reads by the mediator, and graceful handling of a source that is down.

## Build

1. **Per source, `<source>_07_tables.sql`.**
   - Add 3–4 new tables with FK → PK links into the existing ones. Use link tables where an existing table would otherwise need a new column.
   - Fill them deterministically from the rows already in that database, so the script works on any copy.
   - Include free-text columns (QC remarks, transport notes, customer complaints) and plant a small, consistent demo story: a failed QC batch, an expired GMP certificate, a temperature excursion, a broken seal, and complaints.
2. **Per source, `asli_ctx_core.sql` (the same file on all three).** A schema `asli_ctx` with `discover(seeds jsonb, depth, max_rows)`. It must:
   - walk the database's own FK graph, read from `pg_constraint` and not hard-coded;
   - start from seeds (item code, batch, names, free-text words) through a small config table of entry points;
   - score relevance with a decay per FK step, combining seeds with noisy-OR;
   - control explosion: no immediate backtracking, no downward expansion of hub tables unless the user named the hub, and a fan-out cap.
   Also add a local full-text search over the source's own text columns.
3. **Mediator, `mediator_07_federated_context.sql`.** It needs:
   - `p3_parse(text, fields)` → seeds;
   - `p3_discover` → round 1 sends the sub-query to every source in parallel with `dblink_send_query`. Round 2 turns the cross-database keys found in the answers (a registry `p3_links`) into new seeds, sent only to the source they point to;
   - per-source timeouts and error logging;
   - audit tables (`p3_queries`, `p3_source_calls`, `p3_context`);
   - context → weighted search terms;
   - data-driven risk rules (`p3_signal_rules`).
4. **Mediator, `mediator_08_documents.sql`.** A documents table with a generated `tsvector` and an embedding column. The hybrid search uses the query context, not just the user's words: weighted full-text, cosine on embeddings, and a bonus for exact mentions of the case's entities. Scores are absolute, so a weak match stays weak.
5. **Python.**
   - An indexer that loads `documents.json` and embeds it: sentence-transformers if installed, otherwise LSA fitted on the corpus.
   - An orchestrator that runs one query end to end and returns context, documents, signals and an assessment.
   - An LLM summary that cites `[C#]`, `[S#]` and `[D#]` tags.
6. **GUI.**
   - A tab "Ask across databases" showing the assessment, the answer, the federation (seeds, calls per round, timings, graph), the context per source with its FK paths (graph), the documents with score breakdown, the signals and the search terms. It also shows the live schema graph of every source.
   - A Phase 3 panel at the end of Verify.
   - A "Prompt & code" tab that shows this prompt and a diff of generated versus modified code.

Comment every section so team members can explain it in the viva. All SQL must use parameters, and every database call must fail with a clear message instead of crashing the page.
