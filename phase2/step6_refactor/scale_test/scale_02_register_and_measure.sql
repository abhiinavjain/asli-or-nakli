-- =====================================================================
-- Asli-or-Nakli · OPTIONAL scale test · RUN ON: mediator_db (Alt+X)
-- Registers scale_db as a 4th source (one INSERT into the registry; no function
-- changes), measures a probe, then switches the source off again.
-- Edit host / port / user / password below to where scale_db lives.
-- =====================================================================
DROP SERVER IF EXISTS scale_server CASCADE;
CREATE SERVER scale_server FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (dbname 'scale_db', host 'localhost', port '5432',
             extensions 'asli_match', use_remote_estimate 'true', fetch_size '25');
CREATE USER MAPPING FOR CURRENT_USER SERVER scale_server OPTIONS (user 'postgres', password 'postgres');
DROP SCHEMA IF EXISTS scale CASCADE;
CREATE SCHEMA scale;
IMPORT FOREIGN SCHEMA public LIMIT TO (vendor_inventory, vendors) FROM SERVER scale_server INTO scale;

-- the new source: same probe as vendor_db, pointed at the scale tables
INSERT INTO public.asli_sources (source_id, kind, enabled, description, probe_sql)
SELECT 'scale_vendor', 'VENDOR', true, 'synthetic shop with 1,000,000 records (scale test)',
       replace(replace(replace(probe_sql, 'public.vendor_inventory', 'scale.vendor_inventory'),
                       'public.vendors', 'scale.vendors'), '''vendor''', '''scale_vendor''')
FROM public.asli_sources WHERE source_id = 'vendor'
ON CONFLICT (source_id) DO UPDATE SET probe_sql = EXCLUDED.probe_sql, enabled = true;

-- 1. noisy code against 1,000,000 records: at most k rows come back
SELECT stored_code, hit, pre_dist
FROM public.asli_probe('ITEM0O41234', NULL, NULL, ARRAY['VENDOR'])
WHERE source_id = 'scale_vendor' ORDER BY pre_dist;
-- expect 5 rows: ITEM0041234 (0.25) first, then 4 codes at 0.75 (one error away)

-- 2. timing (look at "Execution Time")
EXPLAIN ANALYZE SELECT * FROM public.asli_probe('ITEM0574321', NULL, NULL, ARRAY['VENDOR']);

-- 3. switch the test source off so normal demos are unaffected
UPDATE public.asli_sources SET enabled = false WHERE source_id = 'scale_vendor';
