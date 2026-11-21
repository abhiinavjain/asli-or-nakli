# Phase 2 · Step 3 — Combined scoring and candidate search

Runs on **`mediator_db` only**, after step 2.

## How to run

1. Open `mediator_03_candidate_search.sql` in DBeaver on **mediator_db** and run it as a script (**Alt+X**).
2. The last result tab shows 8 checks, which take a few seconds. **All must say PASS**; checks 4–6 say SKIP once the noisy records have been cleansed.
3. Optional: run `eval_step3.sql` (Alt+X) for the three results tables below. It is read-only and takes ~30–60 s.

The script can be re-run safely. It drops and recreates its own functions; your `match_config` values are kept.

## What it adds

| Object | Use |
|---|---|
| `v_golden_items` | Manufacturer's item list with medicine and company names (the reference) |
| `v_stored_records` | Distributor + vendor rows under **one set of column names**: the schema mapping, made explicit |
| `v_stored_record_flags` | Every stored row: **OK**, **UNKNOWN CODE**, or **CONTEXT CONFLICT** (with the issues listed) |
| `search_by_pack(code, name, company, mfg, expiry, limit, shop, distributor)` | **Buyer search.** Everything except the code is optional. The pack gives manufacturer data; the bill gives the shop (vendor data) and the distributor (distributor data, name or ID) |
| `match_stored_record(source, record_id)` | Which real item a distributor/vendor row is |
| `find_records_for_item(item_code)` | **Vice versa.** A real item → every record in the other DBs that is, or looks like, that item |
| `match_candidates(...)` | The core the three above share |

## How a search works

**Stage 1: approximate code match.** Every manufacturer item whose code similarity (step 2's weighted distance) is **≥ 0.80** becomes a candidate. That's up to about 2 unrelated edits, or 8 look-alike ones. It deliberately casts a wide net, because V16 shows the true item isn't always the closest code.

**Stage 2: context.** Each candidate is scored on whatever evidence is available:

| Evidence | Weight | Available for |
|---|---|---|
| Item code | 0.40 | always |
| Medicine name (vs name *and* composition) | 0.30 | pack, stored rows |
| Expiry date | 0.15 | pack, stored rows |
| Manufacturer | 0.10 | pack, stored rows |
| Mfg date | 0.05 | pack, stored rows |
| Distributor ID agrees with the other DB | 0.10 | stored rows |
| Distributor says it supplied this item **to this shop** (counts only when it agrees) | 0.10 | vendor rows |

**Total = weighted average of the evidence that exists.** A blank field is left out, not scored as 0.

If the mfg and expiry dates match the candidate *crossed over*, they are scored as matching and flagged `dates_swapped` for cleansing.

## Verdicts

| Verdict | Rule |
|---|---|
| **EXACT MATCH** | Code exists exactly and the context agrees |
| **MATCH** | Best ≥ 0.85, **and** it leads the runner-up by ≥ 0.10 in total **or** by ≥ 0.5 in code edit cost with context at least as good. Also used when the code only differs by formatting (`item-000202`) |
| **CONTEXT ERROR** | Code is real and the medicine name agrees, but other fields (e.g. expiry) are wrong |
| **WRONG CODE** | Code is real but belongs to a different medicine, and another item fits the context (≥ 0.85, context ≥ 0.8) |
| **NOISY MANUFACTURER RECORD** | The distributor *and* the vendor both hold this exact code but the manufacturer doesn't: the manufacturer's copy is noisy (majority 2 of 3). Only items no other database holds are candidates; the item is the manufacturer's noisy record |
| **POSSIBLE CLONED CODE** | Buyer only: the code is real, the pack contradicts it (name, manufacturer or expiry), and nothing else fits. Treat as **NAKALI** |
| **REVIEW** | More than one plausible item, so a person decides. The system never guesses |
| **NO MATCH** | Nothing reaches 0.60, or no candidate at all (the function returns no rows) |

**Why the second MATCH condition exists.** Items in one batch (e.g. ITEM000041–050) share medicine, company and dates. Context can't separate them, so a 0.25 vs 0.75 code difference changes the total by only ~0.02. The rule lets a clearly better code win **only when the context is not worse**. That's the "context narrows it down, the code decides" logic the professor described with the number plates.

All weights and thresholds live in `match_config`.

## Results

### A) All 24 noisy stored records → 24 / 24 as expected

| Record | Stored code | Verdict | Resolved to |
|---|---|---|---|
| D01–D05 | `ITEM0000S0`, `ITEM0000BB`, `ITEM00095`, `ITEM000816`, `ITEM-000263` | MATCH | true item each |
| D06 | `ITEM0002B7` | MATCH, **dates swapped detected** | ITEM000287 |
| V01–V05, V07–V14 | 13 noisy codes | MATCH | true item each |
| V06 | `ITEM000193` (a real code) | **WRONG CODE** | ITEM000139 |
| V15 | `ITEM000209` (a real code) | **WRONG CODE** | ITEM000200 |
| V16 | `ITEM00017` | **REVIEW** (171 / 173 tied at 0.967) | — |
| V17 | `ITEM000l06` | MATCH | ITEM000106 (cleansing will treat it as a duplicate) |
| V18 | `ITEM000153` | **CONTEXT ERROR** | ITEM000153 (expiry wrong) |

V07 (`ITEM000910`) was the one miss with codes alone in step 2. With context it resolves to ITEM000190 (score 0.951), and ITEM000010 drops out.

### B) Buyer searches

| Scenario | Verdict | Item |
|---|---|---|
| Exact code, no context | EXACT MATCH | ITEM000001 |
| Noisy code only (`ITEM0O0041`) | MATCH | ITEM000041 |
| Noisy code + name + expiry | MATCH | ITEM000041 |
| Swapped digits, code only (`ITEM000910`) | **REVIEW** (ITEM000010 vs ITEM000190) | — |
| Same + "Doxycycline 100mg" | MATCH | ITEM000190 |
| Lost digit + name + expiry (`ITEM00017`) | **REVIEW** (171–179 identical to a buyer) | — |
| Typo onto a real code + context (`ITEM000193`, Calcium) | **WRONG CODE** ("did you mean") | ITEM000139 |
| Real code on an unrelated pack (`ITEM000106`, Amoxicillin) | **POSSIBLE CLONED CODE** | — |
| Garbage | NO MATCH (no rows) | — |

Rows 4 → 5 are the clearest demo of why context matters. The same code is ambiguous on its own and certain with one word from the pack.

### C) Vice versa

| Item | Records found in other DBs |
|---|---|
| ITEM000106 | distributor + vendor rows with the exact code · **`ITEM000l06`** (vendor) as a NOISY VARIANT |
| ITEM000139 | distributor exact row · **`ITEM000193`** (vendor) as a NOISY VARIANT |
| ITEM000193 | distributor exact row · vendor row with this code marked BELONGS ELSEWHERE → ITEM000139 |
| ITEM000171 | distributor exact row · **`ITEM00017`** as POSSIBLE (ambiguous) |
| ITEM000153 | distributor exact row · vendor row as EXACT CODE, CONTEXT ERROR |
| ITEM000287 | vendor exact row · **`ITEM0002B7`** (distributor) as a NOISY VARIANT |

## Speed (local test copy)

| Call | Time |
|---|---|
| `search_by_pack` | ~0.3–0.5 s |
| `match_stored_record` | ~0.6 s |
| `find_records_for_item` | ~2 s |

Over the network between your machines, expect these to be slower. Every call fetches each remote table **once** (`MATERIALIZED`), not once per candidate.

## Updated 20 Oct (re-run this script)

- **Majority rule for codes** → new verdict NOISY MANUFACTURER RECORD (see the table above). Needed now that the manufacturer can be noisy.
- **Supply evidence only counts when it agrees.** A record at a different shop than the distributor's supply table says is a Phase 1 supply anomaly, not proof that the record is a different item. Before this change, a new record at an arbitrary shop could push its true item out of the candidate list.
- **Context tolerance 0.05** in the "clearly better code" rule (`context_tolerance` in `match_config`). One extra piece of supporting evidence on a neighbouring item no longer blocks a clearly better code. Found when the noisy medicine name M03 turned V17 into REVIEW.
- **The checks no longer depend on how much noise is present.**

The 24 step-1 records still resolve to exactly the same verdicts and items. Only some runner-up candidates differ.


## Buyer input from all three databases (update, 17 Nov)

The buyer's input now carries a little of every database, not only the manufacturer's:

| Input | Checked against | How it is used |
|---|---|---|
| Item code, medicine name, manufacturer, mfg, expiry (the pack) | manuf_db | entity + context matching, as before |
| **Shop** bought from (the bill) | vendor_db (`vendor_inventory` + `vendors`) and distributor_db (`supplied_items.vendor_reference`) | `supply_score` = 1 when the shop holds the item, or the distributor supplied the item to that shop |
| **Distributor** on the bill (name or ID) | distributor_db (`inventory_items`) and the vendor's `distributor_id` | `distributor_score` = 1 when that distributor holds the item, or the shop's record names it |
| **Purchase date** (the bill) | vendor_db (`received_date`, `medicine_sales.sale_date`) | GUI check only: a purchase before the shop received the item, or after expiry, is flagged |

- Bill evidence is **positive only**: a match raises the candidate's score (weights `w_distributor`, `w_supply`); a mismatch is not counted against the item, because it says something about *this pack*, not about which item the code means. Records stored under a noisy copy of the code count too (looked up by folded code at the sources, no extra table reads).
- In the GUI, the verification shows **"Your bill vs the records"**. If the shop or distributor does not match, the result reads **GENUINE CODE, BILL DOES NOT MATCH** (a genuine code may have been copied onto this pack) and offers a report button. It is not reported automatically, because the item's own records are clean.
- No schema change: only `search_by_pack` gets two optional parameters (old calls with 5 or 6 arguments still work).
- Checks 7 and 8 test the shop and distributor evidence.
