# Phase 2 · Step 1 — Context columns + noisy data

## What this step does

1. **Adds context columns** to the distributor and vendor databases, so each source records what it knows about an item (medicine name, manufacturer, dates), each in its own naming and format.
2. **Fills those columns** for every existing row, using the manufacturer's data.
3. **Inserts 24 noisy records** (18 vendor, 6 distributor) for the matching and cleansing demo.
4. **Exposes the new columns** to the mediator through FDW.

The manufacturer database is **not changed**.

## Schema mapping after this step

| Meaning | Manufacturer | Distributor (`inventory_items`) | Vendor (`vendor_inventory`) |
|---|---|---|---|
| Item code | `unique_item_code` | `product_code` | `item_identifier` |
| Medicine name | `medicines.medicine_name` | `drug_name` (UPPER CASE) | `medicine_name` |
| Manufacturer | `manufacturers.manufacturer_name` | `mfr_name` (UPPER CASE) | `company` |
| Mfg date | `manufacturing_date` (DATE) | `mfg_date` (DATE) | `mfg` (TEXT, `MM/YYYY`) |
| Expiry date | `expiry_date` (DATE) | `exp_date` (DATE) | `expiry` (TEXT, `MM/YYYY`) |

## How to run

**Before anything:** each owner takes a backup of their own database, e.g.
`pg_dump -U postgres -d distributor_db -f distributor_backup_before_phase2.sql`

| Order | Who | Database | File |
|---|---|---|---|
| 1 | Distributor owner | `distributor_db` | `distributor_01_context_columns.sql` |
| 2 | Distributor owner | `distributor_db` | `distributor_02_noisy_records.sql` |
| 3 | Vendor owner | `vendor_db` | `vendor_01_context_columns.sql` |
| 4 | Vendor owner | `vendor_db` | `vendor_02_noisy_records.sql` |
| 5 | Mediator owner | `mediator_db` | `mediator_01_fdw_columns.sql` (after 1–4) |

Steps 1–2 and 3–4 can run in parallel on their own machines. Every script ends with a check query and can be re-run safely (nothing is duplicated or overwritten).

**Expected results**
- `distributor_01` / `vendor_01`: `rows_without_context = 0`
- `distributor_02`: 6 rows listed · `vendor_02`: 18 rows listed
- `mediator_01`: 5 sample rows from each foreign table, with context filled in

## Noise catalogue (ground truth — keep this out of the databases)

`noise_catalogue.csv` has the same data in machine-readable form, for the accuracy test harness later.

| ID | DB | Stored code | True code | Noise | Stored context | Expected result |
|---|---|---|---|---|---|---|
| V01 | vendor | `ITEM0O0041` | ITEM000041 | OCR look-alike: O for 0 | Ibuprofen 400mg · Sunrise Pharmaceuticals · 03/2028 | AUTO-FIX |
| V02 | vendor | `1TEM000098` | ITEM000098 | OCR look-alike: 1 for I | Aspirin 75mg · HealthPlus Pharma · 04/2028 | AUTO-FIX |
| V03 | vendor | `ITEM0000B4` | ITEM000084 | OCR look-alike: B for 8 | Diclofenac 50mg · **MediCare Labs** · **MAR-2028** | AUTO-FIX |
| V04 | vendor | `ITEM00112` | ITEM000112 | Missing character | **Losartan Potassium 50mg** · HealthPlus Pharma · 04/2028 | AUTO-FIX |
| V05 | vendor | `ITEM0000165` | ITEM000165 | Extra character | Levocetirizine 5mg · NovaMed Pharmaceuticals · 05/2028 | AUTO-FIX |
| V06 | vendor | `ITEM000193` | ITEM000139 | Transposed digits → **another real code** | Calcium 500mg · LifeWell Laboratories · 05/2028 | NEEDS CONFIRMATION |
| V07 | vendor | `ITEM000910` | ITEM000190 | Transposed digits | **Doxycyclin** 100mg · CureLife Pharma · **6/28** | AUTO-FIX |
| V08 | vendor | `item-000202` | ITEM000202 | Lowercase + separator | Naproxen 250mg · CureLife Pharma · 06/2028 | AUTO-FIX |
| V09 | vendor | `ITEM 000248` | ITEM000248 | Embedded space | Clopidogrel 75mg · **PrimeHealth Pharma** · 07/2028 | AUTO-FIX |
| V10 | vendor | `ITRM000107` | ITEM000107 | Keyboard slip (R next to E) | Metformin 500mg · HealthPlus Pharma · 04/2028 | AUTO-FIX |
| V11 | vendor | `ITM000174` | ITEM000174 | Prefix variant | **Rabeprazol 20 mg** · NovaMed Pharmaceuticals · 05/2028 | AUTO-FIX |
| V12 | vendor | `ITEM214` | ITEM000214 | Unpadded number | Glimepiride 2mg · WellCare Laboratories · **2028-06** | AUTO-FIX |
| V13 | vendor | `ITЕM000268` | ITEM000268 | Unicode look-alike (Cyrillic Е) | Domperidone 10mg · PrimeHealth Pharmaceuticals · 08/2028 | AUTO-FIX |
| V14 | vendor | `lTEM0OO183` | ITEM000183 | Three OCR errors (l, O, O) | Doxycycline 100mg · **Cure Life Pharma** · 06/2028 | AUTO-FIX |
| V15 | vendor | `ITEM000209` | ITEM000200 | One digit wrong → **another real code** | Cefixime 200mg · CureLife Pharma · 06/2028 | NEEDS CONFIRMATION |
| V16 | vendor | `ITEM00017` | 171 / 173 / 178 | Last digit lost | Rabeprazole 20mg · NovaMed Pharmaceuticals · 05/2028 | **REVIEW — must not auto-fix** |
| V17 | vendor | `ITEM000l06` | ITEM000106 | Duplicate of an existing row (l for 1) | Metformin 500mg · HealthPlus Pharma · 04/2028 | DUPLICATE → remove |
| V18 | vendor | `ITEM000153` | ITEM000153 | Clean code, wrong context | Montelukast 10mg · NovaMed Pharmaceuticals · **05/2029** | CONTEXT FIX → 05/2028 |
| D01 | distributor | `ITEM0000S0` | ITEM000050 | OCR look-alike: S for 5 | IBUPROFEN 400MG · SUNRISE PHARMACEUTICALS · 2028-03-01 | AUTO-FIX |
| D02 | distributor | `ITEM0000BB` | ITEM000088 | OCR look-alike: B for 8 (×2) | **DICLOFNAC** 50MG · MEDICARE LABORATORIES · 2028-03-29 | AUTO-FIX |
| D03 | distributor | `ITEM00095` | ITEM000095 | Missing character | ASPIRIN 75MG · HEALTHPLUS PHARMA · 2028-04-05 | AUTO-FIX |
| D04 | distributor | `ITEM000816` | ITEM000186 | Transposed digits | DOXYCYCLINE 100MG · CURELIFE PHARMA · 2028-06-07 | AUTO-FIX |
| D05 | distributor | `ITEM-000263` | ITEM000263 | Separator | **DOMPERIDONE 10 MG** · PRIMEHEALTH PHARMACEUTICALS · 2028-08-02 | AUTO-FIX |
| D06 | distributor | `ITEM0002B7` | ITEM000287 | OCR look-alike: B for 8 | LORATADINE 10MG · GLOBALMEDS INDIA LTD · **mfg/exp swapped** | AUTO-FIX + DATE FIX |

**Bold** = noisy context value.

### Why these records were chosen
- **V01–V15, D01–D06** belong to real, approved, unexpired items whose record is missing in that database today. Once cleansed, they link up across all three sources and verify as **GENUINE**. That gives the demo a visible before/after.
- **V06 and V15** are the hardest kind of noise: a one-character slip that lands on *another valid code*. Edit distance alone can never catch them; only context can.
- **V16** is deliberately unresolvable. The system must say "I can't decide" instead of guessing.
- **V17** and **V18** cover duplicate records and wrong context on an otherwise clean record.

## Verified on a local copy

All scripts were run twice, in the order above, on a local PostgreSQL rebuilt from the team's dumps:

- Second run changed nothing (distributor: 287 rows, vendor: 103 rows).
- All rows have context. Unicode in V13 survives the FDW hop.
- The global view and every `gui.py` query still work. The materialized view refreshes.
- 15 vendor and 6 distributor noisy codes match no manufacturer code. V06, V15 and V18 do match real codes, by design.

## Known effect on the current (Phase 1) GUI

Until cleansing exists, three noisy rows change what the GUI shows:
- `ITEM000193` → DISTRIBUTOR ID MISMATCH (V06's wrong code)
- `ITEM000209` → **GENUINE**, although that vendor record really belongs to ITEM000200 (V15)
- `ITEM000153` → GENUINE, although the vendor's expiry is wrong (V18)

The `ITEM000209` case shows a real gap. The distributor sold ITEM000209 to *Wellness Pharmacy*, but *LifeCare* claims to hold it, and nothing checks `supplied_items.vendor_reference`. Phase 2 matching should use that field as context.
