# Phase 2 · Step 4 — GUI

`gui.py` replaces the Phase 1 GUI. It needs **steps 2 and 3 run on mediator_db** first.

## How to run

1. **Keep a copy of the old GUI**, e.g. rename it to `gui_phase1.py`.
2. Put the new `gui.py` in its place. `DB_CONFIG` is unchanged (same host, database, user and password as your Phase 1 file).
3. `streamlit run gui.py`

No new libraries: still only `streamlit`, `psycopg2` and `pandas` (plus Python's built-in `json`).

## Tabs (7)

| Tab | What it does |
|---|---|
| 🔍 **Verify medicine** | Item code + optional pack details (name, manufacturer, mfg, expiry) → verdict, ranked candidates with scores, explanation of the code edits, then the full **Phase 1 verification** of the chosen item |
| 🔁 **Find records for an item** | Vice versa: a real item code → every distributor/vendor record that carries it or a noisy copy of it, with icons and counts |
| 🩺 **Data health** | Every stored record checked against the manufacturer; the ones that need attention, and "Explain" for any one of them |
| 🧹 **Data cleansing** | Run a scan (majority vote across the 3 databases), resolve reviews, **download a fix script per database**, check which fixes the owners applied, cleansing log. See `step5_cleansing/README.md` |
| 📢 **Reports** | Phase 1 reports table (unchanged) |
| 📊 **Analysis** | Phase 1 analysis (unchanged) |
| ⚙️ **Matching settings** | Weights, thresholds and character costs, read-only, with how the verdict is decided |

### What each verdict does on the Verify tab

| Verdict | Shown | Item verified | Report filed |
|---|---|---|---|
| EXACT MATCH / MATCH | ✅ green, "resolved to X" | the matched item | as in Phase 1, if suspicious |
| WRONG CODE | ⚠️ "Did you mean X?" | X (the item that fits the pack) | as in Phase 1, if suspicious |
| CONTEXT ERROR | 🚨 + pack-vs-record table | the item with that code | **PACK DETAILS DIFFER FROM RECORD** |
| POSSIBLE CLONED CODE | 🚨 + pack-vs-record table | the genuine item with that code (marked "not the pack in your hand") | **POSSIBLE CLONED CODE** |
| REVIEW | ❓ "choose" | **nothing until the user picks** | only after picking |
| NO MATCH | ❌ "very likely fake" | — | **CODE NOT FOUND**, when the button is pressed |
| NOISY MANUFACTURER RECORD | ⚠️ "distributor and vendor record X, the manufacturer's record reads Y" | Y (the manufacturer's noisy record) | **none**: the suspicion comes from our own data; fix it on the Data cleansing tab |

The Phase 1 verification code was moved into a function (`show_verification`) **without changing its logic**, so any candidate can be verified. The Phase 1 query, report and analysis functions are untouched.

## Demo script (all tested)

| Type in Verify tab | Expect |
|---|---|
| `ITEM000001` | EXACT MATCH → GENUINE |
| `ITEM0O0041` + "Ibuprofen 400mg" + `MAR-2028` | MATCH → ITEM000041 |
| `ITEM000910` alone | REVIEW (ITEM000010 vs ITEM000190) |
| `ITEM000910` + "Doxycycline 100mg" | MATCH → ITEM000190 |
| `ITEM000193` + "Calcium 500mg" + "LifeWell Laboratories" + `05/2028` | WRONG CODE → did you mean ITEM000139 |
| `ITEM000106` + "Amoxicillin 500mg" + `12/2029` | POSSIBLE CLONED CODE → reported |
| `ITEM000153` + "Montelukast 10mg" + `05/2029` | CONTEXT ERROR → reported |
| `ZZZ-998877` | NO MATCH → report button |

| Type in Find-records tab | Expect |
|---|---|
| `ITEM000106` | 2 exact records + noisy `ITEM000l06` |
| `ITEM000139` | 1 exact + noisy `ITEM000193` |
| `ITEM000171` | 1 exact + `ITEM00017` as possible |

## How it was tested

Streamlit can't be installed in my environment, so the GUI was run headlessly: a stand-in for Streamlit replays clicks and inputs and records everything the page would display, and a stand-in for psycopg2 sends every query to a local copy of your four databases.

**27 scenarios pass**: every verdict path, candidate selection across reruns, reporting, every tab and the refresh button, plus the whole cleansing flow driven through the GUI (scan, resolve both reviews, run the three downloaded scripts, check applied, rescan clean, verify GENUINE afterwards). The layout itself has not been seen in a browser yet. Please check it when you run it.

## For rubric 3 (prompt → generated code → your changes)

`PROMPT_gui.md` is the prompt this `gui.py` was generated from (with the Phase 1 `gui.py` attached).

1. **Before anyone edits anything**, commit both files as they are:
   ```
   git add PROMPT_gui.md gui.py
   git commit -m "GUI as generated from PROMPT_gui.md"
   ```
2. Make your team's changes and commit them separately.
3. In the demo, `git diff <first commit> -- gui.py` shows exactly the changes you made to the generated code.
