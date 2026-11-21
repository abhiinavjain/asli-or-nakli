-- =====================================================================
-- Asli-or-Nakli · demo-day smoke test · RUN ON THE MEDIATOR (mediator_db)
-- Run AFTER all three source laptops passed source_smoke_test.sql.
-- DBeaver: Alt+X. Sections 1-4 are read-only; section 5 writes only to
-- the p3_* audit tables (same as asking a question in the GUI).
-- =====================================================================

-- 1. Basics
SELECT current_database() AS running_on;                              -- mediator_db
SELECT extname, extversion FROM pg_extension WHERE extname IN ('dblink', 'asli_match');

-- 2. Where does the mediator think each laptop is? (check IPs against today's ipconfig / ip a)
SELECT srvname, srvoptions FROM pg_foreign_server ORDER BY srvname;
SELECT * FROM asli_sources ORDER BY source_id;                        -- all enabled = true
SELECT * FROM p3_endpoints ORDER BY source_id;                        -- all enabled = true

-- 3. Is every laptop answering right now? (a WARNING line names any laptop that is not)
SELECT source_id, count(*) AS tables, sum(row_count) AS total_rows
FROM p3_source_tables() GROUP BY source_id ORDER BY source_id;         -- distributor 7 · manufacturer 7 · vendor 8
SELECT * FROM p3_demo_story();                                        -- note the Ibuprofen + Amoxicillin batch numbers

-- 4. Phase 1/2 path still works (step 6 probe)
SELECT source_id, hit, count(*) FROM asli_probe('ITEM000150') GROUP BY 1, 2 ORDER BY 1, 2;   -- all 3 sources, each <= 5
SELECT source_id, stored_code, hit, pre_dist FROM asli_probe('ITEM0O0041') ORDER BY pre_dist;

-- 5. Phase 3 end to end (two statements: run, then read the audit)
SELECT p3_run('Is Ibuprofen from Sunrise sold at CityCare safe?') AS query_id;

SELECT round, source_id, status, rows_back, elapsed_ms, error
FROM p3_source_calls
WHERE query_id = (SELECT max(query_id) FROM p3_queries)
ORDER BY round, source_id;            -- round 1: 3 × OK · round 2: OK / SKIPPED (no ERROR / TIMEOUT)

SELECT rule_id, severity, source_id, message
FROM p3_signals((SELECT max(query_id) FROM p3_queries))
ORDER BY severity DESC;               -- QC_FAIL, GMP_EXPIRED, TEMP/TRANSPORT, COMPLAINT

SELECT * FROM p3_context_terms((SELECT max(query_id) FROM p3_queries), 10);   -- the batch number appears here

-- 6. Documents loaded and embedded (run the indexer again if count = 0 or model is NULL)
SELECT count(*) AS documents, count(embedding) AS embedded, max(embedding_model) AS model FROM p3_documents;

-- 7. Timing guard: how long did the last few questions take?
SELECT query_id, left(query_text, 50) AS q, rounds_run, context_rows, elapsed_ms
FROM p3_queries ORDER BY query_id DESC LIMIT 5;                        -- each well under p3_timeout_ms (8000)
