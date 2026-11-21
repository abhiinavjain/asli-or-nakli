-- =====================================================================
-- Asli-or-Nakli · demo-day smoke test · RUN ON EACH SOURCE LAPTOP
--   manufacturer laptop -> manuf_db
--   distributor laptop  -> distributor_db
--   vendor laptop       -> vendor_db
-- Read-only. DBeaver: Alt+X (each statement gets its own result tab).
-- =====================================================================

-- 1. Am I in the right database? (must NOT say postgres)
SELECT current_database() AS running_on, version();

-- 2. Shared extension present, same version as the mediator (1.0)
SELECT extname, extversion FROM pg_extension WHERE extname IN ('asli_match', 'plpgsql');

-- 3. Phase 3 engine installed
SELECT count(*) AS tables_in_ctx_schema FROM asli_ctx.v_schema;      -- manufacturer 7 · distributor 7 · vendor 8
SELECT count(*) AS fk_edges             FROM asli_ctx.fk_edges;      -- > 0
SELECT * FROM asli_ctx.demo_story;                                    -- manufacturer + distributor: 2 rows each

-- 4. Context discovery works locally (this is exactly what the mediator calls)
SELECT table_name, count(*) AS rows_found, max(relevance) AS best
FROM asli_ctx.discover('[{"kind":"text","value":"ibuprofen","weight":0.7}]'::jsonb, 3, 40)
GROUP BY table_name ORDER BY best DESC;                               -- several tables, not 0 rows

SELECT table_name, count(*) AS rows_found
FROM asli_ctx.discover('[{"kind":"item_code","value":"ITEM0O0041","weight":1.0}]'::jsonb, 3, 40)
GROUP BY table_name;                                                  -- noisy code still finds rows

-- 5. The mediator can reach this laptop
SHOW listen_addresses;                                                -- must be '*' (or include this laptop's LAN IP)
SHOW port;                                                            -- usually 5432
SELECT inet_server_addr() AS server_ip;                               -- NULL if you connected via socket/localhost; fine
-- pg_hba rules (needs superuser): there must be a 'host' line that allows the mediator's IP
SELECT line_number, type, database, user_name, address, netmask, auth_method
FROM pg_hba_file_rules WHERE type = 'host' ORDER BY line_number;
