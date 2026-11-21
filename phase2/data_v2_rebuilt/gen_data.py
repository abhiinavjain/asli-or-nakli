"""Rebuild distributor_db / vendor_db / mediator approvals data (data v2 style)
around the real manufacturer data extracted from manuf_db.

The original data v2 load scripts were never saved, so this regenerates rows that
follow data_v2/README.md, TEST_CASES.md and noise_catalogue_v2.csv:
  - every Phase 1 case, using the item codes listed in TEST_CASES.md
  - the V01-V18 / D01-D07 noisy records from the noise catalogue
  - 6 counterfeit codes in shops (2 sold)
Output: distributor_data.sql, vendor_data.sql, mediator_data.sql
"""
import csv, datetime as dt, random, re, sys
from pathlib import Path

MANUF = Path(sys.argv[1])          # folder with the extracted manuf_db tables (*.tsv)
CATALOGUE = Path(sys.argv[2])      # noise_catalogue_v2.csv
OUT = Path(sys.argv[3])
TODAY = dt.date(2026, 11, 21)
rnd = random.Random(231)

def tsv(name):
    return [l.split('\t') for l in (MANUF / f'{name}.tsv').read_text().strip().split('\n')]

medicines = {r[1]: r for r in tsv('medicines')}               # code -> row
makers = {r[0]: r[1] for r in tsv('manufacturers')}          # id -> name
items = {}                                                    # true code -> (medicine_code, mfg, exp)
for r in tsv('manufactured_items'):
    code = r[2]
    if r[0] == '2':                       # M01: manufacturer's copy is noisy, sources hold the true code
        code = 'ITEM000002'
    if re.fullmatch(r'ITEM\d{6}', code) and int(code[4:]) <= 300:
        items[code] = (r[1], dt.date.fromisoformat(r[3]), dt.date.fromisoformat(r[4]))
assert len(items) == 300, len(items)

def med_name(code): return medicines[items[code][0]][2]
def maker(code): return makers[medicines[items[code][0]][5]]
def mmyyyy(d): return d.strftime('%m/%Y')
def expired(code): return items[code][2] < TODAY

# ---------------------------------------------------------------- cases
listed = {
    'genuine_sold':    [3, 6, 7, 13, 15, 16, 17, 20],
    'genuine_stock':   [10, 11, 26, 29, 33, 34, 39, 42],
    'unapproved':      [62, 71, 144, 158, 188, 194, 216, 237],
    'unapproved_sold': [54, 66, 219, 231, 259, 285],
    'expired':         [21, 22, 23, 79, 80, 123, 124, 125],
    'expired_sold':    [25, 76, 77, 122, 292, 294],
    'shop_no_dist':    [46, 56, 67, 73, 103, 104, 129, 134],
    'never_shipped':   [9, 19, 31, 37, 85, 127, 132, 196],
    'dist_no_shop':    [8, 12, 14, 18, 40, 43, 53, 55],
    'mismatch':        [30, 48, 51, 61, 152, 203, 211, 220],
    'exp_unapproved':  [78, 228, 291, 295],
    'exp_no_dist':     [24, 121, 227, 293],
    'unapp_mismatch':  [72, 96, 212, 233, 251],
}
target = {'genuine_sold': 95, 'genuine_stock': 62, 'unapproved': 10, 'unapproved_sold': 6,
          'expired': 11, 'expired_sold': 6, 'shop_no_dist': 12, 'never_shipped': 10,
          'dist_no_shop': 30, 'mismatch': 12, 'exp_unapproved': 4, 'exp_no_dist': 4,
          'unapp_mismatch': 5}

cat = list(csv.DictReader(CATALOGUE.open(encoding='utf-8')))
noise = {r['id']: r for r in cat}
# items whose record is noisy (V01-V16 at the vendor, D01-D06 at the distributor)
v_items = {r['true_value']: r for r in cat if r['id'] in {f'V{i:02d}' for i in range(1, 17)}}
d_items = {r['true_value']: r for r in cat if r['id'] in {f'D{i:02d}' for i in range(1, 7)}}

case = {}
for c, nums in listed.items():
    for n in nums:
        case[f'ITEM{n:06d}'] = c
# special items
case['ITEM000193'] = 'dist_no_shop'     # V06 stores ITEM000193 at the vendor -> the real 193 must not be there
case['ITEM000209'] = 'dist_no_shop'     # V15 stores ITEM000209
case['ITEM000150'] = 'dist_no_shop'     # M08: only the distributor also holds it
for code in ['ITEM000106', 'ITEM000153', 'ITEM000255', 'ITEM000002', 'ITEM000005', 'ITEM000201']:
    case[code] = 'genuine_stock'
for code in v_items: case[code] = 'noisy_vendor'
for code in d_items: case[code] = 'noisy_dist'
for code in items:                      # remaining expired items
    if code not in case and expired(code):
        case[code] = 'expired'

counts = {c: sum(1 for v in case.values() if v == c) for c in target}
pool = [c for c in sorted(items) if c not in case]
rnd.shuffle(pool)
fill_order = ['dist_no_shop', 'genuine_stock', 'mismatch', 'shop_no_dist', 'never_shipped',
              'unapproved', 'unapproved_sold', 'unapp_mismatch', 'genuine_sold']
for c in fill_order:
    while counts[c] < target[c] and pool:
        case[pool.pop()] = c; counts[c] += 1
for code in pool: case[code] = 'genuine_sold'
assert not any(expired(c) for c, k in case.items() if not k.startswith(('exp',)) and k != 'expired'), \
    'a non-expired case got an expired item'

# ---------------------------------------------------------------- rows
distributors = [
    (1, 'Delhi Pharma Distributors', 'DL-DIST-001', 'Karol Bagh, New Delhi', '9810000001'),
    (2, 'MedSupply India', 'DL-DIST-002', 'Lajpat Nagar, New Delhi', '9810000002'),
    (3, 'HealthRoute Distributors', 'DL-DIST-003', 'Dwarka, New Delhi', '9810000003'),
    (4, 'PrimeMed Distributors', 'DL-DIST-004', 'Rohini, New Delhi', '9810000004'),
    (5, 'LifeCare Supply Network', 'DL-DIST-005', 'Saket, New Delhi', '9810000005')]
vendors = [
    (1, 'CityCare Medical Store', 'DL-VEN-001', 'Karol Bagh, New Delhi', '9820000001'),
    (2, 'Apollo Health Point', 'DL-VEN-002', 'Lajpat Nagar, New Delhi', '9820000002'),
    (3, 'Wellness Pharmacy', 'DL-VEN-003', 'Dwarka, New Delhi', '9820000003'),
    (4, 'LifeCare Medical Store', 'DL-VEN-004', 'Rohini, New Delhi', '9820000004'),
    (5, 'GreenCross Pharmacy', 'DL-VEN-005', 'Saket, New Delhi', '9820000005'),
    (6, 'MediTrust Pharmacy', 'DL-VEN-006', 'Janakpuri, New Delhi', '9820000006'),
    (7, 'HealthFirst Medicals', 'DL-VEN-007', 'Pitampura, New Delhi', '9820000007'),
    (8, 'CarePlus Pharmacy', 'DL-VEN-008', 'Mayur Vihar, New Delhi', '9820000008'),
    (9, 'PrimeCare Medical Store', 'DL-VEN-009', 'Rajouri Garden, New Delhi', '9820000009'),
    (10, 'SafeMeds Pharmacy', 'DL-VEN-010', 'Vasant Kunj, New Delhi', '9820000010')]
vname = {v[0]: v[1] for v in vendors}

def clamp(d, lo, hi): return max(lo, min(d, hi))
def later(d, a, b, cap=TODAY - dt.timedelta(days=2)): return clamp(d + dt.timedelta(days=rnd.randint(a, b)), d, cap)

def parse_ctx(s):
    """'Name · Company · mfg X · exp Y' -> dict (missing parts -> None)"""
    out = {'name': None, 'company': None, 'mfg': None, 'exp': None}
    parts = [p.strip() for p in s.split('·')]
    plain = [p for p in parts if not p.startswith(('mfg ', 'exp '))]
    if plain: out['name'] = plain[0]
    if len(plain) > 1: out['company'] = plain[1]
    for p in parts:
        if p.startswith('mfg '): out['mfg'] = p[4:]
        if p.startswith('exp '): out['exp'] = p[4:]
    return out

dist_rows, supply_rows, vend_rows, sale_rows, approvals = [], [], [], [], []
SOLD = {'genuine_sold', 'unapproved_sold', 'expired_sold'}
HAS_DIST = {'genuine_sold', 'genuine_stock', 'unapproved', 'unapproved_sold', 'expired', 'expired_sold',
            'dist_no_shop', 'mismatch', 'exp_unapproved', 'unapp_mismatch', 'noisy_vendor', 'noisy_dist'}
HAS_VEND = {'genuine_sold', 'genuine_stock', 'unapproved', 'unapproved_sold', 'expired', 'expired_sold',
            'shop_no_dist', 'mismatch', 'exp_unapproved', 'exp_no_dist', 'unapp_mismatch',
            'noisy_vendor', 'noisy_dist'}
UNAPPROVED = {'unapproved', 'unapproved_sold', 'exp_unapproved', 'unapp_mismatch'}
extra_sold = set(rnd.sample(sorted(c for c, k in case.items() if k in ('mismatch', 'shop_no_dist')), 7))

for code in sorted(items):
    k = case[code]
    med, mfg, exp = items[code]
    did = rnd.randint(1, 5)
    vid = rnd.randint(1, 10)
    if k not in UNAPPROVED:
        approvals.append(code)
    d_recv = later(mfg, 10, 45)
    supply_date = later(d_recv, 5, 30)
    v_recv = later(supply_date, 0, 2)
    if k in HAS_DIST:
        dcode, dname, dmaker, dmfg, dexp = code, med_name(code).upper(), maker(code).upper(), mfg, exp
        if k == 'noisy_dist':
            n = d_items[code]; ctx = parse_ctx(n['stored_context'])
            dcode, dname, dmaker = n['stored_value'], ctx['name'], ctx['company']
            if n['id'] == 'D06':                    # mfg / expiry swapped
                dmfg, dexp = exp, mfg
        dist_rows.append([did, dcode, d_recv, dname, dmaker, dmfg, dexp])
        if k in HAS_VEND and k != 'shop_no_dist':
            supply_rows.append([dcode, vname[vid], supply_date])
    if k in HAS_VEND:
        vdid = did
        if k in ('mismatch', 'unapp_mismatch'):
            vdid = rnd.choice([x for x in range(1, 6) if x != did])
        if k in ('shop_no_dist', 'exp_no_dist'):
            v_recv = later(mfg, 30, 75)
        vcode, vmname, vcomp, vmfg, vexp = code, med_name(code), maker(code), mmyyyy(mfg), mmyyyy(exp)
        if k == 'noisy_vendor':
            n = v_items[code]; ctx = parse_ctx(n['stored_context'])
            vcode, vmname, vcomp = n['stored_value'], ctx['name'], ctx['company']
            vexp = ctx['exp'] or vexp
        if code == 'ITEM000153':                    # V18: clean code, expiry one year off
            vexp = mmyyyy(exp.replace(year=exp.year + 1))
        vend_rows.append([vid, vdid, vcode, v_recv, vmname, vcomp, vmfg, vexp])
        if k in SOLD or code in extra_sold:
            sale_rows.append([vcode, vid, later(v_recv, 3, 60)])

# V17: duplicate vendor row of ITEM000106; D07: duplicate distributor row of ITEM000255
v106 = next(r for r in vend_rows if r[2] == 'ITEM000106')
ctx = parse_ctx(noise['V17']['stored_context'])
vend_rows.append([v106[0], v106[1], noise['V17']['stored_value'], v106[3], ctx['name'], ctx['company'], v106[6], ctx['exp']])
d255 = next(r for r in dist_rows if r[1] == 'ITEM000255')
ctx = parse_ctx(noise['D07']['stored_context'])
dist_rows.append([d255[0], noise['D07']['stored_value'], d255[2], ctx['name'], d255[4], d255[5],
                  dt.date.fromisoformat(ctx['exp'])])

# counterfeit codes held by shops (the manufacturer never made them); first two are sold
fakes = ['ITEM583920', 'ITEM771045', 'ITEM586491', 'ITEM640558', 'ITEM315790', 'ITEM827364']
for i, fc in enumerate(fakes):
    src = rnd.choice(sorted(items))
    med, mfg, exp = items[src]
    vid, did = rnd.randint(1, 10), rnd.randint(1, 5)
    recv = later(mfg, 30, 90)
    vend_rows.append([vid, did, fc, recv, med_name(src), maker(src), mmyyyy(mfg), mmyyyy(exp)])
    if i < 2:
        sale_rows.append([fc, vid, later(recv, 3, 30)])

# ---------------------------------------------------------------- SQL
def q(v):
    if v is None: return 'NULL'
    if isinstance(v, (int,)): return str(v)
    return "'" + str(v).replace("'", "''") + "'"

def inserts(table, cols, rows):
    out = [f'INSERT INTO public.{table} ({", ".join(cols)}) VALUES']
    out.append(',\n'.join('  (' + ', '.join(q(x) for x in r) + ')' for r in rows) + ';')
    return '\n'.join(out)

OUT.mkdir(parents=True, exist_ok=True)
d_sql = ['-- distributor_db: data v2 (rebuilt). Run after the Phase 1 schema + step 1 context columns.',
         'BEGIN;', 'TRUNCATE public.supplied_items, public.inventory_items, public.distributors RESTART IDENTITY CASCADE;',
         inserts('distributors', ['distributor_id', 'distributor_name', 'license_number', 'address', 'contact_number'], distributors),
         inserts('inventory_items', ['inventory_id', 'distributor_id', 'product_code', 'received_date', 'drug_name', 'mfr_name', 'mfg_date', 'exp_date'],
                 [[i + 1] + r for i, r in enumerate(dist_rows)]),
         inserts('supplied_items', ['supply_item_id', 'product_code', 'vendor_reference', 'supply_date'],
                 [[i + 1] + r for i, r in enumerate(supply_rows)]),
         "SELECT setval('public.distributors_distributor_id_seq', 5);",
         f"SELECT setval('public.inventory_items_inventory_id_seq', {len(dist_rows)});",
         f"SELECT setval('public.supplied_items_supply_item_id_seq', {len(supply_rows)});",
         'COMMIT;',
         'SELECT (SELECT count(*) FROM public.distributors) AS distributors, (SELECT count(*) FROM public.inventory_items) AS stock, (SELECT count(*) FROM public.supplied_items) AS supplied;']
(OUT / 'distributor_data.sql').write_text('\n'.join(d_sql) + '\n')

v_sql = ['-- vendor_db: data v2 (rebuilt). Run after the Phase 1 schema + step 1 context columns.',
         'BEGIN;', 'TRUNCATE public.medicine_sales, public.vendor_inventory, public.vendors RESTART IDENTITY CASCADE;',
         inserts('vendors', ['vendor_id', 'vendor_name', 'license_number', 'address', 'contact_number'], vendors),
         inserts('vendor_inventory', ['inventory_id', 'vendor_id', 'distributor_id', 'item_identifier', 'received_date', 'medicine_name', 'company', 'mfg', 'expiry'],
                 [[i + 1] + r for i, r in enumerate(vend_rows)]),
         inserts('medicine_sales', ['sale_id', 'item_identifier', 'vendor_id', 'sale_date', 'customer_reference'],
                 [[i + 1, r[0], r[1], r[2], f'CUST{i + 1:03d}'] for i, r in enumerate(sale_rows)]),
         "SELECT setval('public.vendors_vendor_id_seq', 10);",
         f"SELECT setval('public.vendor_inventory_inventory_id_seq', {len(vend_rows)});",
         f"SELECT setval('public.medicine_sales_sale_id_seq', {len(sale_rows)});",
         'COMMIT;',
         'SELECT (SELECT count(*) FROM public.vendors) AS vendors, (SELECT count(*) FROM public.vendor_inventory) AS stock, (SELECT count(*) FROM public.medicine_sales) AS sales;']
(OUT / 'vendor_data.sql').write_text('\n'.join(v_sql) + '\n')

m_sql = ['-- mediator_db: approvals for data v2 (rebuilt)', 'BEGIN;',
         'TRUNCATE public.approved_items RESTART IDENTITY;', 'TRUNCATE public.reports RESTART IDENTITY;',
         inserts('approved_items', ['item_code', 'approved_at', 'approved_by'],
                 [[c, '2026-06-01 10:00:00', 'CDSCO Drug Controller'] for c in approvals]),
         'COMMIT;', 'SELECT count(*) AS approvals FROM public.approved_items;']
(OUT / 'mediator_data.sql').write_text('\n'.join(m_sql) + '\n')

print('distributor stock', len(dist_rows), 'supplied', len(supply_rows))
print('vendor stock', len(vend_rows), 'sales', len(sale_rows), 'approvals', len(approvals))
print({c: sum(1 for v in case.values() if v == c) for c in sorted(set(case.values()))})
