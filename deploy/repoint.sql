-- Run on mediator_db after the restore (restore.sh does this).
-- Points manufacturer_server / distributor_server / vendor_server at the containers
-- instead of the old laptop IPs. dblink (Phase 3) connects through the same
-- servers, so this fixes both postgres_fdw and dblink.
-- Needs:  psql -v pw=<PG_PASSWORD>

SELECT set_config('asli.pw', :'pw', false) IS NOT NULL AS password_set;

CREATE OR REPLACE FUNCTION pg_temp.set_opt(p_target text, p_opt text, p_val text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    -- ADD the option if missing, SET it if present
    EXECUTE format('ALTER %s OPTIONS (ADD %I %L)', p_target, p_opt, p_val);
EXCEPTION WHEN duplicate_object THEN
    EXECUTE format('ALTER %s OPTIONS (SET %I %L)', p_target, p_opt, p_val);
END $$;

DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM (VALUES ('manufacturer_server', 'manufacturer', 'manuf_db'),
                                   ('distributor_server',  'distributor',  'distributor_db'),
                                   ('vendor_server',       'vendor',       'vendor_db')) v(srv, host, db) LOOP
        PERFORM pg_temp.set_opt(format('SERVER %I', r.srv), 'host',   r.host);
        PERFORM pg_temp.set_opt(format('SERVER %I', r.srv), 'port',   '5432');
        PERFORM pg_temp.set_opt(format('SERVER %I', r.srv), 'dbname', r.db);
    END LOOP;

    FOR r IN SELECT srvname, usename FROM pg_user_mappings
             WHERE srvname IN ('manufacturer_server', 'distributor_server', 'vendor_server') LOOP
        PERFORM pg_temp.set_opt(format('USER MAPPING FOR %s SERVER %I',
                                       CASE WHEN r.usename = 'public' THEN 'PUBLIC' ELSE quote_ident(r.usename) END,
                                       r.srvname), 'user', 'postgres');
        PERFORM pg_temp.set_opt(format('USER MAPPING FOR %s SERVER %I',
                                       CASE WHEN r.usename = 'public' THEN 'PUBLIC' ELSE quote_ident(r.usename) END,
                                       r.srvname), 'password', current_setting('asli.pw'));
    END LOOP;
END $$;

-- Check: every source answers through dblink and postgres_fdw
SELECT srvname, srvoptions FROM pg_foreign_server
WHERE srvname IN ('manufacturer_server', 'distributor_server', 'vendor_server');
SELECT kind, count(*) AS candidates FROM public.asli_probe('ITEM000001') GROUP BY kind ORDER BY kind;

-- ---------------------------------------------------------------------
-- The manufacturer database is now called manuf_db.
-- The mediator's Phase 2 cleansing code uses the database name as a label
-- (target_db, fix-script names, asli_sources description). The dump still
-- has 'manufacturer_db', so rewrite it: every function that mentions it is
-- re-created with the new name, and stored rows are updated.
-- ---------------------------------------------------------------------
DO $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN SELECT p.oid FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
             WHERE ns.nspname NOT IN ('pg_catalog', 'information_schema')
               AND p.prokind IN ('f', 'p') AND p.prosrc LIKE '%manufacturer_db%' LOOP
        EXECUTE replace(pg_get_functiondef(r.oid), 'manufacturer_db', 'manuf_db');
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'functions renamed to manuf_db: %', n;

    IF to_regclass('public.cleansing_proposals') IS NOT NULL THEN
        UPDATE public.cleansing_proposals SET target_db = 'manuf_db' WHERE target_db = 'manufacturer_db';
    END IF;
    IF to_regclass('public.cleansing_log') IS NOT NULL THEN
        UPDATE public.cleansing_log SET target_db = 'manuf_db' WHERE target_db = 'manufacturer_db';
    END IF;
    IF to_regclass('public.asli_sources') IS NOT NULL THEN
        UPDATE public.asli_sources SET description = replace(description, 'manufacturer_db', 'manuf_db')
        WHERE description LIKE '%manufacturer_db%';
    END IF;
END $$;
