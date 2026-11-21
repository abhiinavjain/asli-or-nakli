# Phase 2 · Step 2 — Matching functions

Everything in this step lives in **`mediator_db` only**. The other three databases are not touched.

**No extensions.** Every algorithm is our own PL/pgSQL/SQL. The script also **removes `fuzzystrmatch` and `pg_trgm`** if an earlier version installed them, and a check confirms they are gone.

## How to run

1. Open `mediator_02_matching_functions.sql` in DBeaver, connected to **mediator_db**.
2. Run it as a **script**: *SQL Editor → Execute SQL Script* (**Alt+X**), not Ctrl+Enter. The functions contain `$$ … $$` blocks, which must go through whole.
3. The last result tab shows 18 checks. **All must say PASS.** One of them confirms `fuzzystrmatch` and `pg_trgm` are no longer installed.
4. Optional: run `eval_code_ranking.sql` (also Alt+X) to reproduce the comparison table below. It is read-only.

The script can be re-run safely. Functions are replaced; your edits to the two settings tables are kept.

## What gets created

| Object | Type | What it does |
|---|---|---|
| `trigrams(text)`, `trigram_similarity(a, b)` | functions | **Ours.** Words padded as `'  word '`, cut into 3-letter pieces; similarity = shared pieces / all distinct pieces |
| `soundex_code(word)` | function | **Ours.** Soundex sound-alike key: first letter + 3 digits (`Rabeprazol` = `Rabeprazole` = R116) |
| `plain_levenshtein(a, b)` | function | **Ours.** Unweighted edit distance, used only as the baseline |
| `match_config` | table | Tunable numbers (indel / zero / swap / default costs). Step 3 adds score weights here. |
| `code_char_costs` | table | 92 character pairs: OCR look-alikes (0.25), neighbouring keys (0.5) |
| `normalize_code(code)` | function | Look-alike Cyrillic/Greek letters → Latin, upper case, keep only A–Z 0–9 |
| `code_distance(a, b)` | function | **Our** weighted Damerau-Levenshtein. 0 = identical |
| `code_similarity(a, b)` | function | Same as a 0–1 score |
| `code_edit_steps(noisy, candidate)` | function | Lists each edit with its cost and reason, for the GUI and the viva |
| `normalize_medicine_name(name)` | function | Lower case, `500 mg`→`500mg`, `0.5 g`→`500mg`, drops tab/cap/syrup… |
| `medicine_name_similarity(a, b)` | function | 75% trigram spelling + 25% sound-alike (Soundex), halved if strengths differ |
| `normalize_company(name)` | function | Pharmaceuticals→pharma, Laboratories/Labs→lab, drops Ltd/Pvt/spaces |
| `company_similarity(a, b)` | function | Trigram similarity of the normalised names |
| `parse_pack_date(text)` | function | Reads 11 date styles found on packs; NULL if unreadable |
| `date_similarity(a, b)` | function | Month level: 1 same month, 0.5 one month apart, else 0 |

All context functions return **NULL when a value is missing**, so "not given" is never treated as "wrong".

## Why a custom distance for codes

Plain Levenshtein charges 1 for every change. On our codes that fails in three ways:

1. **All substitutions cost the same.** `O`→`0` is a very likely scanning error; `6`→`8` is not. Plain Levenshtein can't tell them apart, so many codes tie for first place.
2. **A swap counts as 2.** `ITEM000816` vs `ITEM000186` is one slip, but scores like two unrelated changes.
3. **Missing padding is expensive.** `ITEM214` needs three inserted zeros, which costs 3.

Trigram similarity is worse for codes. Every code starts with `ITEM000`, so most trigrams are shared and swaps fall to rank 102.

Our distance fixes all three, with costs kept in tables you can show and edit:

| Edit | Cost | Example |
|---|---|---|
| OCR look-alike substitution | 0.25 | `O↔0`, `I/L↔1`, `S↔5`, `B↔8`, `Z↔2`, `G↔6`, `A↔4` |
| Neighbouring-key substitution | 0.5 | `E↔R`, `9↔0` |
| Neighbouring characters swapped | 0.6 | `193↔139` |
| Missing / extra `0` | 0.5 | `ITEM214` → `ITEM000214` = 1.5 |
| Missing / extra other character | 1.0 | `ITM` → `ITEM` |
| Any other substitution | 1.0 | |

Example output of `code_edit_steps('lTEM0OO183', 'ITEM000183')`:

| step | operation | noisy | candidate | cost | reason |
|---|---|---|---|---|---|
| 1 | replace | L | I | 0.25 | OCR look-alike |
| 2 | replace | O | 0 | 0.25 | OCR look-alike |
| 3 | replace | O | 0 | 0.25 | OCR look-alike |

## Results: codes only, no context

For each of the 20 noisy codes stored in the distributor and vendor DBs, all 303 manufacturer codes were ranked. A record counts as **correct** only if the true item is *alone* in first place.

| Method | Correct (of 20) |
|---|---|
| Plain Levenshtein (`plain_levenshtein`) | 11 |
| Levenshtein after our normalisation | 11 |
| Trigram similarity (`trigram_similarity`) | 13 |
| **Ours (weighted Damerau-Levenshtein)** | **19** |

| Record | Levenshtein | Trigram | Ours |
|---|---|---|---|
| D02 `ITEM0000BB` | 1st, **99-way tie** | 10th | **1st** |
| D04 `ITEM000816` (swap) | 4th | **102nd** | **1st** |
| V03 `ITEM0000B4` | 1st, 10-way tie | 10th | **1st** |
| V07 `ITEM000910` (swap) | 4th | 102nd | 2nd |
| V12 `ITEM214` | 1st | 1st | **1st** |

Full per-record table: run `eval_code_ranking.sql`.

### What codes alone cannot do (→ step 3)

- **V07 `ITEM000910`:** `ITEM000010` is also one slip away (9 and 0 are neighbouring keys). On the code alone both explanations are fair. The pack context (Doxycycline vs Paracetamol) separates them.
- **V16 `ITEM00017`:** the three closest codes (`017`, `107`, `170`) are all wrong. The true candidates (`171`/`173`/`178`) are slightly further away. So candidate search must take **everything above a similarity threshold**, not just the top few, and let context filter.
- **V06 / V15** (a typo that lands on another real code) score a perfect 0 on the code. Only context can expose them.

This is the argument for combining code distance with name, company and date similarity, which is step 3.

## Replacing the extensions (19 Oct)

The professor asked us not to use `fuzzystrmatch` or `pg_trgm`. Only three calls used them (`similarity()` for medicine and company names, `dmetaphone()` for sound-alike names); the code matching was always our own. They were replaced by our own `trigram_similarity()` and `soundex_code()`.

Checked against the extension versions before removing them:

| Comparison | Pairs compared | Differences |
|---|---|---|
| `trigram_similarity` vs pg_trgm `similarity`, names and companies | 2,896 | 0 |
| `trigram_similarity` vs pg_trgm, noisy codes × all items | 7,272 | 0 |
| `plain_levenshtein` vs fuzzystrmatch `levenshtein`, same codes | 7,272 | 0 |
| `soundex_code` vs `dmetaphone`: "sounds the same?" on drug words | 1,089 | 0 |
| Final name/company scores | 2,896 | 49 differ in the 3rd decimal only (pg_trgm uses lower-precision numbers) |

The comparison table above, all 24 stored-record verdicts, all buyer searches, the vice-versa results and all 18 GUI test scenarios are **identical** before and after.
