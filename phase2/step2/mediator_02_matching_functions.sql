-- =====================================================================
-- Asli-or-Nakli · Phase 2 · Step 2
-- Matching functions (building blocks for approximate matching)
-- RUN ON: mediator_db
-- Safe to run more than once (functions are replaced, settings kept).
-- =====================================================================
--
--  What                        How
--  --------------------------  ---------------------------------------------
--  Item codes                  normalize_code()  +  OUR OWN weighted
--                              Damerau-Levenshtein: code_distance(),
--                              code_similarity(), code_edit_steps()
--  Medicine names              normalize_medicine_name() + OUR OWN
--                              trigram_similarity() + soundex_code()
--  Manufacturer / company      normalize_company() + trigram_similarity()
--  Pack dates                  parse_pack_date() + date_similarity()
--  Baselines for comparison    OUR OWN plain_levenshtein() and
--                              trigram_similarity() on codes
--
-- No extensions are used: every algorithm is written here in PL/pgSQL / SQL.
-- (Earlier versions used fuzzystrmatch and pg_trgm; this script removes them.)
--
-- Tunable numbers live in two tables (match_config, code_char_costs) so
-- they can be shown and changed during the demo without touching code.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.match_config (
    key         text PRIMARY KEY,
    value       numeric NOT NULL,
    description text
);

INSERT INTO public.match_config (key, value, description) VALUES
 ('code_indel_cost',         1.0,  'Cost of a missing or extra character in a code'),
 ('code_zero_indel_cost',    0.5,  'Cost of a missing or extra 0 (dropped / added zero padding)'),
 ('code_transposition_cost', 0.6,  'Cost of two neighbouring characters swapped (e.g. 193 vs 139)'),
 ('code_default_sub_cost',   1.0,  'Cost of replacing one character with an unrelated one')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.match_cfg(p_key text)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT value FROM public.match_config WHERE key = p_key
$$;

-- ---------------------------------------------------------------------
-- 2. Character substitution costs for codes
--    OCR look-alikes are cheap (0.25), neighbouring keys medium (0.5),
--    anything else costs code_default_sub_cost (1.0).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.code_char_costs (
    char_a  char(1) NOT NULL,
    char_b  char(1) NOT NULL,
    cost    numeric NOT NULL,
    reason  text    NOT NULL,
    PRIMARY KEY (char_a, char_b)
);

-- OCR / print look-alikes (both directions)
INSERT INTO public.code_char_costs (char_a, char_b, cost, reason)
SELECT x.a, x.b, 0.25, 'OCR look-alike'
FROM (VALUES ('0','O'),('0','Q'),('0','D'),('O','Q'),('O','D'),
             ('1','I'),('1','L'),('I','L'),
             ('2','Z'),('5','S'),('6','G'),('8','B'),('4','A'),('U','V')) AS p(c1, c2)
CROSS JOIN LATERAL (VALUES (p.c1, p.c2), (p.c2, p.c1)) AS x(a, b)
ON CONFLICT (char_a, char_b) DO NOTHING;

-- Keyboard slips: horizontally neighbouring keys on a QWERTY keyboard
INSERT INTO public.code_char_costs (char_a, char_b, cost, reason)
SELECT x.a, x.b, 0.5, 'Neighbouring key'
FROM (VALUES ('1234567890'), ('QWERTYUIOP'), ('ASDFGHJKL'), ('ZXCVBNM')) AS r(keys)
CROSS JOIN LATERAL generate_series(1, length(r.keys) - 1) AS g(i)
CROSS JOIN LATERAL (VALUES (substr(r.keys, g.i, 1), substr(r.keys, g.i + 1, 1)),
                           (substr(r.keys, g.i + 1, 1), substr(r.keys, g.i, 1))) AS x(a, b)
ON CONFLICT (char_a, char_b) DO NOTHING;   -- an OCR pair keeps its cheaper cost

-- ---------------------------------------------------------------------
-- 3. Item codes
-- ---------------------------------------------------------------------

-- Canonical form: look-alike letters from other alphabets -> Latin,
-- upper case, keep only A-Z and 0-9 (drops spaces, dashes, dots, hidden
-- characters). Does NOT guess O->0 etc.: that is the distance's job.
CREATE OR REPLACE FUNCTION public.normalize_code(p_code text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT regexp_replace(
             upper(translate(coalesce(p_code, ''),
                   -- Cyrillic (upper + lower) and Greek letters that look like Latin ones,
                   -- written as character codes so no editor can silently change them
                   chr(1040) || chr(1042) || chr(1045) || chr(1029) || chr(1030) || chr(1032) || chr(1050) || chr(1052) || chr(1053) || chr(1054) || chr(1056) || chr(1057) || chr(1058) || chr(1059) || chr(1061) || chr(1072) || chr(1074) || chr(1077) || chr(1109) || chr(1110) || chr(1112) || chr(1082) || chr(1084) || chr(1085) || chr(1086) || chr(1088) || chr(1089) || chr(1090) || chr(1091) || chr(1093) || chr(913) || chr(914) || chr(917) || chr(918) || chr(919) || chr(921) || chr(922) || chr(924) || chr(925) || chr(927) || chr(929) || chr(932) || chr(933) || chr(935),
                   'ABESIJKMHOPCTYXABESIJKMHOPCTYXABEZHIKMNOPTYX')),
             '[^A-Z0-9]', '', 'g')
$$;

-- Weighted Damerau-Levenshtein (optimal string alignment) on normalised codes.
-- 0 = identical; each edit adds its cost from code_char_costs / match_config.
CREATE OR REPLACE FUNCTION public.code_distance(p_a text, p_b text)
RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
    a  text := public.normalize_code(p_a);
    b  text := public.normalize_code(p_b);
    n  int  := length(a);
    m  int  := length(b);
    w  int  := m + 1;                       -- row width of the matrix
    d  numeric[];
    sub     jsonb;
    c_indel numeric := public.match_cfg('code_indel_cost');
    c_zero  numeric := public.match_cfg('code_zero_indel_cost');
    c_trans numeric := public.match_cfg('code_transposition_cost');
    c_sub   numeric := public.match_cfg('code_default_sub_cost');
    i int; j int; ca text; cb text; cost numeric; v numeric;
BEGIN
    IF a = b THEN RETURN 0; END IF;

    SELECT jsonb_object_agg(cc.char_a || cc.char_b, cc.cost) INTO sub FROM public.code_char_costs cc;

    d := array_fill(0::numeric, ARRAY[(n + 1) * w]);
    FOR i IN 1..n LOOP
        d[i * w + 1] := d[(i - 1) * w + 1]
                        + CASE WHEN substr(a, i, 1) = '0' THEN c_zero ELSE c_indel END;
    END LOOP;
    FOR j IN 1..m LOOP
        d[j + 1] := d[j]
                    + CASE WHEN substr(b, j, 1) = '0' THEN c_zero ELSE c_indel END;
    END LOOP;

    FOR i IN 1..n LOOP
        ca := substr(a, i, 1);
        FOR j IN 1..m LOOP
            cb := substr(b, j, 1);
            IF ca = cb THEN
                cost := 0;
            ELSE
                cost := coalesce((sub ->> (ca || cb))::numeric, c_sub);
            END IF;
            v := least(
                d[(i - 1) * w + j] + cost,                                                  -- keep / substitute
                d[(i - 1) * w + j + 1] + CASE WHEN ca = '0' THEN c_zero ELSE c_indel END,   -- extra char in a
                d[i * w + j]           + CASE WHEN cb = '0' THEN c_zero ELSE c_indel END    -- char missing from a
            );
            IF i > 1 AND j > 1 AND ca <> cb
               AND ca = substr(b, j - 1, 1) AND substr(a, i - 1, 1) = cb THEN
                v := least(v, d[(i - 2) * w + j - 1] + c_trans);                            -- swapped pair
            END IF;
            d[i * w + j + 1] := v;
        END LOOP;
    END LOOP;

    RETURN d[(n + 1) * w];
END;
$$;

-- 0..1 score: 1 = identical, falls with the weighted distance
CREATE OR REPLACE FUNCTION public.code_similarity(p_a text, p_b text)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT round(greatest(0,
             1 - public.code_distance(p_a, p_b)
                 / nullif(greatest(length(public.normalize_code(p_a)),
                                   length(public.normalize_code(p_b))), 0)), 3)
$$;

-- Human-readable explanation: which edits turn the noisy code into the candidate
CREATE OR REPLACE FUNCTION public.code_edit_steps(p_noisy text, p_candidate text)
RETURNS TABLE (step int, operation text, at_position int, noisy_char text,
               candidate_char text, cost numeric, reason text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    a  text := public.normalize_code(p_noisy);
    b  text := public.normalize_code(p_candidate);
    n  int  := length(a);
    m  int  := length(b);
    w  int  := m + 1;
    d  numeric[];
    sub     jsonb;
    reasons jsonb;
    c_indel numeric := public.match_cfg('code_indel_cost');
    c_zero  numeric := public.match_cfg('code_zero_indel_cost');
    c_trans numeric := public.match_cfg('code_transposition_cost');
    c_sub   numeric := public.match_cfg('code_default_sub_cost');
    i int; j int; ca text; cb text; c numeric; v numeric;
    ops text[] := '{}'; pos int[] := '{}'; fa text[] := '{}'; tb text[] := '{}';
    cs numeric[] := '{}'; rs text[] := '{}';
    k int;
BEGIN
    SELECT jsonb_object_agg(cc.char_a || cc.char_b, cc.cost),
           jsonb_object_agg(cc.char_a || cc.char_b, cc.reason)
    INTO sub, reasons FROM public.code_char_costs cc;

    -- same matrix as code_distance()
    d := array_fill(0::numeric, ARRAY[(n + 1) * w]);
    FOR i IN 1..n LOOP
        d[i * w + 1] := d[(i - 1) * w + 1] + CASE WHEN substr(a, i, 1) = '0' THEN c_zero ELSE c_indel END;
    END LOOP;
    FOR j IN 1..m LOOP
        d[j + 1] := d[j] + CASE WHEN substr(b, j, 1) = '0' THEN c_zero ELSE c_indel END;
    END LOOP;
    FOR i IN 1..n LOOP
        ca := substr(a, i, 1);
        FOR j IN 1..m LOOP
            cb := substr(b, j, 1);
            c := CASE WHEN ca = cb THEN 0 ELSE coalesce((sub ->> (ca || cb))::numeric, c_sub) END;
            v := least(d[(i - 1) * w + j] + c,
                       d[(i - 1) * w + j + 1] + CASE WHEN ca = '0' THEN c_zero ELSE c_indel END,
                       d[i * w + j]           + CASE WHEN cb = '0' THEN c_zero ELSE c_indel END);
            IF i > 1 AND j > 1 AND ca <> cb AND ca = substr(b, j - 1, 1) AND substr(a, i - 1, 1) = cb THEN
                v := least(v, d[(i - 2) * w + j - 1] + c_trans);
            END IF;
            d[i * w + j + 1] := v;
        END LOOP;
    END LOOP;

    -- walk back from the end, recording the edit used at each cell
    i := n; j := m;
    WHILE i > 0 OR j > 0 LOOP
        ca := CASE WHEN i > 0 THEN substr(a, i, 1) END;
        cb := CASE WHEN j > 0 THEN substr(b, j, 1) END;
        IF i > 0 AND j > 0 THEN
            c := CASE WHEN ca = cb THEN 0 ELSE coalesce((sub ->> (ca || cb))::numeric, c_sub) END;
            IF d[i * w + j + 1] = d[(i - 1) * w + j] + c THEN
                IF ca <> cb THEN
                    ops := ops || 'replace'::text; pos := pos || i; fa := fa || ca; tb := tb || cb;
                    cs := cs || c; rs := rs || coalesce(reasons ->> (ca || cb), 'Unrelated character');
                END IF;
                i := i - 1; j := j - 1; CONTINUE;
            END IF;
            IF i > 1 AND j > 1 AND ca <> cb AND ca = substr(b, j - 1, 1) AND substr(a, i - 1, 1) = cb
               AND d[i * w + j + 1] = d[(i - 2) * w + j - 1] + c_trans THEN
                ops := ops || 'swap'::text; pos := pos || (i - 1); fa := fa || (substr(a, i - 1, 1) || ca);
                tb := tb || (substr(b, j - 1, 1) || cb); cs := cs || c_trans; rs := rs || 'Neighbouring characters swapped'::text;
                i := i - 2; j := j - 2; CONTINUE;
            END IF;
        END IF;
        c := CASE WHEN ca = '0' THEN c_zero ELSE c_indel END;   -- cost if this char is extra
        IF i > 0 AND d[i * w + j + 1] = d[(i - 1) * w + j + 1] + c THEN
            ops := ops || 'remove'::text; pos := pos || i; fa := fa || ca; tb := tb || ''::text;
            cs := cs || c;
            rs := rs || CASE WHEN ca = '0' THEN 'Extra zero' ELSE 'Extra character' END;
            i := i - 1; CONTINUE;
        END IF;
        ops := ops || 'insert'::text; pos := pos || (i + 1); fa := fa || ''::text; tb := tb || cb;
        cs := cs || CASE WHEN cb = '0' THEN c_zero ELSE c_indel END;
        rs := rs || CASE WHEN cb = '0' THEN 'Missing zero (padding)' ELSE 'Missing character' END;
        j := j - 1;
    END LOOP;

    -- edits were collected back-to-front; return them in reading order
    FOR k IN REVERSE coalesce(array_length(ops, 1), 0)..1 LOOP
        step := coalesce(array_length(ops, 1), 0) - k + 1;
        operation := ops[k]; at_position := pos[k]; noisy_char := fa[k];
        candidate_char := tb[k]; cost := cs[k]; reason := rs[k];
        RETURN NEXT;
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------
-- 4. Our own general string algorithms (replace fuzzystrmatch / pg_trgm)
-- ---------------------------------------------------------------------

-- Trigrams of a text: lower case, split into words of letters/digits,
-- each word padded as '  word ' and cut into overlapping 3-character pieces.
-- 'para' -> {"  p"," pa","par","ara","ra "}
CREATE OR REPLACE FUNCTION public.trigrams(p_text text)
RETURNS text[] LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    w   text;
    s   text;
    t   text;
    out text[] := '{}';
    i   int;
BEGIN
    FOREACH w IN ARRAY regexp_split_to_array(lower(coalesce(p_text, '')), '[^[:alnum:]]+') LOOP
        CONTINUE WHEN w = '';
        s := '  ' || w || ' ';
        FOR i IN 1..length(s) - 2 LOOP
            t := substr(s, i, 3);
            IF NOT (t = ANY (out)) THEN
                out := out || t;            -- keep each trigram once
            END IF;
        END LOOP;
    END LOOP;
    RETURN out;
END;
$$;

-- Jaccard similarity of the two trigram sets: shared / all distinct. 0..1
CREATE OR REPLACE FUNCTION public.trigram_similarity(p_a text, p_b text)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    ta     text[] := public.trigrams(p_a);
    tb     text[] := public.trigrams(p_b);
    t      text;
    shared int := 0;
BEGIN
    IF cardinality(ta) + cardinality(tb) = 0 THEN RETURN 0; END IF;
    FOREACH t IN ARRAY ta LOOP
        IF t = ANY (tb) THEN shared := shared + 1; END IF;
    END LOOP;
    RETURN round(shared::numeric / (cardinality(ta) + cardinality(tb) - shared), 6);
END;
$$;

-- Soundex: first letter + 3 digits for the consonant sounds, so words that
-- sound alike get the same key ('Rabeprazol' and 'Rabeprazole' -> R116).
--   1 = B F P V   2 = C G J K Q S X Z   3 = D T   4 = L   5 = M N   6 = R
--   vowels (and Y) separate repeated sounds; H and W are skipped.
CREATE OR REPLACE FUNCTION public.soundex_code(p_word text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    s      text := upper(regexp_replace(coalesce(p_word, ''), '[^A-Za-z]', '', 'g'));
    digits text;
    code   text;
    prev   text;
    d      text;
    i      int;
BEGIN
    IF s = '' THEN RETURN NULL; END IF;
    digits := translate(s, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                           '0123012-02245501262301-202');
    code := substr(s, 1, 1);
    prev := substr(digits, 1, 1);
    FOR i IN 2..length(s) LOOP
        d := substr(digits, i, 1);
        CONTINUE WHEN d = '-';                           -- H, W: ignored
        IF d = '0' THEN prev := '0'; CONTINUE; END IF;   -- vowel: separator
        IF d <> prev THEN code := code || d; END IF;
        prev := d;
        EXIT WHEN length(code) = 4;
    END LOOP;
    RETURN rpad(code, 4, '0');
END;
$$;

-- Plain (unweighted) Levenshtein distance: every insert, delete or
-- substitution costs 1. Used only as the BASELINE our code_distance() is
-- compared against.
CREATE OR REPLACE FUNCTION public.plain_levenshtein(p_a text, p_b text)
RETURNS int LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    a    text := coalesce(p_a, '');
    b    text := coalesce(p_b, '');
    n    int  := length(a);
    m    int  := length(b);
    prev int[];
    cur  int[];
    i int; j int;
BEGIN
    IF n = 0 THEN RETURN m; END IF;
    IF m = 0 THEN RETURN n; END IF;
    prev := ARRAY(SELECT generate_series(0, m));       -- row 0: 0,1,2,..,m
    FOR i IN 1..n LOOP
        cur := ARRAY[i];
        FOR j IN 1..m LOOP
            cur := cur || least(prev[j + 1] + 1,                         -- delete
                                cur[j] + 1,                              -- insert
                                prev[j] + CASE WHEN substr(a, i, 1) = substr(b, j, 1)
                                               THEN 0 ELSE 1 END);       -- substitute
        END LOOP;
        prev := cur;
    END LOOP;
    RETURN prev[m + 1];
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Medicine names
-- ---------------------------------------------------------------------

-- lower case; "500 mg" -> "500mg"; "0.5 g" -> "500mg"; drop dosage-form
-- words (tab, tablet, cap, capsule, ...) and punctuation.
CREATE OR REPLACE FUNCTION public.normalize_medicine_name(p_name text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    s text := lower(coalesce(p_name, ''));
    g text[];
BEGIN
    s := regexp_replace(s, '(\d+(\.\d+)?)\s*(mcg|mg|ml|gm|g)\M', '\1\3', 'g');
    s := regexp_replace(s, '(\d+(\.\d+)?)gm\M', '\1g', 'g');
    FOR g IN SELECT regexp_matches(s, '(\d+(?:\.\d+)?)g\M', 'g') LOOP
        s := regexp_replace(s, g[1] || 'g\M', ((g[1])::numeric * 1000)::int || 'mg');
    END LOOP;
    s := regexp_replace(s, '\m(tablets?|tabs?|capsules?|caps?|syrup|suspension|susp|injection|inj|ip|bp|usp)\M', ' ', 'g');
    s := regexp_replace(s, '[^a-z0-9 ]', ' ', 'g');
    RETURN btrim(regexp_replace(s, '\s+', ' ', 'g'));
END;
$$;

-- 0..1.  NULL when either side is missing (unknown is not the same as wrong).
--   75% spelling similarity (trigram_similarity)
-- + 25% "sounds the same" (soundex_code of the drug word)
-- then halved if both give a strength and the strengths differ (400mg vs 500mg).
CREATE OR REPLACE FUNCTION public.medicine_name_similarity(p_a text, p_b text)
RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
    na text := public.normalize_medicine_name(p_a);
    nb text := public.normalize_medicine_name(p_b);
    wa text; wb text; sa text; sb text;
    score numeric;
BEGIN
    IF na = '' OR nb = '' THEN RETURN NULL; END IF;
    IF na = nb THEN RETURN 1; END IF;

    wa := substring(na FROM '[a-z]+');
    wb := substring(nb FROM '[a-z]+');
    score := 0.75 * public.trigram_similarity(na, nb)
           + 0.25 * CASE WHEN wa IS NOT NULL AND wb IS NOT NULL
                          AND public.soundex_code(wa) = public.soundex_code(wb) THEN 1 ELSE 0 END;

    SELECT string_agg(x[1], ',' ORDER BY x[1]) INTO sa FROM regexp_matches(na, '(\d+(?:\.\d+)?(?:mcg|mg|ml))', 'g') x;
    SELECT string_agg(x[1], ',' ORDER BY x[1]) INTO sb FROM regexp_matches(nb, '(\d+(?:\.\d+)?(?:mcg|mg|ml))', 'g') x;
    IF sa IS NOT NULL AND sb IS NOT NULL AND sa <> sb THEN
        score := score * 0.5;
    END IF;

    RETURN round(least(1, score), 3);
END;
$$;

-- ---------------------------------------------------------------------
-- 6. Manufacturer / company names
-- ---------------------------------------------------------------------

-- lower case; Pharmaceuticals -> pharma; Laboratories / Labs -> lab;
-- drop Ltd / Limited / Pvt / Private / Inc; remove spaces and punctuation
-- ("Cure Life Pharma" and "CureLife Pharma" become identical).
CREATE OR REPLACE FUNCTION public.normalize_company(p_name text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT regexp_replace(
             regexp_replace(
               regexp_replace(
                 regexp_replace(lower(coalesce(p_name, '')), '&', ' and ', 'g'),
                 '\m(pharmaceuticals?|pharmaceutics|pharm)\M', 'pharma', 'g'),
               '\m(laboratories|laboratory|labs)\M', 'lab', 'g'),
             '\m(ltd|limited|pvt|private|inc|co)\M|[^a-z0-9]', '', 'g')
$$;

CREATE OR REPLACE FUNCTION public.company_similarity(p_a text, p_b text)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT CASE
             WHEN public.normalize_company(p_a) = '' OR public.normalize_company(p_b) = '' THEN NULL
             WHEN public.normalize_company(p_a) = public.normalize_company(p_b) THEN 1
             ELSE round(public.trigram_similarity(public.normalize_company(p_a), public.normalize_company(p_b)), 3)
           END
$$;

-- ---------------------------------------------------------------------
-- 7. Dates as printed on packs
-- ---------------------------------------------------------------------

-- Understands: 2028-04-12 · 12/04/2028 · 12-04-28 · 04/2028 · 4/28 ·
--              2028-04 · APR-2028 · Apr 28 · April 2028 · 12 Apr 2028
-- Day-first (Indian) order for full dates. Month-only dates -> 1st of month.
-- Returns NULL if it cannot be read.
CREATE OR REPLACE FUNCTION public.parse_pack_date(p_text text)
RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    s text := upper(btrim(coalesce(p_text, '')));
    r text[];
    y int; mo int; dd int := 1; t int;
    months constant text[] := ARRAY['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
BEGIN
    IF s = '' THEN RETURN NULL; END IF;

    LOOP  -- runs once; EXIT as soon as one pattern matches
        r := regexp_match(s, '^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$');                  -- 2028-04-12
        IF r IS NOT NULL THEN y := r[1]::int; mo := r[2]::int; dd := r[3]::int; EXIT; END IF;

        r := regexp_match(s, '^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})$');            -- 12/04/2028
        IF r IS NOT NULL THEN
            dd := r[1]::int; mo := r[2]::int; y := r[3]::int;
            IF mo > 12 AND dd <= 12 THEN t := dd; dd := mo; mo := t; END IF;              -- 04/12/2028 written US-style
            EXIT;
        END IF;

        r := regexp_match(s, '^(\d{4})[-/.](\d{1,2})$');                                 -- 2028-04
        IF r IS NOT NULL THEN y := r[1]::int; mo := r[2]::int; EXIT; END IF;

        r := regexp_match(s, '^(\d{1,2})[-/.](\d{4}|\d{2})$');                           -- 04/2028, 4/28
        IF r IS NOT NULL THEN mo := r[1]::int; y := r[2]::int; EXIT; END IF;

        r := regexp_match(s, '^([A-Z]{3})[A-Z]*[\s\-/.,]*(\d{4}|\d{2})$');               -- APR-2028, April 28
        IF r IS NOT NULL THEN mo := array_position(months, r[1]); y := r[2]::int; EXIT; END IF;

        r := regexp_match(s, '^(\d{1,2})[\s\-/.]*([A-Z]{3})[A-Z]*[\s\-/.,]*(\d{4}|\d{2})$'); -- 12 Apr 2028
        IF r IS NOT NULL THEN dd := r[1]::int; mo := array_position(months, r[2]); y := r[3]::int; EXIT; END IF;

        RETURN NULL;   -- no pattern matched
    END LOOP;

    IF y < 100 THEN y := 2000 + y; END IF;
    IF mo IS NULL OR mo NOT BETWEEN 1 AND 12 THEN RETURN NULL; END IF;
    BEGIN
        RETURN make_date(y, mo, dd);
    EXCEPTION WHEN others THEN
        RETURN NULL;   -- e.g. 31/02/2028
    END;
END;
$$;

-- Compared at month level (packs usually print only month/year).
-- 1 = same month, 0.5 = one month apart, 0 = further apart, NULL = unknown.
CREATE OR REPLACE FUNCTION public.date_similarity(p_a text, p_b text)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
             WHEN da IS NULL OR db IS NULL THEN NULL
             WHEN abs(months) = 0 THEN 1
             WHEN abs(months) = 1 THEN 0.5
             ELSE 0
           END
    FROM (SELECT public.parse_pack_date(p_a) AS da, public.parse_pack_date(p_b) AS db) x
    CROSS JOIN LATERAL (SELECT (extract(year FROM x.da) * 12 + extract(month FROM x.da))
                             - (extract(year FROM x.db) * 12 + extract(month FROM x.db)) AS months) y
$$;

-- =====================================================================
-- Remove the extensions: nothing above uses them any more.
-- (Fails with a clear message if something else in the database still does.)
-- =====================================================================
DROP EXTENSION IF EXISTS pg_trgm;
DROP EXTENSION IF EXISTS fuzzystrmatch;

-- =====================================================================
-- Checks: every row should say PASS
-- =====================================================================
SELECT test, CASE WHEN got = expected THEN 'PASS' ELSE 'FAIL (got ' || got || ')' END AS result
FROM (VALUES
  ('normalise dash + case',      normalize_code('item-000202'),                          'ITEM000202'),
  ('normalise Cyrillic E',       normalize_code('IT' || chr(1045) || 'M000268'),         'ITEM000268'),
  ('O for 0 costs 0.25',         code_distance('ITEM0O0041', 'ITEM000041')::text,         '0.25'),
  ('swapped digits cost 0.6',    code_distance('ITEM000816', 'ITEM000186')::text,         '0.6'),
  ('3 missing zeros cost 1.5',   code_distance('ITEM214', 'ITEM000214')::text,            '1.5'),
  ('edit steps for lTEM0OO183',  (SELECT string_agg(noisy_char || '>' || candidate_char, ' ' ORDER BY step)
                                  FROM code_edit_steps('lTEM0OO183', 'ITEM000183')),      'L>I O>0 O>0'),
  ('name: misspelt = high',      (medicine_name_similarity('Doxycyclin 100mg', 'Doxycycline 100mg') > 0.8)::text, 'true'),
  ('name: other drug = low',     (medicine_name_similarity('Calcium 500mg', 'Cefixime 200mg') < 0.2)::text,       'true'),
  ('name: 0.5 g = 500mg',        medicine_name_similarity('Paracetamol 0.5 g Tab', 'Paracetamol 500mg')::text,   '1'),
  ('company: Labs = Laboratories', company_similarity('MediCare Labs', 'MediCare Laboratories')::text,         '1'),
  ('date: MAR-2028',             parse_pack_date('MAR-2028')::text,                       '2028-03-01'),
  ('date: 6/28',                 parse_pack_date('6/28')::text,                           '2028-06-01'),
  ('date: 12/04/2028 day-first', parse_pack_date('12/04/2028')::text,                     '2028-04-12'),
  ('date: same month = 1',       date_similarity('2028-06', '2028-06-28')::text,          '1'),
  ('own trigram similarity',     trigram_similarity('rabeprazol', 'rabeprazole')::text,   '0.769231'),
  ('own soundex: Rabeprazol(e)', soundex_code('Rabeprazol') || ' ' || soundex_code('Rabeprazole'), 'R116 R116'),
  ('own plain levenshtein',      plain_levenshtein('ITEM0000B4', 'ITEM000084')::text,     '1'),
  ('no fuzzystrmatch / pg_trgm installed',
     (SELECT count(*) FROM pg_extension WHERE extname IN ('fuzzystrmatch', 'pg_trgm'))::text, '0')
) AS t(test, got, expected);
