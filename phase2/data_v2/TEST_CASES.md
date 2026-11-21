# Data v2 — test cases for the demo

All codes below were checked on the loaded **noisy demo data** (results come from the real `global_medicine_history` view).
Items that carry Phase 2 noise are **not** listed here, so these results don't change until cleansing.

## Phase 1 — exact item codes (type in 🔍 Verify medicine, nothing else needed)

| Case | Item codes | Expected result |
|---|---|---|
| Genuine, sold (95 items) | `ITEM000003`, `ITEM000006`, `ITEM000007`, `ITEM000013`, `ITEM000015`, `ITEM000016`, `ITEM000017`, `ITEM000020` | GENUINE · history ends ✓ Sold |
| Genuine, still in stock (62 items) | `ITEM000010`, `ITEM000011`, `ITEM000026`, `ITEM000029`, `ITEM000033`, `ITEM000034`, `ITEM000039`, `ITEM000042` | GENUINE · Not Sold |
| Unapproved (10 items) | `ITEM000062`, `ITEM000071`, `ITEM000144`, `ITEM000158`, `ITEM000188`, `ITEM000194`, `ITEM000216`, `ITEM000237` | NAKALI / UNAPPROVED (reported) |
| Unapproved, and sold (6 items) | `ITEM000054`, `ITEM000066`, `ITEM000219`, `ITEM000231`, `ITEM000259`, `ITEM000285` | NAKALI / UNAPPROVED · Sold |
| Expired (11 items) | `ITEM000021`, `ITEM000022`, `ITEM000023`, `ITEM000079`, `ITEM000080`, `ITEM000123`, `ITEM000124`, `ITEM000125` | SUSPICIOUS · EXPIRED ITEM |
| Expired, and sold (6 items) | `ITEM000025`, `ITEM000076`, `ITEM000077`, `ITEM000122`, `ITEM000292`, `ITEM000294` | SUSPICIOUS · EXPIRED ITEM · Sold |
| At a shop, no distributor record (12 items) | `ITEM000046`, `ITEM000056`, `ITEM000067`, `ITEM000073`, `ITEM000103`, `ITEM000104`, `ITEM000129`, `ITEM000134` | SUSPICIOUS · DISTRIBUTOR RECORD NOT FOUND |
| Made, never shipped (no distributor, no shop) (10 items) | `ITEM000009`, `ITEM000019`, `ITEM000031`, `ITEM000037`, `ITEM000085`, `ITEM000127`, `ITEM000132`, `ITEM000196` | SUSPICIOUS · DISTRIBUTOR RECORD NOT FOUND |
| At distributor, not at any shop yet (30 items) | `ITEM000008`, `ITEM000012`, `ITEM000014`, `ITEM000018`, `ITEM000040`, `ITEM000043`, `ITEM000053`, `ITEM000055` | SUSPICIOUS · VENDOR RECORD NOT FOUND |
| Shop names a different distributor (12 items) | `ITEM000030`, `ITEM000048`, `ITEM000051`, `ITEM000061`, `ITEM000152`, `ITEM000203`, `ITEM000211`, `ITEM000220` | SUSPICIOUS · DISTRIBUTOR ID MISMATCH (+ red mismatch line) |
| Several problems: expired + unapproved (4 items) | `ITEM000078`, `ITEM000228`, `ITEM000291`, `ITEM000295` | NAKALI / UNAPPROVED (first rule wins) |
| Several problems: expired + no distributor record (4 items) | `ITEM000024`, `ITEM000121`, `ITEM000227`, `ITEM000293` | EXPIRED ITEM (first rule wins) |
| Several problems: unapproved + distributor mismatch (5 items) | `ITEM000072`, `ITEM000096`, `ITEM000212`, `ITEM000233`, `ITEM000251` | NAKALI / UNAPPROVED + red mismatch line |

**Counterfeit codes held by shops** (the manufacturer never made them): `ITEM583920`, `ITEM771045`, `ITEM586491`, `ITEM640558`, `ITEM315790`, `ITEM827364`.
Phase 1: ITEM NOT FOUND. Phase 2: NO MATCH, with a button to report it. Cleansing: REVIEW → ⭐ report as counterfeit (record kept as evidence). Sold: `ITEM583920`, `ITEM771045`.

`test_cases_v2.csv` lists every item with its case and the actual result.

## Phase 2 — noisy codes (🔍 Verify medicine; fill the pack details as shown)

| Type this code | Medicine name | Expiry | What it tests | Result (checked on the demo data) |
|---|---|---|---|---|
| `ITEM0O0041` | Ibuprofen 400mg | 11/2027 | O typed instead of 0 | **MATCH → ITEM000041** |
| `1TEM000098` | Aspirin 75mg | 01/2028 | 1 instead of I | **MATCH → ITEM000098** |
| `item-000202` | Naproxen 250mg | 02/2028 | lowercase, dash, spaces | **MATCH → ITEM000202** |
| `ITEM214` | Glimepiride 2mg | 02/2028 | zeros missing | **MATCH → ITEM000214** |
| `lTEM0OO183` | Doxycycline 100mg | 01/2028 | three look-alike errors | **MATCH → ITEM000183** |
| `ITEM000910` | — | — | swapped digits, NO pack details | **REVIEW** |
| `ITEM000910` | Doxycycline 100mg | 03/2028 | same code + pack details | **MATCH → ITEM000190** |
| `ITEM000193` | Calcium 500mg | 02/2028 | typo lands on another real code | **WRONG CODE → ITEM000139** |
| `ITEM000002` | Paracetamol 500mg | 11/2027 | correct code; manufacturer's copy is noisy (M01) | **NOISY MANUFACTURER RECORD → ITEM0OO002** |
| `ITEM000106` | Amoxicillin 500mg | 12/2029 | real code on an Amoxicillin pack | **POSSIBLE CLONED CODE** |
| `ITEM000153` | Montelukast 10mg | 01/2029 | real code, pack expiry one year off | **CONTEXT ERROR → ITEM000153** |
| `ITEM583920` | — | — | counterfeit code | **NO MATCH** |

## Phase 2 — 🔁 Find records for an item

| Type | Result (checked) |
|---|---|
| `ITEM000106` | distributor ITEM000106 (EXACT CODE), vendor ITEM000106 (EXACT CODE), vendor ITEM000l06 (NOISY VARIANT) |
| `ITEM000139` | distributor ITEM000139 (EXACT CODE), vendor ITEM000193 (NOISY VARIANT) |
| `ITEM000171` | distributor ITEM000171 (EXACT CODE), vendor ITEM00017 (POSSIBLE) |
| `ITEM000287` | vendor ITEM000287 (EXACT CODE), distributor ITEM0002B7 (NOISY VARIANT) |
| `ITEM000255` | distributor ITEM000255 (EXACT CODE), vendor ITEM000255 (EXACT CODE), distributor ITEM0002S5 (NOISY VARIANT) |
