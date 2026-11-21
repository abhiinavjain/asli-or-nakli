-- =====================================================================
-- asli_match 1.0 : functions the mediator can SHIP to a source database.
-- postgres_fdw sends a function to the remote side only when it is IMMUTABLE
-- and belongs to an extension listed in the server's 'extensions' option, so
-- every function here is IMMUTABLE and self-contained (no tables, no config).
-- Same version on the mediator and on every source.
-- =====================================================================

-- Canonical text of a code: look-alike letters from other alphabets -> Latin,
-- upper case, only A-Z and 0-9 (same as the mediator's normalize_code).
CREATE FUNCTION @extschema@.norm(p_code text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $f$
    SELECT pg_catalog.regexp_replace(
             pg_catalog.upper(pg_catalog.translate(coalesce(p_code, ''),
                   pg_catalog.chr(1040) || pg_catalog.chr(1042) || pg_catalog.chr(1045) || pg_catalog.chr(1029) || pg_catalog.chr(1030) || pg_catalog.chr(1032) || pg_catalog.chr(1050) || pg_catalog.chr(1052) || pg_catalog.chr(1053) || pg_catalog.chr(1054) || pg_catalog.chr(1056) || pg_catalog.chr(1057) || pg_catalog.chr(1058) || pg_catalog.chr(1059) || pg_catalog.chr(1061) || pg_catalog.chr(1072) || pg_catalog.chr(1074) || pg_catalog.chr(1077) || pg_catalog.chr(1109) || pg_catalog.chr(1110) || pg_catalog.chr(1112) || pg_catalog.chr(1082) || pg_catalog.chr(1084) || pg_catalog.chr(1085) || pg_catalog.chr(1086) || pg_catalog.chr(1088) || pg_catalog.chr(1089) || pg_catalog.chr(1090) || pg_catalog.chr(1091) || pg_catalog.chr(1093) || pg_catalog.chr(913) || pg_catalog.chr(914) || pg_catalog.chr(917) || pg_catalog.chr(918) || pg_catalog.chr(919) || pg_catalog.chr(921) || pg_catalog.chr(922) || pg_catalog.chr(924) || pg_catalog.chr(925) || pg_catalog.chr(927) || pg_catalog.chr(929) || pg_catalog.chr(932) || pg_catalog.chr(933) || pg_catalog.chr(935),
                   'ABESIJKMHOPCTYXABESIJKMHOPCTYXABEZHIKMNOPTYX')),
             '[^A-Z0-9]', '', 'g')
$f$;

-- Folded code: the prefix read as ITEM, look-alike letters in the number read as
-- digits (O Q D -> 0, I L -> 1, Z -> 2, S -> 5, G -> 6, B -> 8), the number padded
-- to 6 digits. lTEM0OO183 -> ITEM000183, ITEM214 -> ITEM000214. A code that does
-- not look like an item code is returned as norm() gives it.
CREATE FUNCTION @extschema@.fold(p_code text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE COST 100 AS $f$
    SELECT CASE WHEN t.p IS NOT NULL AND t.d ~ '^[0-9]+$'
                THEN 'ITEM' || CASE WHEN pg_catalog.length(pg_catalog.ltrim(t.d, '0')) >= 6 THEN pg_catalog.ltrim(t.d, '0')
                                    ELSE pg_catalog.lpad(pg_catalog.ltrim(t.d, '0'), 6, '0') END
                ELSE t.n END
    FROM (SELECT n, (pg_catalog.regexp_match(n, '^(ITEM|ITRM|ITEN|1TEM|LTEM|ITM|IEM)'))[1] AS p,
                 pg_catalog.translate(pg_catalog.regexp_replace(n, '^(ITEM|ITRM|ITEN|1TEM|LTEM|ITM|IEM)', ''),
                                      'OQDILZSGB', '000112568') AS d
          FROM (SELECT @extschema@.norm(p_code) AS n) a) t
$f$;

-- Blocking keys: any two codes ONE typing error apart (after folding) share a key.
--   h:  one digit replaced by a wildcard          one wrong digit
--   t:  a neighbouring pair written in sorted order two digits swapped
--   d:  the significant digits, and each with one digit deleted   one digit missing or extra
-- About 19 keys per code, whatever the size of the table.
CREATE FUNCTION @extschema@.keys(p_code text) RETURNS text[]
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE COST 500 AS $f$
DECLARE
    f   text := @extschema@.fold(p_code);
    s   text;
    v   text;
    k   text;
    out text[] := '{}';
    i   int;
    a   text; b text;
BEGIN
    s := CASE WHEN f LIKE 'ITEM%' THEN pg_catalog.substr(f, 5) ELSE f END;
    IF s IS NULL OR s = '' THEN RETURN out; END IF;
    v := coalesce(nullif(pg_catalog.ltrim(s, '0'), ''), '0');
    FOR i IN 1..pg_catalog.length(s) LOOP                       -- h: one wrong digit
        out := out || ('h:' || pg_catalog.substr(s, 1, i - 1) || '_' || pg_catalog.substr(s, i + 1));
    END LOOP;
    FOR i IN 1..pg_catalog.length(s) - 1 LOOP                   -- t: two neighbours swapped
        a := pg_catalog.substr(s, i, 1); b := pg_catalog.substr(s, i + 1, 1);
        k := 't:' || pg_catalog.substr(s, 1, i - 1) || LEAST(a, b) || GREATEST(a, b) || pg_catalog.substr(s, i + 2);
        IF NOT k = ANY (out) THEN out := out || k; END IF;
    END LOOP;
    out := out || ('d:' || v);                                   -- d: one digit missing / extra
    FOR i IN 1..pg_catalog.length(v) LOOP
        k := 'd:' || pg_catalog.substr(v, 1, i - 1) || pg_catalog.substr(v, i + 1);
        IF NOT k = ANY (out) THEN out := out || k; END IF;
    END LOOP;
    RETURN out;
END;
$f$;

-- Weighted Damerau-Levenshtein, the same algorithm as the mediator's code_distance,
-- with the default costs built in (the source only uses it to pick its top k;
-- the mediator re-scores with the costs editable in Matching settings).
CREATE FUNCTION @extschema@.dist(p_a text, p_b text) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE COST 200 AS $f$
DECLARE
    a  text := @extschema@.norm(p_a);
    b  text := @extschema@.norm(p_b);
    n  int  := pg_catalog.length(a);
    m  int  := pg_catalog.length(b);
    w  int  := m + 1;
    d  numeric[];
    sub constant jsonb := '{"09": 0.5, "0D": 0.25, "0O": 0.25, "0Q": 0.25, "12": 0.5, "1I": 0.25, "1L": 0.25, "21": 0.5, "23": 0.5, "2Z": 0.25, "32": 0.5, "34": 0.5, "43": 0.5, "45": 0.5, "4A": 0.25, "54": 0.5, "56": 0.5, "5S": 0.25, "65": 0.5, "67": 0.5, "6G": 0.25, "76": 0.5, "78": 0.5, "87": 0.5, "89": 0.5, "8B": 0.25, "90": 0.5, "98": 0.5, "A4": 0.25, "AS": 0.5, "B8": 0.25, "BN": 0.5, "BV": 0.5, "CV": 0.5, "CX": 0.5, "D0": 0.25, "DF": 0.5, "DO": 0.25, "DS": 0.5, "ER": 0.5, "EW": 0.5, "FD": 0.5, "FG": 0.5, "G6": 0.25, "GF": 0.5, "GH": 0.5, "HG": 0.5, "HJ": 0.5, "I1": 0.25, "IL": 0.25, "IO": 0.5, "IU": 0.5, "JH": 0.5, "JK": 0.5, "KJ": 0.5, "KL": 0.5, "L1": 0.25, "LI": 0.25, "LK": 0.5, "MN": 0.5, "NB": 0.5, "NM": 0.5, "O0": 0.25, "OD": 0.25, "OI": 0.5, "OP": 0.5, "OQ": 0.25, "PO": 0.5, "Q0": 0.25, "QO": 0.25, "QW": 0.5, "RE": 0.5, "RT": 0.5, "S5": 0.25, "SA": 0.5, "SD": 0.5, "TR": 0.5, "TY": 0.5, "UI": 0.5, "UV": 0.25, "UY": 0.5, "VB": 0.5, "VC": 0.5, "VU": 0.25, "WE": 0.5, "WQ": 0.5, "XC": 0.5, "XZ": 0.5, "YT": 0.5, "YU": 0.5, "Z2": 0.25, "ZX": 0.5}';
    c_indel constant numeric := 1.0;
    c_zero  constant numeric := 0.5;
    c_trans constant numeric := 0.6;
    c_sub   constant numeric := 1.0;
    i int; j int; ca text; cb text; cost numeric; v numeric;
BEGIN
    IF a = b THEN RETURN 0; END IF;
    d := pg_catalog.array_fill(0::numeric, ARRAY[(n + 1) * w]);
    FOR i IN 1..n LOOP
        d[i * w + 1] := d[(i - 1) * w + 1] + CASE WHEN pg_catalog.substr(a, i, 1) = '0' THEN c_zero ELSE c_indel END;
    END LOOP;
    FOR j IN 1..m LOOP
        d[j + 1] := d[j] + CASE WHEN pg_catalog.substr(b, j, 1) = '0' THEN c_zero ELSE c_indel END;
    END LOOP;
    FOR i IN 1..n LOOP
        ca := pg_catalog.substr(a, i, 1);
        FOR j IN 1..m LOOP
            cb := pg_catalog.substr(b, j, 1);
            IF ca = cb THEN cost := 0; ELSE cost := coalesce((sub ->> (ca || cb))::numeric, c_sub); END IF;
            v := LEAST(d[(i - 1) * w + j] + cost,
                       d[(i - 1) * w + j + 1] + CASE WHEN ca = '0' THEN c_zero ELSE c_indel END,
                       d[i * w + j]           + CASE WHEN cb = '0' THEN c_zero ELSE c_indel END);
            IF i > 1 AND j > 1 AND ca <> cb
               AND ca = pg_catalog.substr(b, j - 1, 1) AND pg_catalog.substr(a, i - 1, 1) = cb THEN
                v := LEAST(v, d[(i - 2) * w + j - 1] + c_trans);
            END IF;
            d[i * w + j + 1] := v;
        END LOOP;
    END LOOP;
    RETURN d[(n + 1) * w];
END;
$f$;

-- Sound key of a medicine name: Soundex of its first word ('Omeprazol 20mg' and
-- 'OMEPRAZOLE 20 MG' -> O516). Used for the context pass of candidate search.
CREATE FUNCTION @extschema@.name_key(p_name text) RETURNS text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE COST 100 AS $f$
DECLARE
    s      text := pg_catalog.upper(coalesce((pg_catalog.regexp_match(coalesce(p_name, ''), '[A-Za-z]+'))[1], ''));
    digits text; code text; prev text; dd text; i int;
BEGIN
    IF s = '' THEN RETURN NULL; END IF;
    digits := pg_catalog.translate(s, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', '0123012-02245501262301-202');
    code := pg_catalog.substr(s, 1, 1);
    prev := pg_catalog.substr(digits, 1, 1);
    FOR i IN 2..pg_catalog.length(s) LOOP
        dd := pg_catalog.substr(digits, i, 1);
        CONTINUE WHEN dd = '-';
        IF dd = '0' THEN prev := '0'; CONTINUE; END IF;
        IF dd <> prev THEN code := code || dd; END IF;
        prev := dd;
        EXIT WHEN pg_catalog.length(code) = 4;
    END LOOP;
    RETURN pg_catalog.rpad(code, 4, '0');
END;
$f$;

-- Pack dates in any of the formats we see (2028-04-12, 12/04/2028, 04/2028, 4/28,
-- APR-2028, 12 Apr 2028); same rules as the mediator's parse_pack_date.
CREATE FUNCTION @extschema@.parse_date(p_text text) RETURNS date
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE COST 100 AS $f$
DECLARE
    s text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_text, '')));
    r text[];
    y int; mo int; dd int := 1; t int;
    months constant text[] := ARRAY['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
BEGIN
    IF s = '' THEN RETURN NULL; END IF;
    LOOP
        r := pg_catalog.regexp_match(s, '^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$');
        IF r IS NOT NULL THEN y := r[1]::int; mo := r[2]::int; dd := r[3]::int; EXIT; END IF;
        r := pg_catalog.regexp_match(s, '^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})$');
        IF r IS NOT NULL THEN
            dd := r[1]::int; mo := r[2]::int; y := r[3]::int;
            IF mo > 12 AND dd <= 12 THEN t := dd; dd := mo; mo := t; END IF;
            EXIT;
        END IF;
        r := pg_catalog.regexp_match(s, '^(\d{4})[-/.](\d{1,2})$');
        IF r IS NOT NULL THEN y := r[1]::int; mo := r[2]::int; EXIT; END IF;
        r := pg_catalog.regexp_match(s, '^(\d{1,2})[-/.](\d{4}|\d{2})$');
        IF r IS NOT NULL THEN mo := r[1]::int; y := r[2]::int; EXIT; END IF;
        r := pg_catalog.regexp_match(s, '^([A-Z]{3})[A-Z]*[\s\-/.,]*(\d{4}|\d{2})$');
        IF r IS NOT NULL THEN mo := pg_catalog.array_position(months, r[1]); y := r[2]::int; EXIT; END IF;
        r := pg_catalog.regexp_match(s, '^(\d{1,2})[\s\-/.]*([A-Z]{3})[A-Z]*[\s\-/.,]*(\d{4}|\d{2})$');
        IF r IS NOT NULL THEN dd := r[1]::int; mo := pg_catalog.array_position(months, r[2]); y := r[3]::int; EXIT; END IF;
        RETURN NULL;
    END LOOP;
    IF y < 100 THEN y := 2000 + y; END IF;
    IF mo IS NULL OR mo NOT BETWEEN 1 AND 12 OR y NOT BETWEEN 1 AND 9999 THEN RETURN NULL; END IF;
    -- no exception block (that would make the function unusable in parallel index
    -- builds): check the day against the length of that month instead
    IF dd < 1 OR dd > pg_catalog.date_part('day', (pg_catalog.make_date(y, mo, 1) + interval '1 month - 1 day'))::int THEN
        RETURN NULL;
    END IF;
    RETURN pg_catalog.make_date(y, mo, dd);
END;
$f$;

-- Month bucket (year * 100 + month) of a date, or of a date written as text.
-- PL/pgSQL on purpose: a plain SQL body would be inlined into date_part(), which
-- postgres_fdw then refuses to send to the source.
CREATE FUNCTION @extschema@.month_key(p_date date) RETURNS int
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $f$
BEGIN
    RETURN (pg_catalog.date_part('year', p_date) * 100 + pg_catalog.date_part('month', p_date))::int;
END;
$f$;
CREATE FUNCTION @extschema@.month_key(p_text text) RETURNS int
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE COST 100 AS $f$
BEGIN
    RETURN @extschema@.month_key(@extschema@.parse_date(p_text));
END;
$f$;
