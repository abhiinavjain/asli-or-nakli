"""
Asli-or-Nakli · Phase 3 · Streamlit views (imported by gui.py).

One story, told in five steps on one screen:

    ① your question          what was asked (free text and/or details)
    ② Phase 2 matching        each item code is matched and verified with the Phase 1 + 2 rules
    ③ structured context      the three databases, each on its own machine, walk their FK -> PK links
    ④ unstructured documents  the context becomes search terms; related documents are found
    ⑤ answer                  one verdict with the evidence from ③ and ④

    inject_css()                                  shared look for every page
    page_header(title, subtitle, phase)           page title with the phase badge
    render_ask_page(get_connection)               Phase 3 · Ask across databases
    render_schemas_page(get_connection)           Phase 3 · Databases and FK links
    render_code_tab()                             Phase 3 · Prompt and code (rubric item 4)
    render_verify_context(get_connection, item, pack)   the same five steps under a Verify result
"""

from __future__ import annotations

import difflib
import html
import json
import os
import re
from pathlib import Path

import pandas as pd
import streamlit as st

from asli_phase3 import ask

APP_DIR = Path(__file__).resolve().parent
PHASE3_DIR = APP_DIR.parent

SOURCES = ["manufacturer", "distributor", "vendor"]
SOURCE_ICON = {"manufacturer": "🏭", "distributor": "🚚", "vendor": "🏪", "documents": "📄",
               "verification": "🔍"}
SEVERITY_ICON = {3: "🔴", 2: "🟠", 1: "⚪"}
LEVEL_CLASS = {"HIGH RISK": ("hero-high", "🚨"), "CAUTION": ("hero-caution", "⚠️"),
               "NO RED FLAGS FOUND": ("hero-ok", "✅"), "NOT FOUND": ("hero-none", "🔍")}
# tables each source had before Phase 3 (the rest are the new FK -> PK tables)
ORIGINAL_TABLES = {"manufacturers", "medicines", "manufactured_items", "distributors", "inventory_items",
                   "supplied_items", "vendors", "vendor_inventory", "medicine_sales"}

EXAMPLES = [
    ("Ibuprofen at CityCare", "Is Ibuprofen from Sunrise sold at CityCare safe?"),
    ("Item ITEM000041", "ITEM000041"),
    ("Customer complaint", "Customer says the tablets are crumbly and there is no hologram"),
    ("Heat damage", "Amoxicillin capsules sticky after transport in the heat"),
    ("Clean medicine", "Tell me about Vitamin C 500mg"),
]

CSS = """
<style>
.block-container {padding-top: 3.2rem; max-width: 1250px;}
.page-head {margin: 0 0 .6rem 0;}
.page-head h1 {font-size: 1.75rem; margin: 0 0 .15rem 0;}
.page-head p {opacity: .75; margin: 0;}
.phase-badge {display:inline-block; font-size:.72rem; font-weight:700; letter-spacing:.04em;
              padding:2px 10px; border-radius:999px; margin-bottom:.35rem;
              background:rgba(79,70,229,.12); color:#4f46e5; border:1px solid rgba(79,70,229,.35);}
.phase-badge.p12 {background:rgba(13,148,136,.12); color:#0d9488; border-color:rgba(13,148,136,.35);}
.flow {display:flex; flex-wrap:wrap; gap:6px; align-items:center; margin:.4rem 0 1rem 0;}
.flow .box {padding:4px 11px; border-radius:8px; font-size:.84rem;
            background:rgba(79,70,229,.08); border:1px solid rgba(79,70,229,.28);}
.flow .arrow {opacity:.45;}
.step-head {display:flex; align-items:center; gap:.65rem; margin:1.5rem 0 .25rem 0;}
.step-num {background:#4f46e5; color:#fff; border-radius:999px; min-width:30px; height:30px;
           display:inline-flex; align-items:center; justify-content:center; font-weight:800;}
.step-title {font-size:1.15rem; font-weight:750;}
.step-sub {opacity:.7; font-size:.9rem; margin:0 0 .6rem 2.6rem;}
.chip {display:inline-block; padding:2px 10px; margin:2px 5px 3px 0; border-radius:999px; font-size:.82rem;
       border:1px solid rgba(128,128,128,.35); background:rgba(128,128,128,.07); white-space:nowrap;}
.chip b {font-weight:650;}
.chip .src {opacity:.6; font-size:.74rem; margin-left:4px;}
.chip.cat {border-color:rgba(220,38,38,.4); background:rgba(220,38,38,.07);}
.chip.new {border-color:rgba(79,70,229,.45); background:rgba(79,70,229,.1); font-size:.7rem; padding:0 7px;}
.chip.real {border-color:rgba(22,163,74,.45); background:rgba(22,163,74,.08);}
.chip.demo {border-color:rgba(245,158,11,.5); background:rgba(245,158,11,.08);}
.hero {border-radius:14px; padding:16px 20px; margin:.4rem 0 .2rem 0; border:1px solid;}
.hero-high {background:rgba(220,38,38,.08); border-color:rgba(220,38,38,.45);}
.hero-caution {background:rgba(245,158,11,.09); border-color:rgba(245,158,11,.5);}
.hero-ok {background:rgba(22,163,74,.08); border-color:rgba(22,163,74,.45);}
.hero-none {background:rgba(100,116,139,.08); border-color:rgba(100,116,139,.4);}
.hero .level {font-size:1.45rem; font-weight:800; margin-bottom:.15rem;}
.hero .headline {font-size:1rem; margin-bottom:.35rem;}
.code {font-family: ui-monospace, Consolas, monospace; font-weight:650;}
.muted {opacity:.65; font-size:.85rem;}
.why {font-size:.86rem; margin-top:.25rem;}
</style>
"""


def inject_css():
    st.markdown(CSS, unsafe_allow_html=True)


def page_header(title: str, subtitle: str, phase: str = "PHASE 3 · STRUCTURED → UNSTRUCTURED"):
    cls = "phase-badge p12" if phase.startswith("PHASE 1") else "phase-badge"
    st.markdown(f'<div class="page-head"><span class="{cls}">{html.escape(phase)}</span>'
                f'<h1>{html.escape(title)}</h1><p>{html.escape(subtitle)}</p></div>', unsafe_allow_html=True)


def _step(num: str, title: str, sub: str = ""):
    st.markdown(f'<div class="step-head"><span class="step-num">{num}</span>'
                f'<span class="step-title">{html.escape(title)}</span></div>'
                + (f'<div class="step-sub">{html.escape(sub)}</div>' if sub else ""), unsafe_allow_html=True)


def _chips(items, cls: str = "") -> str:
    return "".join(f'<span class="chip {cls}">{x}</span>' for x in items)


def _flow():
    boxes = ["① Your question", "② Phase 2 matching", "③ 3 databases · FK → PK context",
             "④ Documents", "⑤ Answer"]
    st.markdown('<div class="flow">' + '<span class="arrow">→</span>'.join(
        f'<span class="box">{b}</span>' for b in boxes) + "</div>", unsafe_allow_html=True)


# ---------------------------------------------------------------------
# running a query
# ---------------------------------------------------------------------
@st.cache_resource(show_spinner="Loading the search model (once)...")
def _warm(_get_connection):
    from asli_phase3 import warm_up
    conn = _get_connection()
    try:
        warm_up(conn)
    finally:
        conn.close()
    return True


def _run(get_connection, question, fields, use_llm):
    _warm(get_connection)
    conn = get_connection()
    try:
        return ask(conn, question, fields, use_llm=use_llm)
    finally:
        conn.close()


def _rows(row_data) -> dict:
    return row_data if isinstance(row_data, dict) else json.loads(row_data)


# ---------------------------------------------------------------------
# the five-step result
# ---------------------------------------------------------------------
def _hero(r):
    cls, icon = LEVEL_CLASS.get(r.assessment["level"], ("hero-none", "ℹ️"))
    cats = r.assessment.get("categories") or []
    head, _, strongest = r.assessment["headline"].partition(". Strongest: ")
    joined = " + ".join(cats)
    if cats and head == joined:                 # the labels below say it all
        head = ""
    elif cats and head.endswith(": " + joined):  # "The code is genuine (X), but: A + B" -> labels after "but:"
        head = head[: -len(joined)].rstrip()
    st.markdown(
        f'<div class="hero {cls}"><div class="level">{icon} {html.escape(r.assessment["level"])}</div>'
        + (f'<div class="headline">{html.escape(head)}</div>' if head else "")
        + (_chips([html.escape(c) for c in cats], "cat") if cats else "")
        + (f'<div class="headline" style="margin-top:.4rem"><b>Strongest evidence:</b> {html.escape(strongest)}</div>'
           if strongest else "")
        + f'<div class="muted" style="margin-top:.35rem">Next step: {html.escape(r.assessment["next_step"])}</div></div>',
        unsafe_allow_html=True)


def _step_matching(r):
    _step("②", "Phase 2 matching", "Each item code in the question goes through the same matching and checks "
                                   "as the Verify page: noisy codes are resolved, then the item is verified.")
    if not r.items:
        st.info("No item code in the question: the databases were searched by names and words instead.")
        return
    for it in r.items:
        batch = (it.get("batch") or {}).get("batch_no") or "—"
        with st.container(border=True):
            c1, c2, c3, c4, c5 = st.columns([1.2, 1.2, 1.2, 1.1, 1.3])
            c1.metric("You typed", it["code"])
            c2.metric("Matched item", it["item"] or "—")
            c3.metric("Phase 2 result", it["verdict"] or "—")
            c4.metric("Phase 1 status", it["risk"] or "—")
            c5.metric("Its own batch", batch)
            notes = [m for _, sev, m in it["signals"] if sev >= 2]
            if it.get("reasons"):
                st.caption("Phase 1 reasons: " + " · ".join(it["reasons"]))
            for m in notes[:3]:
                st.caption("• " + m)


def _step_structured(r):
    _step("③", "Structured context from the three databases",
          "The question was sent to all three machines at once. Each one walked its own foreign keys from what "
          "it recognised and sent back only the related rows. Round 2 passed keys from one database to another.")
    calls, ctx = r.calls, r.context
    cols = st.columns(3)
    for col, src in zip(cols, SOURCES):
        part = ctx[ctx["source_id"] == src] if not ctx.empty else ctx
        mine = calls[calls["source_id"] == src] if not calls.empty else calls
        status = " · ".join(f"R{c.round} {c.status}" for c in mine.itertuples()) or "not asked"
        ms = int(mine["elapsed_ms"].fillna(0).astype(float).max()) if not mine.empty else 0
        with col.container(border=True):
            st.markdown(f"**{SOURCE_ICON[src]} {src}_db**")
            st.caption(f"{status} · {ms} ms")
            st.metric("Related rows", len(part))
            if not part.empty:
                counts = part.groupby("table_name").size().sort_values(ascending=False)
                st.markdown(_chips([f"<b>{html.escape(t)}</b> ×{n}" for t, n in counts.items()]),
                            unsafe_allow_html=True)
    # keys passed between databases
    r2 = calls[calls["round"] == 2] if not calls.empty else calls
    passed = []
    for c in r2.itertuples():
        for s in (c.seeds or []):
            passed.append(f'→ {SOURCE_ICON.get(c.source_id, "")} {c.source_id}: '
                          f'<b>{html.escape(str(s.get("value")))}</b><span class="src">{html.escape(s.get("kind", ""))}</span>')
    if passed:
        st.markdown("**Keys one database found for another (round 2)**")
        st.markdown(_chips(passed[:14]), unsafe_allow_html=True)
    if not ctx.empty:
        with st.expander("🔗 See the rows each database returned, and the FK paths it followed"):
            st.graphviz_chart(_context_dot(ctx))
            for src in SOURCES:
                part = ctx[ctx["source_id"] == src]
                if part.empty:
                    continue
                st.markdown(f"**{SOURCE_ICON[src]} {src}_db**")
                for table, grp in sorted(part.groupby("table_name"), key=lambda kv: -kv[1]["relevance"].max()):
                    data = pd.DataFrame([_rows(x) for x in grp["row_data"]])
                    data.insert(0, "relevance", grp["relevance"].astype(float).round(2).values)
                    data = data.dropna(axis=1, how="all")
                    st.caption(f"{table} — path: {grp.iloc[0]['path']}")
                    st.dataframe(data, use_container_width=True, hide_index=True)


def _step_documents(r):
    _step("④", "Unstructured documents found with that context",
          "The names, batch numbers, codes and shops found in step ③ became search terms. Documents are ranked by "
          "full-text match, meaning (embeddings) and exact mentions of this case's entities.")
    terms = r.terms
    found_in = {}
    if not terms.empty:
        for t in terms.itertuples():
            found_in[str(t.term).lower()] = (t.term, t.term_kind, str(t.found_in).split(",")[0].strip())
        st.markdown("**Search terms from the context**")
        st.markdown(_chips([f'<b>{html.escape(str(t.term))}</b><span class="src">{html.escape(str(t.found_in).split(",")[0])}</span>'
                            for t in terms.head(10).itertuples()]), unsafe_allow_html=True)
    if r.documents.empty:
        st.info("No document is related to this context (weak matches are not shown).")
        return
    for i, d in enumerate(r.documents.itertuples(), 1):
        text = f"{d.title} {d.body or ''}".lower()
        why = [v for k, v in found_in.items() if k and k in text]
        with st.container(border=True):
            left, right = st.columns([4, 1.3])
            with left:
                badge = '<span class="chip real">🌍 REAL</span>' if d.origin == "REAL" else '<span class="chip demo">🧪 DEMO</span>'
                st.markdown(f"**[D{i}] {html.escape(d.title)}**", unsafe_allow_html=True)
                st.markdown(badge + f'<span class="muted">{html.escape(str(d.doc_type).replace("_", " ").title())} · '
                            f'{html.escape(str(d.issuer or ""))} · {d.published_on or ""}</span>', unsafe_allow_html=True)
                st.markdown("> " + (d.headline or "").replace("\n", " "))
                if why:
                    st.markdown('<div class="why">Matched because it mentions: ' + _chips(
                        [f'<b>{html.escape(str(t))}</b><span class="src">from {html.escape(src)}</span>'
                         for t, _, src in why[:6]]) + "</div>", unsafe_allow_html=True)
                if d.url:
                    st.markdown(f"[Open the source ↗]({d.url})")
            with right:
                st.metric("Score", f"{float(d.score):.2f}")
                st.progress(min(1.0, float(d.score)))
                st.caption(f"full-text {('—' if pd.isna(d.lexical) else f'{float(d.lexical):.2f}')} · "
                           f"meaning {('—' if pd.isna(d.semantic) else f'{float(d.semantic):.2f}')} · "
                           f"entities {len(d.entity_hits or [])}")


def _step_answer(r):
    _step("⑤", "Answer", "Structured evidence (③) and documents (④) combined into one verdict.")
    lines = [l for l in r.answer.splitlines()
             if not l.startswith("**Assessment") and not l.startswith("**Problem type")]
    st.markdown("\n".join(lines).strip())
    counted = [s for s in r.signals if s["severity"] >= 2]
    context_only = [s for s in r.signals if s["severity"] < 2]
    if counted:
        with st.expander(f"🚩 All {len(counted)} signal(s) behind the verdict"):
            for i, s in enumerate(counted, 1):
                st.markdown(f"{SEVERITY_ICON.get(s['severity'], '')} **{s['rule']}** · "
                            f"{SOURCE_ICON.get(s['source'], '')} {s['source']} · relevance {s['relevance']:.2f}  \n"
                            f"{s['message']}")
    if context_only:
        with st.expander(f"⚪ {len(context_only)} related finding(s) that are NOT about this item (context only)"):
            for s in context_only:
                st.markdown(f"**{s['rule']}** · {s['source']}  \n{s['message']}")
    st.caption(("🤖 Written by an AI model from the evidence above — check the cited rows and documents."
                if r.answer_how.startswith("llm") else "📝 Written from rules (no AI key configured).")
               + f" · Query #{r.query_id} · " + " · ".join(f"{k} {v:.2f} s" for k, v in r.timings.items()))
    with st.expander("⚙️ Technical details: federation graph and every sub-query"):
        st.graphviz_chart(_federation_dot(r))
        calls = r.calls.copy()
        calls["seeds"] = calls["seeds"].map(lambda s: ", ".join(f"{x['kind']}={x['value']}" for x in (s or []))[:200])
        st.dataframe(calls, use_container_width=True, hide_index=True)


def show_pipeline(r, show_question: bool = True):
    if show_question:
        _step("①", "Your question")
        seeds = [f'<b>{html.escape(str(s.get("value")))}</b><span class="src">{html.escape(s.get("kind", ""))}</span>'
                 for s in (r.seeds or [])]
        st.markdown(f'<span class="muted">“{html.escape(r.question or "(details only)")}”</span> &nbsp; '
                    + (_chips(seeds) if seeds else '<span class="muted">no search keys found</span>'),
                    unsafe_allow_html=True)
    _hero(r)
    _step_matching(r)
    _step_structured(r)
    _step_documents(r)
    _step_answer(r)


def _federation_dot(r) -> str:
    lines = ['digraph G { rankdir=LR; node [shape=box, style="rounded,filled", fillcolor="#f5f5f5", fontname="Helvetica"];',
             'Q [label="your question", fillcolor="#dbeafe"];', 'M [label="mediator\\n(dblink, parallel)", fillcolor="#e0e7ff"];',
             'Q -> M;']
    for c in r.calls.itertuples():
        node = f"{c.source_id}_{c.round}"
        color = {"OK": "#dcfce7", "SKIPPED": "#f3f4f6"}.get(c.status, "#fee2e2")
        lines.append(f'{node} [label="{c.source_id}\\nround {c.round}\\n{c.status} · {c.rows_back} rows · '
                     f'{float(c.elapsed_ms or 0):.0f} ms", fillcolor="{color}"];')
        style = "" if c.round == 1 else ", style=dashed"
        lines.append(f'M -> {node} [label="{c.seeds_sent} {"keys" if c.round == 1 else "new keys"}"{style}];')
    lines.append(f'D [label="documents\\n{len(r.documents)} related", fillcolor="#fef9c3"];')
    lines.append('M -> D [label="context terms"];')
    lines.append("}")
    return "\n".join(lines)


def _context_dot(ctx: pd.DataFrame) -> str:
    edges, nodes = set(), {}
    for row in ctx.itertuples():
        steps = [p.strip() for p in str(row.path).split("→")]
        steps[0] = steps[0].split(".")[0].split(" = ")[0]
        names = [f"{row.source_id}.{s}" for s in steps]
        for n in names:
            nodes[n] = max(nodes.get(n, 0), float(row.relevance))
        edges.update(zip(names, names[1:]))
    lines = ['digraph C { rankdir=LR; node [shape=box, style="rounded,filled", fontname="Helvetica"];']
    for src in SOURCES:
        mine = [n for n in nodes if n.startswith(src + ".")]
        if not mine:
            continue
        lines.append(f'subgraph cluster_{src} {{ label="{src}_db"; style=rounded; color="#9ca3af";')
        for n in mine:
            shade = int(255 - 120 * min(1, nodes[n]))
            lines.append(f'"{n}" [label="{n.split(".", 1)[1]}", fillcolor="#{shade:02x}{shade:02x}ff"];')
        lines.append("}")
    for a, b in sorted(edges):
        lines.append(f'"{a}" -> "{b}";')
    lines.append("}")
    return "\n".join(lines)


# ---------------------------------------------------------------------
# page: Ask across databases
# ---------------------------------------------------------------------
def render_ask_page(get_connection):
    try:      # load the search model when the page opens, not during the first question
        _warm(get_connection)
    except Exception:
        pass
    page_header("Ask across all databases and documents",
                "From a question to structured context on three machines, then to the documents that context points to.")
    _flow()

    ex = st.columns(len(EXAMPLES))
    for i, (label, q) in enumerate(EXAMPLES):
        if ex[i].button(label, key=f"p3_ex_{i}", use_container_width=True, help=q):
            st.session_state["p3_question"] = q

    with st.form("p3_form"):
        question = st.text_area("Your question", key="p3_question", height=70,
                                placeholder="e.g. Is Ibuprofen from Sunrise sold at CityCare safe?  ·  or just an item code")
        with st.expander("Optional details (item code, batch, medicine, maker, shop, distributor)"):
            c1, c2, c3 = st.columns(3)
            f_item = c1.text_input("Item code", key="p3_item")
            f_batch = c1.text_input("Batch number", key="p3_batch")
            f_med = c2.text_input("Medicine name", key="p3_med")
            f_mfr = c2.text_input("Manufacturer", key="p3_mfr")
            f_shop = c3.text_input("Shop", key="p3_shop")
            f_dist = c3.text_input("Distributor", key="p3_dist")
        has_key = bool(os.environ.get("ANTHROPIC_API_KEY"))
        use_llm = st.checkbox("Write the answer with AI", value=has_key, disabled=not has_key,
                              help=None if has_key else "Set ANTHROPIC_API_KEY before starting Streamlit to enable.")
        go = st.form_submit_button("🧠  Ask", type="primary", use_container_width=True)

    if go:
        fields = {"item_code": f_item, "batch_no": f_batch, "medicine_name": f_med,
                  "manufacturer_name": f_mfr, "vendor_name": f_shop, "distributor_name": f_dist}
        if not question.strip() and not any(v.strip() for v in fields.values()):
            st.warning("Type a question or fill in at least one detail.")
        else:
            try:
                with st.spinner("Asking the three databases and searching the documents..."):
                    st.session_state["p3_result"] = _run(get_connection, question.strip(),
                                                         {k: v.strip() for k, v in fields.items()}, use_llm)
            except Exception as e:
                st.session_state["p3_result"] = None
                st.error(f"❌ Phase 3 query failed: {e}")

    r = st.session_state.get("p3_result")
    if r is not None:
        show_pipeline(r)


# ---------------------------------------------------------------------
# page: databases and FK links (rubric item 1)
# ---------------------------------------------------------------------
@st.cache_data(ttl=600, show_spinner="Reading the three machines...")
def _source_schemas(_get_connection):
    conn = _get_connection()
    try:
        return (pd.read_sql("SELECT * FROM p3_source_tables()", conn),
                pd.read_sql("SELECT * FROM p3_source_schemas()", conn),
                pd.read_sql("SELECT source_kind, table_name, column_name, seed_kind, target_kinds FROM p3_links "
                            "ORDER BY 1, 2", conn))
    finally:
        conn.close()


def render_schemas_page(get_connection):
    page_header("The three databases and their FK → PK links",
                "Read live from each machine. Every database now spreads an entity over several tables joined by "
                "foreign keys; the new Phase 3 tables are marked NEW.")
    if st.button("🔄 Read again from the machines"):
        _source_schemas.clear()
    try:
        tables, edges, links = _source_schemas(get_connection)
    except Exception as e:
        st.error(f"❌ Could not read the source schemas: {e}")
        return
    cols = st.columns(3)
    for col, src in zip(cols, SOURCES):
        part = tables[tables["source_id"] == src]
        with col.container(border=True):
            st.markdown(f"### {SOURCE_ICON[src]} {src}_db")
            if part.empty:
                st.warning("This machine did not answer.")
                continue
            st.caption(f"{len(part)} tables · {int(part['row_count'].fillna(0).sum())} rows · "
                       f"{len(edges[edges['source_id'] == src])} foreign keys")
            for t in part.sort_values(["fk_links", "table_name"], ascending=[False, True]).itertuples():
                new = '<span class="chip new">NEW</span>' if t.table_name not in ORIGINAL_TABLES else ""
                st.markdown(f'<span class="code">{html.escape(t.table_name)}</span> {new} '
                            f'<span class="muted">· {int(t.row_count or 0)} rows · {html.escape(str(t.label or t.role))}</span>',
                            unsafe_allow_html=True)
    st.markdown("#### Foreign keys inside each database")
    dot = ['digraph S { rankdir=LR; node [shape=box, style="rounded,filled", fillcolor="#f8fafc", fontname="Helvetica"];']
    for src in SOURCES:
        part = tables[tables["source_id"] == src]
        if part.empty:
            continue
        dot.append(f'subgraph cluster_{src} {{ label="{src}_db"; style=rounded;')
        for t in part.itertuples():
            fill = "#e0e7ff" if t.table_name not in ORIGINAL_TABLES else "#f1f5f9"
            dot.append(f'"{src}.{t.table_name}" [label="{t.table_name}", fillcolor="{fill}"];')
        dot.append("}")
    for e in edges.itertuples():
        dot.append(f'"{e.source_id}.{e.child_table}" -> "{e.source_id}.{e.parent_table}" [label="{e.child_column}", fontsize=9];')
    dot.append("}")
    st.graphviz_chart("\n".join(dot))
    st.caption("Arrow = foreign key, from the referencing table to the referenced one. Blue = new Phase 3 table.")
    st.markdown("#### How the databases connect to each other (keys used in round 2)")
    st.dataframe(links.rename(columns={"source_kind": "found in", "table_name": "table", "column_name": "column",
                                       "seed_kind": "becomes a key of kind", "target_kinds": "sent to"}),
                 use_container_width=True, hide_index=True)
    with st.expander("Commands to look at the new tables yourself (run on each machine)"):
        st.code("-- on any source machine\nSELECT * FROM asli_ctx.fk_edges;            -- its foreign keys\n"
                "SELECT * FROM asli_ctx.v_schema;            -- its tables and roles\n"
                "SELECT * FROM asli_ctx.discover('[{\"kind\":\"item_code\",\"value\":\"ITEM000041\"}]');  -- its context for one item",
                language="sql")


# ---------------------------------------------------------------------
# panel inside Verify (the same five steps, without the question box)
# ---------------------------------------------------------------------
def render_verify_context(get_connection, item_code, pack):
    st.markdown("### 🌐 Phase 3 · structured context and documents for this item")
    pack = pack or {}
    fields = {"item_code": item_code, "batch_no": pack.get("batch"), "medicine_name": pack.get("name"),
              "manufacturer_name": pack.get("company"), "mfg": pack.get("mfg"), "expiry": pack.get("expiry"),
              "vendor_name": pack.get("shop"), "distributor_name": pack.get("distributor")}
    key = json.dumps(fields, sort_keys=True)
    if st.button("🌐 Find context and documents for this item", key=f"p3_verify_{item_code}", type="primary"):
        try:
            with st.spinner("Asking the three databases and searching the documents..."):
                st.session_state["p3_verify"] = (key, _run(get_connection, "", fields,
                                                            bool(os.environ.get("ANTHROPIC_API_KEY"))))
        except Exception as e:
            st.session_state["p3_verify"] = None
            st.error(f"❌ Phase 3 search failed: {e}")
    cached = st.session_state.get("p3_verify")
    if cached and cached[0] == key:
        show_pipeline(cached[1], show_question=False)
    else:
        st.caption("Batch, QC results, transport logs, complaints and outside documents for this item.")


# ---------------------------------------------------------------------
# page: prompt, generated code, modified code (rubric item 4)
# ---------------------------------------------------------------------
CODE_FILES = [
    ("Context engine (every source)", "sources/asli_ctx_core.sql"),
    ("manuf_db new tables", "sources/manufacturer_07_tables.sql"),
    ("distributor_db new tables", "sources/distributor_07_tables.sql"),
    ("vendor_db new tables", "sources/vendor_07_tables.sql"),
    ("Mediator: federated context", "mediator/mediator_07_federated_context.sql"),
    ("Mediator: documents + hybrid search", "mediator/mediator_08_documents.sql"),
    ("Orchestration (Python)", "app/asli_phase3.py"),
    ("Embeddings (Python)", "app/asli_semantic.py"),
    ("AI answer (Python)", "app/asli_llm.py"),
    ("Phase 3 GUI views (Python)", "app/gui_phase3.py"),
    ("Main GUI (Python)", "app/gui.py"),
    ("Document loader (Python)", "app/phase3_index_documents.py"),
    ("Documents (JSON)", "corpus/documents.json"),
]


def render_code_tab():
    page_header("Prompt, generated code and our modifications",
                "What we asked the AI, what it generated, and every change we made after testing it.")
    prompt_file = PHASE3_DIR / "prompts" / "PROMPT_phase3.md"
    with st.expander("📜 The prompt we gave the AI", expanded=False):
        st.markdown(prompt_file.read_text(encoding="utf-8") if prompt_file.exists() else "_prompts/PROMPT_phase3.md not found_")

    totals = []
    for label, rel in CODE_FILES:
        gen, cur = PHASE3_DIR / "generated" / rel, PHASE3_DIR / rel
        if gen.exists() and cur.exists():
            d = list(difflib.unified_diff(gen.read_text(encoding="utf-8").splitlines(),
                                          cur.read_text(encoding="utf-8").splitlines(), lineterm="", n=0))
            totals.append({"file": label, "lines added": sum(1 for l in d if l.startswith("+") and not l.startswith("+++")),
                           "lines removed": sum(1 for l in d if l.startswith("-") and not l.startswith("---"))})
    if totals:
        st.markdown("**Changed lines per file (generated → ours)**")
        st.dataframe(pd.DataFrame(totals), use_container_width=True, hide_index=True)

    label = st.selectbox("File", [l for l, _ in CODE_FILES])
    rel = dict(CODE_FILES)[label]
    gen, cur = PHASE3_DIR / "generated" / rel, PHASE3_DIR / rel
    if not gen.exists() or not cur.exists():
        st.warning(f"Missing {gen if not gen.exists() else cur}.")
        return
    a, b = gen.read_text(encoding="utf-8").splitlines(), cur.read_text(encoding="utf-8").splitlines()
    diff = list(difflib.unified_diff(a, b, fromfile=f"generated/{rel}", tofile=rel, lineterm="", n=2))
    view = st.radio("Show", ["Changes (diff)", "Generated code", "Our final code"], horizontal=True)
    lang = "sql" if rel.endswith(".sql") else ("json" if rel.endswith(".json") else "python")
    if view == "Changes (diff)":
        st.code("\n".join(diff) if diff else "No changes: the file is exactly as generated.", language="diff")
    elif view == "Generated code":
        st.code("\n".join(a), language=lang)
    else:
        st.code("\n".join(b), language=lang)
    notes = PHASE3_DIR / "prompts" / "MODIFICATIONS.md"
    if notes.exists():
        with st.expander("✍️ Why we changed it"):
            st.markdown(notes.read_text(encoding="utf-8"))
