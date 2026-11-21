import json

import streamlit as st
import psycopg2
import pandas as pd

st.set_page_config(
    page_title="Asli / Nakali Medicine",
    page_icon="💊",
    layout="wide"
)

DB_CONFIG = {
    "host": "localhost",
    "port": "5432",
    "dbname": "mediator_db",
    "user": "postgres",
    "password": "akshat2506"
}


# =========================================================
# DATABASE
# =========================================================

def get_connection():
    return psycopg2.connect(**DB_CONFIG)


def run_query(query, params=None):
    """Run a SELECT on the mediator and return a DataFrame."""
    conn = get_connection()
    try:
        return pd.read_sql(query, conn, params=params)
    finally:
        conn.close()


# =========================================================
# PHASE 1 · LIVE VERIFICATION (exact item code)
# =========================================================

def verify_medicine(item_code):
    conn = get_connection()

    # verify_item = the same rules as global_medicine_history, but a distributor /
    # vendor record stored under a NOISY code of this item also counts (step 3)
    query = """
        SELECT *
        FROM verify_item(%s)
    """

    df = pd.read_sql(query, conn, params=(item_code,))
    conn.close()

    return df


# =========================================================
# PHASE 1 · AUTOMATIC REPORT
# =========================================================

def file_report(row):
    conn = get_connection()
    cur = conn.cursor()

    query = """
        INSERT INTO reports
        (
            item_identifier,
            manufacturer,
            distributor,
            vendor,
            report_reason,
            risk_status,
            evidence
        )
        VALUES (%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (item_identifier) DO NOTHING
        RETURNING report_id
    """

    evidence = (
        f"Item Code: {row['item_code']}\n"
        f"Medicine: {row['medicine_name']}\n"
        f"Manufacturer: {row['manufacturer_name']}\n"
        f"Expiry: {row['expiry_date']}\n"
        f"Approval: {row['approval_status']}\n"
        f"Distributor ID: {row['distributor_id']}\n"
        f"Vendor Distributor ID: {row['vendor_distributor_id']}"
    )

    cur.execute(
        query,
        (
            row["item_code"],
            row["manufacturer_name"],
            row["distributor_name"],
            row["vendor_name"],
            row["suspicion_reason"],
            "SUSPICIOUS",
            evidence
        )
    )

    inserted = cur.fetchone()

    conn.commit()
    cur.close()
    conn.close()

    return inserted is not None


# =========================================================
# PHASE 2 · REPORT FROM PACK EVIDENCE
# (cloned code, pack details differ, no match)
# =========================================================

def file_pack_report(item_identifier, manufacturer, reason, evidence):
    """Same reports table and rules as Phase 1; returns True if a new report was filed."""
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO reports
                (item_identifier, manufacturer, distributor, vendor,
                 report_reason, risk_status, evidence)
            VALUES (%s, %s, NULL, NULL, %s, 'SUSPICIOUS', %s)
            ON CONFLICT (item_identifier) DO NOTHING
            RETURNING report_id
            """,
            (item_identifier, manufacturer, reason, evidence)
        )
        inserted = cur.fetchone()
        conn.commit()
        cur.close()
        return inserted is not None
    finally:
        conn.close()


# =========================================================
# PHASE 2 · MATCHING FUNCTIONS (SQL lives in the mediator)
# =========================================================

def search_by_pack(code, name, company, mfg, expiry, limit=10):
    return run_query(
        "SELECT * FROM search_by_pack(%s, %s, %s, %s, %s, %s)",
        (code, name or None, company or None, mfg or None, expiry or None, limit)
    )


def normalize_code(code):
    df = run_query("SELECT normalize_code(%s) AS c", (code,))
    return df.iloc[0]["c"]


def code_edit_steps(noisy, candidate):
    return run_query(
        "SELECT * FROM code_edit_steps(%s, %s)", (noisy, candidate)
    )


def golden_item(item_code):
    return run_query(
        "SELECT * FROM v_golden_items WHERE item_code = %s", (item_code,)
    )


def find_records_for_item(item_code):
    return run_query(
        "SELECT * FROM find_records_for_item(%s)", (item_code,)
    )


def record_flags():
    return run_query(
        """
        SELECT source, record_id, stored_code, status, issues,
               distributor_id, vendor_name, name, company, mfg, expiry
        FROM v_stored_record_flags
        ORDER BY source, record_id
        """
    )


def match_stored_record(source, record_id, limit=10):
    return run_query(
        "SELECT * FROM match_stored_record(%s, %s, %s)",
        (source, int(record_id), limit)
    )


def record_trust(item_code, code=None, name=None, company=None, mfg=None, expiry=None):
    """Genuine record identification: every record of the item with its six trust factors."""
    return run_query(
        "SELECT * FROM record_trust(%s, %s, %s, %s, %s, %s)",
        (item_code, code or None, name or None, company or None, mfg or None, expiry or None)
    )


def source_registry():
    """Registered sources and what the mediator has learned about their reliability."""
    sources = run_query(
        "SELECT source_id, kind, enabled, description FROM asli_sources ORDER BY kind, source_id"
    )
    reliability = run_query("""
        SELECT k.kind, a.attribute, asli_reliability(k.kind, a.attribute) AS reliability,
               r.confirmed, r.checked
        FROM (VALUES ('MANUFACTURER'), ('DISTRIBUTOR'), ('VENDOR')) k(kind)
        CROSS JOIN (VALUES ('ALL'), ('code'), ('name'), ('company'), ('mfg'), ('expiry')) a(attribute)
        LEFT JOIN source_attribute_reliability r ON r.kind = k.kind AND r.attribute = a.attribute
        ORDER BY 1, 2
    """)
    return sources, reliability


TRUST_ICON = {
    "MOST RELIABLE": "🛡️", "ALL RECORDS AGREE": "✅", "AGREES WITH THE TOP RECORD": "✅",
    "LESS RELIABLE": "⚠️", "REVIEW": "❓",
}


def show_trust(trust):
    """Six-factor confidence per record, most trustworthy first."""
    if trust.empty:
        st.info("No records of this item to compare.")
        return
    t = trust.copy()
    t.insert(0, "", t["decision"].map(TRUST_ICON).fillna(""))
    st.dataframe(
        t[["", "rank", "source", "stored_code", "decision", "confidence", "entity", "context",
           "completeness", "attribute_rel", "source_rel", "consistency", "name", "mfg", "expiry"]],
        use_container_width=True, hide_index=True
    )
    w = t.iloc[0]["weights"]
    if isinstance(w, str):
        w = json.loads(w)
    st.caption(
        "Factor weights used here (they change with what is available): "
        + " · ".join(f"{k} {v}" for k, v in w.items())
        + ". entity = code similarity · context = fit with the pack · completeness = fields filled · "
          "attribute / source = reliability learned from earlier fixes · consistency = agreement with the other records."
    )


def show_weights(candidates):
    """The dynamic attribute weights used for this search, against the base weights."""
    w = candidates.iloc[0].get("weights")
    if w is None or (isinstance(w, float) and pd.isna(w)):
        return
    if isinstance(w, str):
        w = json.loads(w)
    base = {r["key"]: float(r["value"]) for _, r in match_settings()[0].iterrows()}
    rows = []
    for attr, key in [("code", "w_code"), ("name", "w_name"), ("expiry", "w_expiry"),
                      ("company", "w_company"), ("mfg", "w_mfg")]:
        rows.append({"Attribute": attr, "Base weight": base.get(key), "Weight used now": w.get(attr)})
    st.dataframe(pd.DataFrame(rows), use_container_width=True, hide_index=True)
    st.caption(
        f"The sources sent {w.get('candidates')} candidate item(s). An attribute that every candidate shares "
        "cannot tell them apart, so its weight shrinks; a field you left blank is left out and the others "
        "share its weight."
    )


def match_settings():
    config = run_query(
        "SELECT key, value, description FROM match_config ORDER BY key"
    )
    costs = run_query(
        """
        SELECT reason, cost, string_agg(char_a || '↔' || char_b, '  ' ORDER BY char_a, char_b) AS pairs
        FROM code_char_costs
        WHERE char_a < char_b
        GROUP BY reason, cost
        ORDER BY cost
        """
    )
    return config, costs


# =========================================================
# PHASE 2 · DATA CLEANSING (scan, review, fix scripts, log)
# =========================================================

DATABASES = ["manuf_db", "distributor_db", "vendor_db", "mediator_db"]


def run_write(query, params=None):
    """Run a statement that changes mediator data and return its rows."""
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute(query, params)
        rows = cur.fetchall() if cur.description else []
        conn.commit()
        cur.close()
        return rows
    finally:
        conn.close()


def cleansing_scan():
    return run_write("SELECT cleansing_scan()")[0][0]


def cleansing_resolve(proposal_id, option):
    return run_write("SELECT cleansing_resolve(%s, %s)", (int(proposal_id), option))[0][0]


def cleansing_check():
    applied, pending = run_write("SELECT applied, pending FROM cleansing_check()")[0]
    return int(applied), int(pending)


def latest_scan():
    return run_query(
        "SELECT scan_id, started_at, finished_at FROM cleansing_scans ORDER BY scan_id DESC LIMIT 1"
    )


def cleansing_proposals():
    return run_query(
        """
        SELECT proposal_id, item_code, source, target_db, target_table, key_column, key_value,
               field, column_name, old_value, new_value, action, reason, options, suggested, status
        FROM v_cleansing_latest
        ORDER BY target_db, (action = 'DELETE') DESC, (field = 'code') DESC, target_table, key_value, field
        """
    )


def cleansing_fix_sql(database):
    return run_query("SELECT cleansing_fix_sql(%s) AS script", (database,)).iloc[0]["script"]


def cleansing_log():
    return run_query(
        """
        SELECT log_id, detected_at, target_db, target_table, key_column, key_value,
               column_name, old_value, new_value, action, reason
        FROM cleansing_log
        ORDER BY log_id DESC
        """
    )


def review_options(proposal):
    """REVIEW options as a list of labels: suggested first, then by score, delete last."""
    options = proposal["options"]
    if options is None or (isinstance(options, float) and pd.isna(options)):
        return []
    if isinstance(options, str):
        options = json.loads(options)

    def order(label):
        if label == proposal["suggested"]:
            return (0, 0)
        if label.startswith("Delete"):
            return (2, 0)
        score = label.rsplit("score ", 1)[-1].rstrip(")") if "score " in label else "0"
        try:
            return (1, -float(score))
        except ValueError:
            return (1, 0)

    return sorted(options.keys(), key=order)


# =========================================================
# PHASE 1 · REPORTS
# =========================================================

def get_reports():
    conn = get_connection()

    query = """
        SELECT
            report_id,
            item_identifier,
            manufacturer,
            distributor,
            vendor,
            report_reason,
            risk_status,
            evidence,
            reported_at,
            status
        FROM reports
        ORDER BY reported_at DESC
    """

    df = pd.read_sql(query, conn)
    conn.close()

    return df


# =========================================================
# PHASE 1 · MATERIALIZED VIEW REFRESH
# =========================================================

def refresh_analysis():
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        "REFRESH MATERIALIZED VIEW mv_medicine_analysis"
    )

    conn.commit()
    cur.close()
    conn.close()


# =========================================================
# PHASE 1 · ANALYSIS QUERIES
# =========================================================

def get_analysis_status():
    conn = get_connection()

    query = """
        SELECT
            analysis_status,
            COUNT(*) AS total_items
        FROM mv_medicine_analysis
        GROUP BY analysis_status
        ORDER BY total_items DESC
    """

    df = pd.read_sql(query, conn)
    conn.close()

    return df


def get_distributor_analysis():
    conn = get_connection()

    query = """
        SELECT
            COALESCE(
                distributor_name,
                'DISTRIBUTOR NOT FOUND'
            ) AS distributor,

            COUNT(*) AS total_items,

            COUNT(*) FILTER (
                WHERE analysis_status = 'GENUINE'
            ) AS genuine_items,

            COUNT(*) FILTER (
                WHERE analysis_status = 'SUSPICIOUS'
            ) AS suspicious_items,

            COUNT(*) FILTER (
                WHERE analysis_status = 'NAKALI'
            ) AS nakali_items

        FROM mv_medicine_analysis

        GROUP BY distributor_name

        ORDER BY
            suspicious_items DESC,
            nakali_items DESC
    """

    df = pd.read_sql(query, conn)
    conn.close()

    return df


def get_vendor_analysis():
    conn = get_connection()

    query = """
        SELECT
            COALESCE(
                vendor_name,
                'VENDOR NOT FOUND'
            ) AS vendor,

            COUNT(*) AS total_items,

            COUNT(*) FILTER (
                WHERE analysis_status = 'GENUINE'
            ) AS genuine_items,

            COUNT(*) FILTER (
                WHERE analysis_status = 'SUSPICIOUS'
            ) AS suspicious_items,

            COUNT(*) FILTER (
                WHERE analysis_status = 'NAKALI'
            ) AS nakali_items

        FROM mv_medicine_analysis

        GROUP BY vendor_name

        ORDER BY
            suspicious_items DESC,
            nakali_items DESC
    """

    df = pd.read_sql(query, conn)
    conn.close()

    return df


def get_suspicion_analysis():
    conn = get_connection()

    query = """
        SELECT
            reason,
            COUNT(*) AS total_items
        FROM (
            SELECT
                TRIM(
                    unnest(
                        string_to_array(
                            suspicion_reason,
                            ' | '
                        )
                    )
                ) AS reason
            FROM mv_medicine_analysis
            WHERE suspicion_reason IS NOT NULL
        ) x

        GROUP BY reason

        ORDER BY total_items DESC
    """

    df = pd.read_sql(query, conn)
    conn.close()

    return df


def get_mismatch_analysis():
    conn = get_connection()

    query = """
        SELECT
            distributor_name,
            vendor_name,
            distributor_id,
            vendor_distributor_id,
            COUNT(*) AS mismatch_count

        FROM mv_medicine_analysis

        WHERE distributor_id IS NOT NULL
          AND vendor_distributor_id IS NOT NULL
          AND distributor_id <> vendor_distributor_id

        GROUP BY
            distributor_name,
            vendor_name,
            distributor_id,
            vendor_distributor_id

        ORDER BY mismatch_count DESC
    """

    df = pd.read_sql(query, conn)
    conn.close()

    return df


# =========================================================
# DISPLAY HELPERS
# =========================================================

# Short explanation shown under each matching verdict
VERDICT_TEXT = {
    "EXACT MATCH": "The code exists exactly and the pack details agree with the manufacturer's record.",
    "MATCH": "The code was noisy, but one item clearly fits both the code and the pack details.",
    "WRONG CODE": "The code you entered is a real code, but it belongs to a different medicine. "
                  "Another item fits the pack — the code was probably mistyped.",
    "CONTEXT ERROR": "The code exists, but the pack's details (e.g. expiry or manufacturer) differ from "
                     "the manufacturer's record. The pack may have been tampered with.",
    "POSSIBLE CLONED CODE": "This is a real code, but the pack contradicts the manufacturer's record and no "
                            "other item fits. A genuine code has probably been copied onto a fake pack.",
    "REVIEW": "More than one item fits equally well. Please choose which one to verify.",
    "NO MATCH": "No item resembles this code.",
    "NOISY MANUFACTURER RECORD": "The distributor and the vendor both record this exact code, but the "
                                 "manufacturer does not: the manufacturer's own record of this item is "
                                 "the noisy one. It is shown below; the Data cleansing tab fixes it.",
}

RELATION_ICON = {
    "EXACT CODE": "✅",
    "EXACT CODE, CONTEXT ERROR": "⚠️",
    "NOISY VARIANT": "🟠",
    "POSSIBLE": "❓",
    "BELONGS ELSEWHERE": "⛔",
}

CANDIDATE_COLUMNS = {
    "rank": "Rank",
    "item_code": "Item code",
    "medicine_name": "Medicine",
    "manufacturer": "Manufacturer",
    "expiry_date": "Expiry",
    "code_edit_cost": "Code edit cost",
    "code_score": "Code",
    "name_score": "Name",
    "company_score": "Company",
    "expiry_score": "Expiry ✓",
    "mfg_score": "Mfg ✓",
    "distributor_score": "Distributor ✓",
    "supply_score": "Supplied to shop ✓",
    "dates_swapped": "Dates swapped",
    "context_score": "Context",
    "total_score": "TOTAL",
}


def show_candidates(df):
    """Ranked candidate table; columns that are empty for every row are hidden."""
    table = df[[c for c in CANDIDATE_COLUMNS if c in df.columns]].copy()
    table = table.dropna(axis=1, how="all")
    table = table.rename(columns=CANDIDATE_COLUMNS)
    st.dataframe(table, use_container_width=True, hide_index=True)


def show_edit_steps(noisy, candidate):
    """How the noisy code turns into the candidate code."""
    try:
        steps = code_edit_steps(noisy, candidate)
        if steps.empty:
            st.write(f"`{noisy}` and `{candidate}` are identical after clean-up — no edits needed.")
        else:
            total = sum(float(c) for c in steps["cost"])
            st.write(f"`{noisy}` → `{candidate}`: {len(steps)} edit(s), total cost **{total:g}**")
            st.dataframe(
                steps.rename(columns={
                    "step": "Step", "operation": "Edit", "at_position": "Position",
                    "noisy_char": "Typed", "candidate_char": "Should be",
                    "cost": "Cost", "reason": "Why it is cheap / expensive"
                }),
                use_container_width=True, hide_index=True
            )
    except Exception as e:
        st.error(f"❌ Could not explain code edits: {e}")


# =========================================================
# PHASE 1 · VERIFICATION RESULT DISPLAY (moved into a function
# so Phase 2 can call it for whichever candidate is chosen)
# =========================================================

def show_verification(item_code, auto_report=True):

    result = verify_medicine(item_code)

    if result.empty:

        st.error(
            "❌ ITEM NOT FOUND"
        )

        st.info(
            "This item code does not exist in the "
            "Manufacturer database."
        )

        return

    row = result.iloc[0]

    st.subheader("📋 Verification Result")

    noisy_held = [
        f"the **{who}** holds it as `{code}`"
        for who, code in (("distributor", row["distributor_item_code"]),
                          ("vendor", row["vendor_item_code"]))
        if pd.notna(code) and code != row["item_code"]
    ]
    if noisy_held:
        st.info(
            f"🔁 Matched records with noisy codes: {' and '.join(noisy_held)}. "
            f"They were matched to **{row['item_code']}** and are used in this verification. "
            "The Data cleansing tab corrects the stored codes."
        )


    # =================================================
    # STATUS
    # =================================================

    if row["risk_status"] == "GENUINE":

        st.success(
            f"✅ GENUINE MEDICINE — {row['item_code']}"
        )

        st.markdown(
            """
            <div style="
                padding:15px;
                border-radius:10px;
                border:1px solid #8bc48b;
                margin:10px 0 20px 0;
            ">
                <b>✓ Verification Passed</b><br>
                The medicine passed all authenticity checks.
                No Ministry report is required.
            </div>
            """,
            unsafe_allow_html=True
        )

    else:

        if "UNAPPROVED / NAKALI" in str(
            row["suspicion_reason"]
        ):

            st.error(
                f"🚨 NAKALI / UNAPPROVED — "
                f"{row['item_code']}"
            )

        else:

            st.warning(
                f"⚠️ SUSPICIOUS MEDICINE — "
                f"{row['item_code']}"
            )


    # =================================================
    # MEDICINE INFORMATION
    # =================================================

    st.markdown("### 💊 Medicine Information")

    c1, c2, c3 = st.columns(3)

    with c1:
        st.write(
            "**Item Code:**",
            row["item_code"]
        )

        st.write(
            "**Medicine Code:**",
            row["medicine_code"]
        )

        st.write(
            "**Medicine Name:**",
            row["medicine_name"]
        )

    with c2:
        st.write(
            "**Composition:**",
            row["composition"]
        )

        st.write(
            "**Dosage Form:**",
            row["dosage_form"]
        )

        st.write(
            "**Approval:**",
            row["approval_status"]
        )

    with c3:
        st.write(
            "**Manufacturing Date:**",
            row["manufacturing_date"]
        )

        st.write(
            "**Expiry Date:**",
            row["expiry_date"]
        )

        st.write(
            "**Expiry Status:**",
            row["expiry_status"]
        )


    # =================================================
    # MANUFACTURER
    # =================================================

    st.markdown("### 🏭 Manufacturer")

    c1, c2 = st.columns(2)

    with c1:
        st.write(
            "**Manufacturer:**",
            row["manufacturer_name"]
        )

    with c2:
        st.write(
            "**Manufacturer ID:**",
            row["manufacturer_id"]
        )


    # =================================================
    # DISTRIBUTOR
    # =================================================

    st.markdown("### 🚚 Distributor")

    c1, c2, c3 = st.columns(3)

    with c1:
        distributor = row["distributor_name"]

        st.write(
            "**Distributor:**",
            distributor
            if pd.notna(distributor)
            else "Not Found"
        )

    with c2:
        distributor_id = row["distributor_id"]

        st.write(
            "**Distributor ID:**",
            distributor_id
            if pd.notna(distributor_id)
            else "Not Found"
        )

    with c3:
        received_date = row[
            "distributor_received_date"
        ]

        st.write(
            "**Received Date:**",
            received_date
            if pd.notna(received_date)
            else "Not Found"
        )


    # =================================================
    # VENDOR
    # =================================================

    st.markdown("### 🏪 Vendor")

    c1, c2, c3 = st.columns(3)

    with c1:
        vendor = row["vendor_name"]

        st.write(
            "**Vendor:**",
            vendor
            if pd.notna(vendor)
            else "Not Found"
        )

    with c2:
        vendor_distributor_id = row[
            "vendor_distributor_id"
        ]

        st.write(
            "**Vendor Distributor ID:**",
            vendor_distributor_id
            if pd.notna(vendor_distributor_id)
            else "Not Found"
        )

    with c3:
        supply_date = row["supply_date"]

        st.write(
            "**Supply Date:**",
            supply_date
            if pd.notna(supply_date)
            else "Not Supplied"
        )


    # =================================================
    # DISTRIBUTOR / VENDOR MISMATCH
    # =================================================

    if (
        pd.notna(row["distributor_id"])
        and
        pd.notna(row["vendor_distributor_id"])
        and
        row["distributor_id"]
        != row["vendor_distributor_id"]
    ):

        st.error(
            f"🚨 DISTRIBUTOR ID MISMATCH — "
            f"Distributor says ID "
            f"{row['distributor_id']} "
            f"but Vendor says ID "
            f"{row['vendor_distributor_id']}"
        )


    # =================================================
    # SUSPICION DETAILS + AUTO REPORT
    # =================================================

    if row["risk_status"] != "GENUINE":

        st.markdown("### 🚨 Suspicion Details")

        reasons = str(
            row["suspicion_reason"]
        ).split(" | ")

        for reason in reasons:

            if reason.strip():

                st.error(
                    f"⚠️ {reason}"
                )


        # ---------------------------------------------
        # AUTOMATIC REPORT
        # ---------------------------------------------

        if not auto_report:

            st.info(
                "📢 Not reported: the suspicion comes from a noisy "
                "manufacturer record, not from the medicine. "
                "Run Data cleansing first."
            )

            return

        try:

            reported_now = file_report(row)

            if reported_now:

                st.success(
                    "📢 Automatically reported to "
                    "Ministry of Consumer Affairs."
                )

            else:

                st.info(
                    "📢 This medicine was already "
                    "reported to the Ministry."
                )

        except Exception as e:

            st.error(
                f"❌ Automatic reporting failed: {e}"
            )


    else:

        st.success(
            "✓ Medicine is genuine. "
            "No Ministry report required."
        )


    # =================================================
    # COMPLETE HISTORY
    # =================================================

    st.divider()

    st.markdown(
        "### 🔗 Complete Medicine History"
    )

    history = pd.DataFrame({
        "Stage": [
            "Manufacturer",
            "Distributor",
            "Vendor",
            "Sale"
        ],

        "Status": [
            "✓ Found",

            "✓ Found"
            if pd.notna(
                row["distributor_item_code"]
            )
            else "❌ Not Found",

            "✓ Found"
            if pd.notna(
                row["vendor_item_code"]
            )
            else "❌ Not Found",

            "✓ Sold"
            if pd.notna(row["sale_id"])
            else "Not Sold"
        ]
    })

    st.dataframe(
        history,
        use_container_width=True,
        hide_index=True
    )


def pack_evidence(pack, record):
    """Text comparing what the pack says with the manufacturer's record."""
    lines = [f"Code on pack: {pack['code']}"]
    for label, key, rec_key in [
        ("Medicine", "name", "medicine_name"),
        ("Manufacturer", "company", "manufacturer"),
        ("Mfg date", "mfg", "mfg_date"),
        ("Expiry", "expiry", "expiry_date"),
    ]:
        if pack.get(key):
            lines.append(f"{label}: pack says '{pack[key]}', record says '{record[rec_key]}'")
    return "\n".join(lines)


# =========================================================
# HEADER
# =========================================================

st.markdown(
    """
    <div style="
        text-align:center;
        padding:10px 0 20px 0;
    ">
        <h1>💊 Asli / Nakali Medicine</h1>
        <h3>Verification System</h3>
        <p>
            Verify medicine authenticity and complete supply history
            using the item code printed on the pack — even when it is
            mistyped or badly printed.
        </p>
    </div>
    """,
    unsafe_allow_html=True
)

(
    tab_verify,
    tab_item,
    tab_health,
    tab_cleanse,
    tab_reports,
    tab_analysis,
    tab_settings
) = st.tabs([
    "🔍 Verify medicine",
    "🔁 Find records for an item",
    "🩺 Data health",
    "🧹 Data cleansing",
    "📢 Reports",
    "📊 Analysis",
    "⚙️ Matching settings",
])


# =========================================================
# TAB 1 · VERIFY MEDICINE (noisy code + pack details)
# =========================================================

with tab_verify:

    st.subheader("🔍 Medicine Verification")
    st.caption(
        "Only the item code is required. Every extra detail from the pack "
        "helps the system tell apart items whose codes look alike."
    )

    with st.form("pack_form"):
        item_code = st.text_input(
            "Item code (as printed)",
            placeholder="e.g. ITEM000001"
        )
        c1, c2 = st.columns(2)
        with c1:
            pack_name = st.text_input("Medicine name", placeholder="e.g. Ibuprofen 400mg")
            pack_mfg = st.text_input("Mfg date", placeholder="e.g. 03/2026")
        with c2:
            pack_company = st.text_input("Manufacturer", placeholder="e.g. Sunrise Pharmaceuticals")
            pack_expiry = st.text_input("Expiry date", placeholder="e.g. MAR-2028")
        verify_button = st.form_submit_button("🔍 VERIFY", type="primary")

    # Remember the search so it survives reruns (e.g. when a candidate is picked)
    if verify_button:
        if not item_code.strip():
            st.warning("⚠️ Please enter a medicine item code.")
            st.session_state.pop("pack", None)
        else:
            st.session_state["pack"] = {
                "code": item_code.strip(),
                "name": pack_name.strip(),
                "company": pack_company.strip(),
                "mfg": pack_mfg.strip(),
                "expiry": pack_expiry.strip(),
            }
            st.session_state["search_id"] = st.session_state.get("search_id", 0) + 1

    pack = st.session_state.get("pack")

    if pack:
        try:
            candidates = search_by_pack(
                pack["code"], pack["name"], pack["company"], pack["mfg"], pack["expiry"]
            )
            cleaned = normalize_code(pack["code"])

            st.divider()

            if cleaned != pack["code"]:
                st.caption(f"Code after clean-up: `{cleaned}` (typed: `{pack['code']}`)")

            # ---------------------------------------------
            # NO MATCH: nothing resembles the code
            # ---------------------------------------------
            if candidates.empty:
                st.error("❌ NO MATCH — no medicine in the manufacturer's records resembles this code.")
                st.info(VERDICT_TEXT["NO MATCH"] + " This pack is very likely fake.")
                if st.button("📢 Report as suspected fake"):
                    try:
                        if file_pack_report(
                            cleaned or pack["code"], None, "CODE NOT FOUND",
                            "Code on pack matches no manufacturer item.\n"
                            + "\n".join(f"{k}: {v}" for k, v in pack.items() if v)
                        ):
                            st.success("📢 Reported to Ministry of Consumer Affairs.")
                        else:
                            st.info("📢 This code was already reported.")
                    except Exception as e:
                        st.error(f"❌ Reporting failed: {e}")

            else:
                verdict = candidates.iloc[0]["verdict"]
                decided = candidates.iloc[0]["decided_item"]
                decided = decided if pd.notna(decided) else None

                # ---------------------------------------------
                # VERDICT BANNER
                # ---------------------------------------------
                st.subheader(f"🧩 Matching result: {verdict}")
                if verdict == "EXACT MATCH":
                    st.success(f"✅ {VERDICT_TEXT[verdict]}")
                elif verdict == "MATCH":
                    st.success(f"✅ Noisy code `{pack['code']}` resolved to **{decided}**. {VERDICT_TEXT[verdict]}")
                elif verdict == "WRONG CODE":
                    st.warning(f"⚠️ {VERDICT_TEXT[verdict]} Did you mean **{decided}**?")
                elif verdict == "REVIEW":
                    st.warning(f"❓ {VERDICT_TEXT[verdict]}")
                elif verdict == "NOISY MANUFACTURER RECORD":
                    st.warning(
                        f"⚠️ The distributor and vendor both record `{cleaned}`, but the manufacturer's "
                        f"record of this item reads **{decided}**. {VERDICT_TEXT[verdict]}"
                    )
                else:   # CONTEXT ERROR, POSSIBLE CLONED CODE
                    st.error(f"🚨 {verdict} — {VERDICT_TEXT.get(verdict, '')}")

                # ---------------------------------------------
                # RANKED CANDIDATES
                # ---------------------------------------------
                st.markdown("### 📊 Candidate items")
                show_candidates(candidates)
                with st.expander("⚖️ How the attributes were weighted for this search"):
                    show_weights(candidates)

                # ---------------------------------------------
                # CLONED CODE / PACK DIFFERS: compare and report
                # ---------------------------------------------
                if verdict in ("POSSIBLE CLONED CODE", "CONTEXT ERROR"):
                    exact = candidates[candidates["code_edit_cost"].astype(float) == 0]
                    if not exact.empty:
                        record = exact.iloc[0]
                        st.markdown("### 🔎 Pack vs manufacturer's record")
                        comparison = pd.DataFrame({
                            "Field": ["Item code", "Medicine", "Manufacturer", "Mfg date", "Expiry"],
                            "On the pack": [pack["code"], pack["name"] or "—", pack["company"] or "—",
                                            pack["mfg"] or "—", pack["expiry"] or "—"],
                            "Manufacturer's record": [record["item_code"], record["medicine_name"],
                                                      record["manufacturer"], str(record["mfg_date"]),
                                                      str(record["expiry_date"])],
                        })
                        st.dataframe(comparison, use_container_width=True, hide_index=True)
                        try:
                            reason = ("POSSIBLE CLONED CODE" if verdict == "POSSIBLE CLONED CODE"
                                      else "PACK DETAILS DIFFER FROM RECORD")
                            if file_pack_report(record["item_code"], record["manufacturer"],
                                                reason, pack_evidence(pack, record)):
                                st.success("📢 Automatically reported to Ministry of Consumer Affairs.")
                            else:
                                st.info("📢 This code was already reported to the Ministry.")
                        except Exception as e:
                            st.error(f"❌ Automatic reporting failed: {e}")

                # ---------------------------------------------
                # CHOOSE WHICH ITEM TO VERIFY (default: decided item)
                # ---------------------------------------------
                options = list(candidates["item_code"])
                exact_codes = list(candidates.loc[candidates["code_edit_cost"].astype(float) == 0, "item_code"])
                if decided in options:
                    default = decided
                elif verdict in ("POSSIBLE CLONED CODE", "CONTEXT ERROR") and exact_codes:
                    default = exact_codes[0]      # the genuine item that carries this code
                else:
                    default = None                # REVIEW: the buyer must choose
                labels = {
                    r["item_code"]: f"{r['item_code']} · {r['medicine_name']} · score {r['total_score']}"
                    for _, r in candidates.iterrows()
                }
                labels[None] = "— choose an item —"
                if default is None:
                    options = [None] + options
                chosen = st.selectbox(
                    "Verify which item?",
                    options,
                    index=options.index(default),
                    format_func=lambda c: labels[c],
                    key=f"chosen_{st.session_state.get('search_id', 0)}",
                )

                if chosen is None:
                    st.info("Choose the item that matches your pack to see its verification.")
                else:
                    with st.expander("🔤 How the typed code matches this item"):
                        show_edit_steps(pack["code"], chosen)

                    with st.expander("🛡️ Which stored record of this item is most trustworthy"):
                        show_trust(record_trust(chosen, pack["code"], pack["name"], pack["company"],
                                                pack["mfg"], pack["expiry"]))

                    if verdict == "POSSIBLE CLONED CODE" and chosen == default:
                        st.info(
                            "The supply-chain record below belongs to the genuine item with this code — "
                            "not to the pack in your hand."
                        )

                    st.divider()
                    show_verification(
                        chosen,
                        auto_report=not (verdict == "NOISY MANUFACTURER RECORD" and chosen == decided)
                    )

        except Exception as e:
            st.error(f"❌ Verification failed: {e}")


# =========================================================
# TAB 2 · VICE VERSA: REAL ITEM -> RECORDS IN OTHER DATABASES
# =========================================================

with tab_item:

    st.subheader("🔁 Find every record of an item")
    st.caption(
        "Enter a genuine item code from the manufacturer. The system finds every "
        "distributor and vendor record that carries it — or a noisy version of it."
    )

    col1, col2 = st.columns([5, 1])
    with col1:
        lookup_code = st.text_input(
            "Item code", placeholder="e.g. ITEM000106",
            label_visibility="collapsed", key="lookup_code"
        )
    with col2:
        lookup_button = st.button("🔁 FIND", type="primary", use_container_width=True)

    if lookup_button and lookup_code.strip():
        st.session_state["lookup"] = lookup_code.strip().upper()

    lookup = st.session_state.get("lookup")

    if lookup:
        try:
            item = golden_item(lookup)

            if item.empty:
                st.error(f"❌ {lookup} is not an item code in the manufacturer's records.")
                closest = search_by_pack(lookup, None, None, None, None, 5)
                if not closest.empty:
                    st.info("Closest real item codes:")
                    show_candidates(closest)
            else:
                g = item.iloc[0]
                st.markdown(
                    f"**{g['item_code']}** · {g['medicine_name']} ({g['composition']}) · "
                    f"{g['manufacturer_name']} · mfg {g['manufacturing_date']} · exp {g['expiry_date']}"
                )

                records = find_records_for_item(lookup)

                if records.empty:
                    st.info("No distributor or vendor record carries this item, even approximately.")
                else:
                    c1, c2, c3 = st.columns(3)
                    c1.metric("Exact records", int((records["relation"] == "EXACT CODE").sum()))
                    c2.metric("Noisy records",
                              int(records["relation"].isin(["NOISY VARIANT", "EXACT CODE, CONTEXT ERROR"]).sum()))
                    c3.metric("Possible / elsewhere",
                              int(records["relation"].isin(["POSSIBLE", "BELONGS ELSEWHERE"]).sum()))

                    records.insert(0, "", records["relation"].map(RELATION_ICON).fillna(""))
                    st.dataframe(
                        records[["", "source", "stored_code", "relation", "verdict", "decided_item",
                                 "item_score", "code_edit_cost", "name", "company", "expiry",
                                 "distributor_id", "vendor_name", "record_id"]],
                        use_container_width=True, hide_index=True
                    )
                    st.caption(
                        "✅ exact code · ⚠️ exact code but wrong details · 🟠 noisy copy of this item · "
                        "❓ ambiguous, could be this item · ⛔ carries this code but belongs to another item"
                    )

                    st.markdown("### 🛡️ Which record is most trustworthy")
                    show_trust(record_trust(lookup))

                    noisy = records[records["stored_code"] != lookup]
                    for _, r in noisy.iterrows():
                        with st.expander(f"🔤 {r['source']} record `{r['stored_code']}` vs {lookup}"):
                            show_edit_steps(r["stored_code"], lookup)

        except Exception as e:
            st.error(f"❌ Search failed: {e}")


# =========================================================
# TAB 3 · DATA HEALTH (stored records that need attention)
# =========================================================

with tab_health:

    st.subheader("🩺 Data health of the distributor and vendor databases")
    st.caption(
        "Every stored record is checked against the manufacturer: is its code a real code, "
        "and do its medicine name, manufacturer and dates agree? Applying fixes (cleansing) "
        "is on the Data cleansing tab."
    )

    try:
        flags = record_flags()

        summary = flags.pivot_table(
            index="source", columns="status", values="record_id", aggfunc="count", fill_value=0
        )
        st.dataframe(summary, use_container_width=True)

        problems = flags[flags["status"] != "OK"]

        if problems.empty:
            st.success("✓ Every stored record matches the manufacturer's data.")
        else:
            st.markdown(f"### ⚠️ {len(problems)} record(s) need attention")
            st.dataframe(
                problems[["source", "record_id", "stored_code", "status", "issues",
                          "name", "company", "expiry", "distributor_id", "vendor_name"]],
                use_container_width=True, hide_index=True
            )

            keys = [f"{r['source']} #{r['record_id']} · {r['stored_code']}" for _, r in problems.iterrows()]
            pick = st.selectbox("Explain which record?", keys, key="health_pick")
            if st.button("🔎 EXPLAIN", key="health_explain"):
                st.session_state["health_record"] = pick

            picked = st.session_state.get("health_record")
            if picked in keys:
                rec = problems.iloc[keys.index(picked)]
                result = match_stored_record(rec["source"], rec["record_id"])
                if result.empty:
                    st.error("❌ No real item resembles this record.")
                else:
                    verdict = result.iloc[0]["verdict"]
                    decided = result.iloc[0]["decided_item"]
                    decided = decided if pd.notna(decided) else None
                    st.markdown(
                        f"**{picked}** → **{verdict}**"
                        + (f" → belongs to **{decided}**" if decided else " → needs a person to decide")
                    )
                    show_candidates(result)
                    show_edit_steps(rec["stored_code"], decided or result.iloc[0]["item_code"])

    except Exception as e:
        st.error(f"❌ Data health check failed: {e}")

    try:
        with st.expander("🏛️ Sources and what the mediator has learned about them"):
            sources, reliability = source_registry()
            st.markdown("**Registered sources** (each finds its own candidates; the mediator never reads a whole table)")
            st.dataframe(sources, use_container_width=True, hide_index=True)
            st.markdown("**Reliability** (prior 0.9 until fixes are checked; updated by CHECK APPLIED FIXES)")
            st.dataframe(reliability, use_container_width=True, hide_index=True)
    except Exception as e:
        st.error(f"❌ Could not load the source registry: {e}")


# =========================================================
# TAB 4 · DATA CLEANSING
# =========================================================

with tab_cleanse:

    st.subheader("🧹 Data cleansing")
    st.caption(
        "No database is assumed correct. For every item the mediator compares what the manufacturer, "
        "distributor and vendor record and takes a majority vote (2 of 3) for the code, medicine name, "
        "manufacturer and dates. Values that disagree with the majority are fixed; ties go to a person. "
        "The mediator never edits the other databases: each owner downloads and runs their own fix script, "
        "then CHECK APPLIED FIXES records the changes in the cleansing log."
    )

    c1, c2 = st.columns(2)
    with c1:
        scan_button = st.button("▶ RUN CLEANSING SCAN", type="primary", use_container_width=True, key="scan")
    with c2:
        check_button = st.button("🔎 CHECK APPLIED FIXES", use_container_width=True, key="check")

    if scan_button:
        try:
            with st.spinner("Scanning the manufacturer, distributor and vendor databases..."):
                scan_id = cleansing_scan()
            st.success(f"✅ Scan #{scan_id} finished.")
        except Exception as e:
            st.error(f"❌ Cleansing scan failed: {e}")

    if check_button:
        try:
            applied, pending = cleansing_check()
            if applied:
                st.success(f"✅ {applied} fix(es) found in the databases and written to the cleansing log.")
            if pending:
                st.warning(f"⏳ {pending} fix(es) not applied yet — run the downloaded scripts on their databases.")
            if not applied and not pending:
                st.info("Nothing waiting to be applied.")
        except Exception as e:
            st.error(f"❌ Check failed: {e}")

    try:
        scan = latest_scan()

        if scan.empty:
            st.info("No scan yet. Click RUN CLEANSING SCAN.")

        else:
            scan_id = int(scan.iloc[0]["scan_id"])
            props = cleansing_proposals()
            st.markdown(f"### Scan #{scan_id} · {scan.iloc[0]['started_at']}")

            fixes = props[props["action"].isin(["UPDATE", "DELETE"])]
            reviews = props[(props["action"] == "REVIEW") & (props["status"] == "PROPOSED")]
            m1, m2, m3, m4 = st.columns(4)
            m1.metric("Fixes to run", int((fixes["status"] == "PROPOSED").sum()))
            m2.metric("Of which deletions", int(((fixes["status"] == "PROPOSED") & (fixes["action"] == "DELETE")).sum()))
            m3.metric("Need a decision", len(reviews))
            m4.metric("Applied", int((fixes["status"] == "APPLIED").sum()))

            if props.empty:
                st.success("✓ No anomalies: every value agrees across the three databases.")

            # ---------------------------------------------
            # REVIEWS: no majority, a person decides
            # ---------------------------------------------
            if not reviews.empty:
                st.markdown("### ❓ Needs a decision")
                for _, p in reviews.iterrows():
                    pid = int(p["proposal_id"])
                    st.markdown(
                        f"**#{pid} · {p['source'].title()} {p['field']} `{p['old_value']}`** "
                        f"({p['target_db']}.{p['target_table']} {p['key_column']} = {p['key_value']}) — {p['reason']}"
                    )
                    labels = review_options(p)
                    if not labels:
                        st.info("Correct this value by hand in the database that is wrong, then scan again.")
                        continue
                    suggested = p["suggested"] if pd.notna(p["suggested"]) else None
                    choice = st.selectbox(
                        "Choose the correct value",
                        labels,
                        format_func=lambda l, s=suggested: ("⭐ suggested: " if l == s else "") + l,
                        key=f"review_{pid}",
                    )
                    if st.button("✔ APPLY CHOICE", key=f"resolve_{pid}"):
                        try:
                            added = cleansing_resolve(pid, choice)
                            st.success(
                                f"✅ Choice applied: {added} fix(es) added to the scripts below."
                                if added else "✅ Choice applied (recorded; no database change needed)."
                            )
                            st.rerun()
                        except Exception as e:
                            st.error(f"❌ Could not apply choice: {e}")

            # ---------------------------------------------
            # FIXES PER DATABASE + DOWNLOADABLE SCRIPT
            # ---------------------------------------------
            for db in DATABASES:
                part = fixes[fixes["target_db"] == db]
                to_run = int((part["status"] == "PROPOSED").sum())
                done = int((part["status"] == "APPLIED").sum())
                st.markdown(f"### 🗄️ {db} — {to_run} to run, {done} applied")
                if part.empty:
                    st.caption("Nothing to fix in this database.")
                    continue
                table = part[["status", "action", "target_table", "key_column", "key_value",
                              "column_name", "old_value", "new_value", "reason"]].copy()
                table.insert(0, "", table["status"].map({"APPLIED": "✅", "PROPOSED": "⏳"}).fillna(""))
                st.dataframe(table, use_container_width=True, hide_index=True)
                if to_run:
                    script = cleansing_fix_sql(db)
                    st.download_button(
                        f"⬇️ Download fix script for {db}",
                        script,
                        file_name=f"fix_{db}_scan{scan_id}.sql",
                        mime="text/plain",
                        key=f"download_{db}",
                    )
                    with st.expander(f"Show the SQL for {db}"):
                        st.code(script, language="sql")

        # ---------------------------------------------
        # LOG OF APPLIED CHANGES
        # ---------------------------------------------
        st.markdown("### 📜 Cleansing log")
        log = cleansing_log()
        if log.empty:
            st.caption("No fixes applied yet.")
        else:
            st.dataframe(log, use_container_width=True, hide_index=True)

    except Exception as e:
        st.error(f"❌ Could not load cleansing results: {e}")


# =========================================================
# TAB 5 · REPORTS (Phase 1)
# =========================================================

with tab_reports:

    st.subheader(
        "📢 Reports to Ministry of Consumer Affairs"
    )

    try:

        reports = get_reports()

        if reports.empty:

            st.info(
                "No suspicious medicines have been reported yet."
            )

        else:

            st.write(
                f"**Total Reports: {len(reports)}**"
            )

            st.dataframe(
                reports,
                use_container_width=True,
                hide_index=True
            )

    except Exception as e:

        st.error(
            f"❌ Could not load reports: {e}"
        )


# =========================================================
# TAB 6 · ANALYSIS (Phase 1)
# =========================================================

with tab_analysis:

    st.subheader("📊 Medicine Analysis")

    st.write(
        "Analysis uses a materialized view snapshot. "
        "Verification remains live through the global view."
    )

    refresh_col1, refresh_col2 = st.columns([4, 1])

    with refresh_col1:
        st.write(
            "Click refresh whenever you want the latest "
            "distributed database data in the analysis."
        )

    with refresh_col2:

        refresh_button = st.button(
            "🔄 REFRESH",
            type="primary",
            use_container_width=True
        )


    if refresh_button:

        try:

            refresh_analysis()

            st.success(
                "✅ Analysis data refreshed successfully."
            )

            st.rerun()

        except Exception as e:

            st.error(
                f"❌ Analysis refresh failed: {e}"
            )


    st.markdown("### 📌 Status Analysis")

    try:

        status_df = get_analysis_status()

        if not status_df.empty:

            st.dataframe(
                status_df,
                use_container_width=True,
                hide_index=True
            )

        else:

            st.info(
                "No analysis data available."
            )

    except Exception as e:

        st.error(
            f"❌ Status analysis failed: {e}"
        )


    st.markdown("### 🚚 Distributor Analysis")

    try:

        distributor_df = get_distributor_analysis()

        st.dataframe(
            distributor_df,
            use_container_width=True,
            hide_index=True
        )

    except Exception as e:

        st.error(
            f"❌ Distributor analysis failed: {e}"
        )


    st.markdown("### 🏪 Vendor Analysis")

    try:

        vendor_df = get_vendor_analysis()

        st.dataframe(
            vendor_df,
            use_container_width=True,
            hide_index=True
        )

    except Exception as e:

        st.error(
            f"❌ Vendor analysis failed: {e}"
        )


    st.markdown("### 🚨 Suspicion Reason Analysis")

    try:

        suspicion_df = get_suspicion_analysis()

        if not suspicion_df.empty:

            st.dataframe(
                suspicion_df,
                use_container_width=True,
                hide_index=True
            )

        else:

            st.info(
                "No suspicious reasons available."
            )

    except Exception as e:

        st.error(
            f"❌ Suspicion analysis failed: {e}"
        )


    st.markdown(
        "### 🔄 Distributor / Vendor Mismatch Analysis"
    )

    try:

        mismatch_df = get_mismatch_analysis()

        if not mismatch_df.empty:

            st.dataframe(
                mismatch_df,
                use_container_width=True,
                hide_index=True
            )

        else:

            st.success(
                "✓ No distributor/vendor ID mismatches found."
            )

    except Exception as e:

        st.error(
            f"❌ Mismatch analysis failed: {e}"
        )


# =========================================================
# TAB 7 · MATCHING SETTINGS (read-only)
# =========================================================

with tab_settings:

    st.subheader("⚙️ How matching decides")
    st.markdown(
        "- **Stage 1 – code:** every item whose code is at least `min_code_similarity` similar "
        "(weighted edit distance: look-alike characters are cheap, unrelated ones expensive) is a candidate.\n"
        "- **Stage 2 – context:** each candidate gets a **total score** = weighted average of the evidence "
        "available (code, medicine name, expiry, manufacturer, mfg date, and for stored records the "
        "distributor and supply links). Missing evidence is left out, not counted as wrong.\n"
        "- **Verdict:** MATCH if the best total is at least `match_threshold` and clearly ahead of the "
        "runner-up (`total_margin`, or `code_margin` cheaper code with context at least as good); "
        "REVIEW if several items are close; NO MATCH below `review_threshold`.\n"
        "- **Where candidates come from:** each source database finds its own top `probe_k` candidates with "
        "an index (one typing error away, same folded code, or same medicine and expiry month) and sends only "
        "those. The mediator never reads a whole table.\n"
        "- **Dynamic weights:** each attribute weight = base weight × how well it tells the candidates apart "
        "(floor `discrimination_floor`) × how reliable the record's source has been for it.\n"
        "- **Most trustworthy record:** six factors (entity, context, completeness, attribute and source "
        "reliability, consistency) weighted by the `beta_*` settings; accepted at `trust_accept` when clearly "
        "ahead of the records that disagree, otherwise REVIEW. Cleansing votes are weighted by reliability "
        "and need `vote_accept_share` of the support."
    )

    try:
        config, costs = match_settings()
        st.markdown("### Weights and thresholds (`match_config`)")
        st.dataframe(config, use_container_width=True, hide_index=True)
        st.markdown("### Character costs for codes (`code_char_costs`)")
        st.dataframe(costs, use_container_width=True, hide_index=True)
    except Exception as e:
        st.error(f"❌ Could not load matching settings: {e}")
