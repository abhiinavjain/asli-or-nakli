-- =====================================================================
-- Asli-or-Nakli · Phase 3 · Context discovery engine (runs AT each source)
-- RUN ON: manuf_db, distributor_db AND vendor_db (the same file on all three),
--         BEFORE <source>_07_tables.sql.   DBeaver: Alt+X.  Safe to re-run.
-- =====================================================================
--
-- The mediator sends each source a sub-query: a few SEEDS taken from the user's
-- query (an item code, a medicine name, a shop, a batch number, free-text words).
-- The source answers with the CONTEXT around those seeds: the rows that match,
-- plus the rows reachable from them through its own FK -> PK relationships.
--
--   asli_ctx.discover(seeds jsonb, depth int, max_rows int)
--     seeds: [{"kind": "item_code", "value": "ITEM000041", "weight": 1.0}, ...]
--
-- Nothing in here names a table. The FK graph is read from the catalogue
-- (pg_constraint), so a new table with a foreign key is discovered automatically.
-- Each source only says WHERE seeds can enter (asli_ctx.entry_points) and what
-- role a table plays (asli_ctx.table_roles). That is the per-source config.
--
-- Relevance of a row:
--   seed row        = seed weight x entry weight (x text rank for free text)
--   each FK step    = parent relevance x decay x weight of the table reached
--   several seeds   = combined with noisy-OR, so a row that two different parts
--                     of the query lead to ranks above a row only one leads to
-- Explosion control (production data has hub rows with millions of children):
--   * never walk back down the FK we just came up (no siblings for free)
--   * hub tables (manufacturers, distributors, vendors) are only expanded
--     downwards when the hub itself was named in the user's query (not when the
--     mediator derived it from another source's answer: "derived": true)
--   * at most fanout_cap children per row per FK, at most max_rows returned
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS asli_ctx;

-- where seeds can enter this database
CREATE TABLE IF NOT EXISTS asli_ctx.entry_points (
    seed_kind   text    NOT NULL,   -- item_code, medicine_name, manufacturer_name, vendor_name,
                                    -- distributor_name, distributor_id, batch_no, medicine_code, text
    table_name  text    NOT NULL,
    column_name text    NOT NULL,
    match       text    NOT NULL,   -- exact | fold | prefix | name | text (see discover)
    weight      numeric NOT NULL DEFAULT 1,
    PRIMARY KEY (seed_kind, table_name, column_name)
);

-- what each table is, for ranking and explosion control
CREATE TABLE IF NOT EXISTS asli_ctx.table_roles (
    table_name text PRIMARY KEY,
    role       text    NOT NULL CHECK (role IN ('hub', 'entity', 'link', 'detail')),
    weight     numeric NOT NULL DEFAULT 1,
    label      text
);

-- re-runs of an older version: allow the newer match kinds
ALTER TABLE asli_ctx.entry_points DROP CONSTRAINT IF EXISTS entry_points_match_check;
ALTER TABLE asli_ctx.entry_points ADD CONSTRAINT entry_points_match_check
    CHECK (match IN ('exact', 'fold', 'prefix', 'name', 'text'));

-- columns that must not leave this database as they are (personal data):
--   drop = never returned,  mask = only the first letter is returned
CREATE TABLE IF NOT EXISTS asli_ctx.private_columns (
    table_name  text NOT NULL,
    column_name text NOT NULL,
    action      text NOT NULL CHECK (action IN ('drop', 'mask')),
    PRIMARY KEY (table_name, column_name)
);

-- values this database's demo data was built around (the mediator reads them to
-- fill the batch numbers into the demo documents, so they match every copy)
CREATE TABLE IF NOT EXISTS asli_ctx.demo_story (
    key   text PRIMARY KEY,
    value text
);

CREATE TABLE IF NOT EXISTS asli_ctx.settings (
    key   text PRIMARY KEY,
    value numeric NOT NULL,
    description text
);
INSERT INTO asli_ctx.settings VALUES ('decay', 0.6, 'Relevance kept per FK step') ON CONFLICT (key) DO NOTHING;
INSERT INTO asli_ctx.settings VALUES ('fanout_cap', 10, 'Children followed per row per foreign key') ON CONFLICT (key) DO NOTHING;
INSERT INTO asli_ctx.settings VALUES ('seed_rows_cap', 25, 'Rows one seed may match in one entry point') ON CONFLICT (key) DO NOTHING;
INSERT INTO asli_ctx.settings VALUES ('min_relevance', 0.05, 'Rows below this relevance are dropped') ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION asli_ctx.setting(p_key text) RETURNS numeric
LANGUAGE sql STABLE AS $$ SELECT value FROM asli_ctx.settings WHERE key = p_key $$;

-- primary key of a table as one text expression, e.g. concat_ws('|', t.item_id::text)
CREATE OR REPLACE FUNCTION asli_ctx.pk_expr(p_table text, p_alias text) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce('concat_ws(''|'', ' || string_agg(format('%I.%I::text', p_alias, a.attname), ', '
                                                       ORDER BY array_position(i.indkey::int2[], a.attnum)) || ')',
                    format('%I.ctid::text', p_alias))
    FROM pg_index i
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
    WHERE i.indrelid = p_table::regclass AND i.indisprimary
$$;

-- primary-key columns as an ORDER BY list, e.g. "x.item_id DESC" (numeric order, not text)
CREATE OR REPLACE FUNCTION asli_ctx.pk_order(p_table text, p_alias text, p_dir text DEFAULT 'DESC') RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce(string_agg(format('%I.%I %s', p_alias, a.attname, p_dir), ', '
                               ORDER BY array_position(i.indkey::int2[], a.attnum)),
                    format('%I.ctid %s', p_alias, p_dir))
    FROM pg_index i
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
    WHERE i.indrelid = p_table::regclass AND i.indisprimary
$$;

-- a typed value cannot be a LIKE pattern: escape % _ and \
CREATE OR REPLACE FUNCTION asli_ctx.like_escape(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT replace(replace(replace(p, '\', '\\'), '%', '\%'), '_', '\_') $$;

-- a row as it may leave this database (private columns dropped or masked)
CREATE OR REPLACE FUNCTION asli_ctx.redact(p_table text, p_row jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE AS $$
DECLARE
    pc record;
    r  jsonb := p_row;
BEGIN
    FOR pc IN SELECT * FROM asli_ctx.private_columns WHERE table_name = p_table LOOP
        IF pc.action = 'drop' THEN
            r := r - pc.column_name;
        ELSIF r ? pc.column_name AND r ->> pc.column_name IS NOT NULL THEN
            r := jsonb_set(r, ARRAY[pc.column_name], to_jsonb(left(r ->> pc.column_name, 1) || '***'));
        END IF;
    END LOOP;
    RETURN r;
END;
$$;

-- the FK graph of this database (single-column FKs in schema public), with the
-- column types so the joins compare typed values and can use the indexes
DROP VIEW IF EXISTS asli_ctx.v_schema;
DROP VIEW IF EXISTS asli_ctx.fk_edges;
CREATE VIEW asli_ctx.fk_edges AS
SELECT c.oid                     AS fk_oid,
       c.conname::text           AS fk_name,
       c.conrelid::regclass::text  AS child_table,
       ca.attname::text          AS child_column,
       c.confrelid::regclass::text AS parent_table,
       pa.attname::text          AS parent_column,
       format_type(ca.atttypid, ca.atttypmod) AS child_type,
       format_type(pa.atttypid, pa.atttypmod) AS parent_type
FROM pg_constraint c
JOIN pg_attribute ca ON ca.attrelid = c.conrelid  AND ca.attnum = c.conkey[1]
JOIN pg_attribute pa ON pa.attrelid = c.confrelid AND pa.attnum = c.confkey[1]
WHERE c.contype = 'f'
  AND array_length(c.conkey, 1) = 1
  AND c.connamespace = 'public'::regnamespace;

-- ---------------------------------------------------------------------
-- discover: seeds -> related rows of THIS database, ranked by relevance
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS asli_ctx.discover(jsonb, int, int);
CREATE FUNCTION asli_ctx.discover(p_seeds jsonb, p_depth int DEFAULT 3, p_max_rows int DEFAULT 60)
RETURNS TABLE (db text, table_name text, row_key text, hop int, path text,
               seeds text, relevance numeric, row_data jsonb)
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_decay  numeric := asli_ctx.setting('decay');
    v_cap    int     := asli_ctx.setting('fanout_cap')::int;
    v_seedcap int    := asli_ctx.setting('seed_rows_cap')::int;
    v_min    numeric := asli_ctx.setting('min_relevance');
    s        record;
    e        record;
    fk       record;
    h        int;
    v_where  text;
    v_rel    text;
BEGIN
    IF to_regclass('pg_temp._asli_ctx') IS NOT NULL THEN
        DROP TABLE pg_temp._asli_ctx;
    END IF;
    CREATE TEMP TABLE _asli_ctx (
        tbl text, row_key text, hop int, path text,
        seed text, rel numeric, row_data jsonb,
        came_by oid, dir text, named boolean);

    -- hop 0: rows the seeds point at directly
    -- a seed is "named" when the user typed it; seeds the mediator derived from
    -- another source's answer ("derived": true) may not open hub tables downwards
    FOR s IN SELECT x->>'kind' AS kind, x->>'value' AS value, coalesce((x->>'weight')::numeric, 1) AS weight,
                    NOT coalesce((x->>'derived')::boolean, false) AS named
             FROM jsonb_array_elements(coalesce(p_seeds, '[]'::jsonb)) x
             WHERE nullif(btrim(x->>'value'), '') IS NOT NULL LOOP
        FOR e IN SELECT * FROM asli_ctx.entry_points ep
                 WHERE ep.seed_kind = s.kind
                   AND to_regclass(ep.table_name) IS NOT NULL LOOP
            v_rel := '1';
            v_where := CASE e.match
                WHEN 'exact' THEN format('t.%I::text = $1', e.column_name)
                WHEN 'fold'  THEN format('asli.fold(t.%I::text) = asli.fold($1)', e.column_name)
                -- prefix: can use an index on lower(col) text_pattern_ops (large tables)
                WHEN 'prefix' THEN format('lower(t.%I::text) LIKE asli_ctx.like_escape(lower($1)) || ''%%''', e.column_name)
                -- name: substring, only for small tables (shops, makers, distributors)
                WHEN 'name'  THEN format('lower(t.%I::text) LIKE ''%%'' || asli_ctx.like_escape(lower($1)) || ''%%''', e.column_name)
                WHEN 'text'  THEN format('to_tsvector(''english'', coalesce(t.%I::text, '''')) @@ plainto_tsquery(''english'', $1)',
                                         e.column_name)
            END;
            IF e.match = 'text' THEN
                v_rel := format('least(1, 0.5 + ts_rank_cd(to_tsvector(''english'', coalesce(t.%I::text, '''')), plainto_tsquery(''english'', $1)))',
                                e.column_name);
            END IF;
            EXECUTE format(
                'INSERT INTO _asli_ctx
                 SELECT %L, %s, 0, %L, %L, %s * %s * %s, to_jsonb(t), NULL, ''seed'', %L
                 FROM %s t WHERE %s
                 ORDER BY 6 DESC, %s LIMIT %s',
                e.table_name, asli_ctx.pk_expr(e.table_name, 't'),
                e.table_name || '.' || e.column_name || ' = ' || s.value,
                s.kind || ': ' || s.value,
                s.weight, e.weight, v_rel, s.named,
                e.table_name, v_where, asli_ctx.pk_order(e.table_name, 't', 'ASC'), v_seedcap)
            USING s.value;
        END LOOP;
    END LOOP;

    -- hops 1..depth: follow foreign keys in both directions
    FOR h IN 1 .. p_depth LOOP
        FOR fk IN SELECT * FROM asli_ctx.fk_edges LOOP
            -- UP: child row -> its parent row (exactly one, no cap needed)
            EXECUTE format(
                'INSERT INTO _asli_ctx
                 SELECT %L, %s, %s, f.path || '' → '' || %L, f.seed,
                        f.rel * %s * coalesce((SELECT weight FROM asli_ctx.table_roles WHERE table_name = %L), 1),
                        to_jsonb(p), %s, ''up'', f.named
                 FROM _asli_ctx f
                 JOIN %s p ON p.%I = (f.row_data->>%L)::%s
                 WHERE f.tbl = %L AND f.hop = %s
                   AND NOT (f.came_by = %s AND f.dir = ''down'')',
                fk.parent_table, asli_ctx.pk_expr(fk.parent_table, 'p'), h, fk.parent_table,
                v_decay, fk.parent_table, fk.fk_oid,
                fk.parent_table, fk.parent_column, fk.child_column, fk.parent_type,
                fk.child_table, h - 1, fk.fk_oid);

            -- DOWN: parent row -> up to fanout_cap child rows
            --   (hub tables only when the hub itself was seeded)
            EXECUTE format(
                'INSERT INTO _asli_ctx
                 SELECT %L, c.k, %s, f.path || '' → '' || %L, f.seed,
                        f.rel * %s * coalesce((SELECT weight FROM asli_ctx.table_roles WHERE table_name = %L), 1),
                        c.j, %s, ''down'', f.named
                 FROM _asli_ctx f
                 CROSS JOIN LATERAL (SELECT %s AS k, to_jsonb(x) AS j FROM %s x
                                     WHERE x.%I = (f.row_data->>%L)::%s
                                     ORDER BY %s LIMIT %s) c
                 WHERE f.tbl = %L AND f.hop = %s
                   AND NOT (f.came_by = %s AND f.dir = ''up'')
                   AND ((f.hop = 0 AND f.named)
                        OR coalesce((SELECT role FROM asli_ctx.table_roles WHERE table_name = %L), ''entity'') <> ''hub'')',
                fk.child_table, h, fk.child_table,
                v_decay, fk.child_table, fk.fk_oid,
                asli_ctx.pk_expr(fk.child_table, 'x'), fk.child_table,
                fk.child_column, fk.parent_column, fk.child_type,
                asli_ctx.pk_order(fk.child_table, 'x', 'DESC'), v_cap,
                fk.parent_table, h - 1, fk.fk_oid, fk.parent_table);
        END LOOP;

        -- keep one copy per (row, seed): the most relevant, then the shortest path
        DELETE FROM _asli_ctx a USING _asli_ctx b
        WHERE a.tbl = b.tbl AND a.row_key = b.row_key AND a.seed = b.seed
          AND (a.rel < b.rel OR (a.rel = b.rel AND (a.hop > b.hop OR (a.hop = b.hop AND a.ctid > b.ctid))));
        DELETE FROM _asli_ctx WHERE _asli_ctx.rel < v_min;
    END LOOP;

    -- one row per database row; seeds combined with noisy-OR
    RETURN QUERY
    SELECT current_database()::text, g.tbl, g.row_key, g.hop, g.path, g.seeds,
           round(g.rel, 4), asli_ctx.redact(g.tbl, g.row_data)
    FROM (SELECT x.tbl, x.row_key,
                 min(x.hop) AS hop,
                 (array_agg(x.path ORDER BY x.rel DESC, x.hop))[1] AS path,
                 string_agg(DISTINCT x.seed, ' + ') AS seeds,
                 least(1, 1 - exp(sum(ln(greatest(1e-9, 1 - least(x.rel, 0.999999)))))) AS rel,
                 (array_agg(x.row_data ORDER BY x.hop))[1] AS row_data
          FROM _asli_ctx x
          GROUP BY x.tbl, x.row_key) g
    ORDER BY g.rel DESC, g.hop, g.tbl, g.row_key
    LIMIT p_max_rows;
END;
$$;

-- Free-text search over THIS database's own unstructured text columns
-- (QC remarks, temperature-log notes, customer complaints ...), ranked.
-- The text never leaves the source except for the few rows that match.
DROP FUNCTION IF EXISTS asli_ctx.search_text(text, int);
CREATE FUNCTION asli_ctx.search_text(p_query text, p_limit int DEFAULT 10)
RETURNS TABLE (db text, table_name text, column_name text, row_key text, rank real, headline text, row_data jsonb)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    e record;
BEGIN
    FOR e IN SELECT DISTINCT ep.table_name, ep.column_name FROM asli_ctx.entry_points ep
             WHERE ep.match = 'text' AND to_regclass(ep.table_name) IS NOT NULL LOOP
        RETURN QUERY EXECUTE format(
            'SELECT current_database()::text, %L::text, %L::text, %s,
                    ts_rank_cd(to_tsvector(''english'', coalesce(t.%I, '''')), q),
                    ts_headline(''english'', coalesce(t.%I, ''''), q, ''MaxFragments=2, MaxWords=18, MinWords=6''),
                    asli_ctx.redact(%L, to_jsonb(t))
             FROM %s t, websearch_to_tsquery(''english'', $1) q
             WHERE to_tsvector(''english'', coalesce(t.%I, '''')) @@ q
             ORDER BY 5 DESC LIMIT $2',
            e.table_name, e.column_name, asli_ctx.pk_expr(e.table_name, 't'),
            e.column_name, e.column_name, e.table_name, e.table_name, e.column_name)
        USING p_query, p_limit;
    END LOOP;
END;
$$;

-- describe this source (the mediator shows it in the GUI)
CREATE VIEW asli_ctx.v_schema AS
SELECT t.table_name::text,
       coalesce(r.role, 'entity') AS role,
       r.label,
       (SELECT count(*) FROM asli_ctx.fk_edges f WHERE f.child_table = t.table_name OR f.parent_table = t.table_name) AS fk_links
FROM information_schema.tables t
LEFT JOIN asli_ctx.table_roles r ON r.table_name = t.table_name
WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE';
