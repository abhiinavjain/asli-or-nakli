# Phase 2 · Step 6 — Mediator refactor: sources find candidates, the mediator decides

This step implements the professor's feedback on the mediator. The design is in the proposal doc *Asli-or-Nakli: Mediator Refactor Proposal*.

| Requirement | What we built |
|---|---|
| 1. Don't fetch all data | Every source finds its own candidates with an index and returns at most `probe_k` (5) tuples per pass. A buyer search now ships **6 rows instead of 331**. |
| 2. Record-level matching | The mediator receives candidate tuples in one shape from every source. It then does entity matching (which item) and context matching (name, company, dates, supply chain). |
| 3. Dynamic weights | Each attribute weight = base weight × how well it separates *these* candidates × how reliable the record's source has been for it. |
| 4. Genuine record identification | `record_trust(item)` gives every record of an item a confidence from six factors: entity, context, completeness, attribute reliability, source reliability and consistency. |
| 5. Final decision | The top record is accepted only if it is trusted enough and clearly ahead of the records that disagree; otherwise REVIEW. Cleansing votes are weighted by reliability. |
| Scale | A source registry (`asli_sources`); adding a source is one INSERT. Tested with a 1,000,000-record source: a probe ships 5 rows in about 0.35 s. |

**No existing table, column or constraint is changed.** The sources only get an extension (functions only) and expression indexes. The mediator gets three new tables: `asli_sources`, `source_attribute_reliability` and settings rows in `match_config`.

## Install (in this order)

**0. Backups** of all four databases, as before.

| # | Where | What | Expect |
|---|---|---|---|
| 1 | **every** machine (all 3 sources + mediator) | copy `asli_match/asli_match.control` and `asli_match/asli_match--1.0.sql` into PostgreSQL's `share\extension` folder: right-click `install_extension_windows.bat` → *Run as administrator* (edit `PGVER` if not 18) | "Done." |
| 2 | manuf_db | `manufacturer_06_candidate_indexes.sql` (Alt+X) | 4 index names |
| 3 | distributor_db | `distributor_06_candidate_indexes.sql` | 3 index names |
| 4 | vendor_db | `vendor_06_candidate_indexes.sql` | 4 index names |
| 5 | mediator_db | `mediator_06_sources.sql` | 5 checks PASS |
| 6 | mediator_db | `../step3/mediator_03_candidate_search.sql` (**updated**) | 8 checks PASS (4–6 may SKIP) |
| 7 | mediator_db | `../step5_cleansing/mediator_05_cleansing.sql` (**updated**) | 5 checks PASS |
| 8 | GUI machine | replace `gui.py` (**updated**), restart Streamlit | 7 tabs |

The extension must be the **same version (1.0) on all four databases**. postgres_fdw only sends a function to a source when that source has the same extension installed.

On Linux/macOS, copy the two files into `$(pg_config --sharedir)/extension/` instead of using the `.bat`.

## How it works

```
buyer types a code ──► mediator: asli_probe(code, name, expiry)
                          │  keys = asli.keys(code)   (~19 blocking keys)
                          ▼
     for each enabled source in asli_sources  (parallel-ready, a failing source is skipped)
        code pass    : WHERE asli.keys(code_col) && keys  ORDER BY asli.dist(...) LIMIT k   ─┐ all run AT
        fold pass    : WHERE asli.fold(code_col) = ANY(folded codes)                          │ the source,
        context pass : WHERE asli.name_key(name) = .. AND asli.month_key(expiry) = ..  (only   │ through its
                       when no close code fits the pack)                                      ─┘ own indexes
                          │  ≤ k tuples per pass, same shape from every source
                          ▼
     mediator: entity matching → context matching with dynamic weights → verdict
               record_trust(): six-factor confidence per record → most reliable / REVIEW
```

- **`asli.fold(code)`** reads a code the way a person means it. Look-alike letters become digits (O→0, I/l→1, S→5, B→8, G→6, Z→2), Cyrillic look-alikes are replaced, and the number is padded to 6 digits. So `lTEM0OO183` folds to `ITEM000183`.
- **`asli.keys(code)`**: every code one typing error away shares at least one key with it. The keys cover one wrong digit, two digits swapped, and one digit missing or extra. Recall on all 28 noisy codes in the noise catalogue: 28 of 28.
- **Pushdown.** The source runs the WHERE, ORDER BY and LIMIT itself. This works because the functions live in an extension listed in the server's `extensions` option. `use_remote_estimate` lets the planner see that this is cheaper than shipping rows. Inside `asli_probe`, local sorting is switched off so ORDER BY … LIMIT k always runs at the source.
- **Reliability** starts at 0.9 for everyone (`reliability_prior`). *CHECK APPLIED FIXES* recomputes it from the cleansing history: records checked versus fixes needed, per source and per attribute. After one full cleansing cycle on data v2, the vendor is the least reliable source (0.91 overall, 0.93 for codes).

## Results on the local copy (data v2)

Rows were counted from the sources' own query plans.

| Operation | Before | After |
|---|---|---|
| Buyer search (Verify) | 331 rows | **6 rows**, ~0.3 s |
| Noise-aware verification | 3,494 rows | **99 rows** |
| Find records of an item | 1,975 rows | **80 rows** |
| One stored record (Data health → Explain) | ~600 rows | **14 rows** |
| Phase 1 view, one item | 3 rows | 3 rows |
| Data health (every record once, by design) | 890 rows | 840 rows |
| Full cleansing scan | 44,278 rows | **2,680 rows** (each record read once + small probes), ~17 s |
| Probe against a 1,000,000-record source | — | **5 rows**, ~0.35 s |

**Same results as before.**

- All 37 GUI tests pass, including 3 new ones for this step.
- The 26 Verify cases give the same verdicts.
- The full cleansing cycle gives the same result: 40 fixes + 7 decisions, 41 changes, 0 anomalies, GENUINE 164 → 187.
- Every live-edit scenario gives the same proposals: the 3 noise scripts, the professor's case, ITEM0003O0/O1, the 18 `anywhere_*` edits, and the deleted, modified and inserted records.

**Known limit.** The context pass (only used when no close code fits the pack) sorts one batch at the source. On the 1,000,000-record test source a batch is about 16,000 rows, which takes about 2.5 s there. It still ships at most `fetch_size` (25) rows.

## New in the GUI

- **🔍 Verify:**
  - *⚖️ How the attributes were weighted*: base weight vs the weight used for this search, and how many candidates the sources sent.
  - *🛡️ Which stored record is most trustworthy*: the six factors per record and the decision.
- **🔁 Find records:** the same trust table for the item.
- **🩺 Data health:** *🏛️ Sources and what the mediator has learned*, showing the registry and the reliability per source and attribute.
- **⚙️ Matching settings:** the new settings appear in the table: `probe_k`, `beta_*`, `trust_*`, `vote_accept_share`, `discrimination_floor`, `reliability_*`, `context_pass_above`.

## Optional scale test

1. Create the database `scale_db`.
2. Run `scale_test/scale_01_build_source.sql` on it. This makes 1,000,000 records and takes about 1 minute.
3. Run `scale_test/scale_02_register_and_measure.sql` on the mediator. It registers the database as a fourth source, shows that a probe returns 5 rows, and switches the source off again.

## Demo lines (viva)

- "The mediator never reads a source table. It sends a probe, and each source answers with at most five candidates from its own index."
- "Weights are not fixed. A field every candidate shares can't tell them apart, so its weight shrinks. A source that needed many fixes counts for less."
- "When records disagree we don't take the closest code. Each record gets a confidence from six factors, and the top one must be clearly ahead of the records that disagree, or a person decides."
