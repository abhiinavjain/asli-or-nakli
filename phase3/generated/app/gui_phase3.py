"""
Asli-or-Nakli · Phase 3 · Streamlit views (imported by gui.py).

    render_ask_tab(get_connection)                 the "Ask across databases" tab
    render_verify_context(get_connection, item, pack)   Phase 3 panel inside Verify
    render_code_tab()                              "Prompt & code" tab (rubric item 4)
"""

from __future__ import annotations

import difflib
import json
import os
import re
from pathlib import Path

import pandas as pd
import streamlit as st

from asli_phase3 import ask

APP_DIR = Path(__file__).resolve().parent
PHASE3_DIR = APP_DIR.parent

LEVEL_STYLE = {
    "HIGH RISK": ("error", "🚨"),
    "CAUTION": ("warning", "⚠️"),
    "NO RED FLAGS FOUND": ("success", "✅"),
    "NOT FOUND": ("info", "🔍"),
}
SOURCE_ICON = {"manufacturer": "🏭", "distributor": "🚚", "vendor": "🏪", "documents": "📄"}
SEVERITY_ICON = {3: "🔴", 2: "🟠", 1: "🟡"}

EXAMPLES = [
    "Is Ibuprofen from Sunrise sold at CityCare safe?",
    "ITEM000035",
    "Customer says the tablets are crumbly and there is no hologram",
    "Amoxicillin capsules sticky after transport in the heat",
    "Tell me about Vitamin C 500mg",
]


# ---------------------------------------------------------------------
# shared result view
# ---------------------------------------------------------------------
def _run(get_connection, question, fields, use_llm):
    conn = get_connection()
    try:
        return ask(conn, question, fields, use_llm=use_llm)
    finally:
        conn.close()


def _show_result(r, key_prefix):
    kind, icon = LEVEL_STYLE.get(r.assessment["level"], ("info", "ℹ️"))
    getattr(st, kind)(f"{icon} **{r.assessment['level']}** — {r.assessment['headline']}")

    st.markdown(r.answer)
    st.caption(("🤖 Written by an AI model from the evidence below — check the cited rows and documents."
                if r.answer_how.startswith("llm") else
                "📝 Written from rules (no AI key configured)."
                ) + f" · Query #{r.query_id} · " + " · ".join(f"{k} {v:.2f} s" for k, v in r.timings.items()))

    t_fed, t_ctx, t_docs, t_sig, t_terms = st.tabs(
        ["🌐 Federation", "🔗 Context from the 3 databases", "📄 Documents", "🚩 Signals", "🔎 Search terms"])

    with t_fed:
        st.markdown("**Seeds taken from your query**")
        seeds = pd.DataFrame(r.seeds) if r.seeds else pd.DataFrame(columns=["kind", "value", "weight"])
        st.dataframe(seeds, use_container_width=True, hide_index=True)
        st.markdown("**Sub-queries sent to each machine** (round 1 in parallel; round 2 follows "
                    "keys that one database found for another)")
        calls = r.calls.copy()
        calls.insert(0, "", calls["source_id"].map(SOURCE_ICON).fillna(""))
        calls["seeds"] = calls["seeds"].map(
            lambda s: ", ".join(f"{x['kind']}={x['value']}" for x in (s or []))[:200])
        st.dataframe(calls, use_container_width=True, hide_index=True)
        st.graphviz_chart(_federation_dot(r))

    with t_ctx:
        if r.context.empty:
            st.info("No database recognised anything in this query.")
        else:
            st.caption("Each source walked its own FK → PK relationships from the seeds. Relevance falls "
                       "with every step; rows reached from several parts of the query rank higher.")
            st.graphviz_chart(_context_dot(r.context))
            for src in ["manufacturer", "distributor", "vendor"]:
                part = r.context[r.context["source_id"] == src]
                if part.empty:
                    continue
                st.markdown(f"**{SOURCE_ICON[src]} {src}** — {len(part)} row(s)")
                st.dataframe(part[["round", "table_name", "relevance", "hop", "path", "summary"]],
                             use_container_width=True, hide_index=True)

    with t_docs:
        if r.documents.empty:
            st.info("No document is related to this query context.")
        for i, d in enumerate(r.documents.itertuples(), 1):
            badge = "🌍 REAL" if d.origin == "REAL" else "🧪 DEMO (fictional)"
            with st.container(border=True):
                st.markdown(f"**[D{i}] {d.title}**  \n{badge} · {d.doc_type.replace('_', ' ').title()} · "
                            f"{d.issuer or ''} · {d.published_on or ''}")
                c1, c2, c3, c4 = st.columns(4)
                c1.metric("Score", f"{float(d.score):.2f}")
                c2.metric("Full-text", "—" if pd.isna(d.lexical) else f"{float(d.lexical):.2f}")
                c3.metric("Semantic", "—" if pd.isna(d.semantic) else f"{float(d.semantic):.2f}")
                c4.metric("Case entities", len(d.entity_hits or []))
                if d.entity_hits:
                    st.caption("Mentions: " + ", ".join(d.entity_hits))
                st.markdown("> " + (d.headline or "").replace("\n", " "))
                if d.url:
                    st.markdown(f"[Source]({d.url})")

    with t_sig:
        if not r.signals:
            st.success("No risk signal in the context or the documents.")
        for i, s in enumerate(r.signals, 1):
            st.markdown(f"{SEVERITY_ICON.get(s['severity'], '')} **[S{i}] {s['rule']}** · "
                        f"{SOURCE_ICON.get(s['source'], '')} {s['source']}.{s['table']} · "
                        f"relevance {s['relevance']:.2f}  \n{s['message']}")
            st.caption(f"path: {s['path']}")

    with t_terms:
        st.caption("The query context, turned into weighted search terms for the documents.")
        st.dataframe(r.terms, use_container_width=True, hide_index=True)


def _federation_dot(r) -> str:
    lines = ['digraph G { rankdir=LR; node [shape=box, style="rounded,filled", fillcolor="#f5f5f5", fontname="Helvetica"];',
             'Q [label="your query", fillcolor="#dbeafe"];', 'M [label="mediator\\n(dblink, parallel)", fillcolor="#e0e7ff"];',
             'Q -> M;']
    for c in r.calls.itertuples():
        node = f"{c.source_id}_{c.round}"
        color = {"OK": "#dcfce7", "SKIPPED": "#f3f4f6"}.get(c.status, "#fee2e2")
        lines.append(f'{node} [label="{c.source_id}\\nround {c.round}\\n{c.status} · {c.rows_back} rows · '
                     f'{float(c.elapsed_ms or 0):.0f} ms", fillcolor="{color}"];')
        if c.round == 1:
            lines.append(f'M -> {node} [label="{c.seeds_sent} seeds"];')
        else:
            lines.append(f'M -> {node} [label="{c.seeds_sent} new keys", style=dashed];')
    lines.append(f'D [label="documents\\n{len(r.documents)} related", fillcolor="#fef9c3"];')
    lines.append('M -> D [label="context terms"];')
    lines.append("}")
    return "\n".join(lines)


def _context_dot(ctx: pd.DataFrame) -> str:
    """Tables visited per source, with the FK steps that were followed."""
    edges, nodes = set(), {}
    for row in ctx.itertuples():
        steps = [p.strip() for p in str(row.path).split("→")]
        steps[0] = steps[0].split(".")[0].split(" = ")[0]
        names = [f"{row.source_id}.{s}" for s in steps]
        for n in names:
            nodes[n] = max(nodes.get(n, 0), float(row.relevance))
        for a, b in zip(names, names[1:]):
            edges.add((a, b))
    lines = ['digraph C { rankdir=LR; node [shape=box, style="rounded,filled", fontname="Helvetica"];']
    for src in ["manufacturer", "distributor", "vendor"]:
        mine = [n for n in nodes if n.startswith(src + ".")]
        if not mine:
            continue
        lines.append(f'subgraph cluster_{src} {{ label="{src}"; style=rounded; color="#9ca3af";')
        for n in mine:
            shade = int(255 - 120 * min(1, nodes[n]))
            lines.append(f'"{n}" [label="{n.split(".", 1)[1]}", fillcolor="#{shade:02x}{shade:02x}ff"];')
        lines.append("}")
    for a, b in sorted(edges):
        lines.append(f'"{a}" -> "{b}";')
    lines.append("}")
    return "\n".join(lines)


# ---------------------------------------------------------------------
# tab: Ask across databases
# ---------------------------------------------------------------------
def render_ask_tab(get_connection):
    st.subheader("🧠 Ask across all databases and documents")
    st.caption("Your question is split into sub-queries that run on the manufacturer, distributor and vendor "
               "machines at the same time. Each database finds the context around it through its own "
               "foreign keys; that context then searches regulator alerts, recalls, inspection reports, news "
               "and package inserts.")

    ex = st.columns(len(EXAMPLES))
    for i, e in enumerate(EXAMPLES):
        if ex[i].button(e if len(e) < 34 else e[:31] + "…", key=f"p3_ex_{i}", use_container_width=True):
            st.session_state["p3_question"] = e

    with st.form("p3_form"):
        question = st.text_area("Your question", key="p3_question", height=80,
                                placeholder="e.g. Is Ibuprofen from Sunrise sold at CityCare safe?")
        with st.expander("Optional: structured details"):
            c1, c2, c3 = st.columns(3)
            f_item = c1.text_input("Item code", key="p3_item")
            f_batch = c1.text_input("Batch number", key="p3_batch", placeholder="e.g. SUN-MED005-2603")
            f_med = c2.text_input("Medicine name", key="p3_med")
            f_mfr = c2.text_input("Manufacturer", key="p3_mfr")
            f_shop = c3.text_input("Shop", key="p3_shop")
            f_dist = c3.text_input("Distributor", key="p3_dist")
        has_key = bool(os.environ.get("ANTHROPIC_API_KEY"))
        use_llm = st.checkbox("Write the answer with AI", value=has_key, disabled=not has_key,
                              help=None if has_key else "Set ANTHROPIC_API_KEY before starting Streamlit to enable.")
        go = st.form_submit_button("🧠 ASK", type="primary")

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
                st.error(f"❌ Phase 3 query failed: {e}")

    r = st.session_state.get("p3_result")
    if r is not None:
        st.divider()
        _show_result(r, "ask")

    with st.expander("🗺️ Source schemas: tables and FK → PK links, read live from each machine"):
        try:
            conn = get_connection()
            try:
                tables = pd.read_sql("SELECT * FROM p3_source_tables()", conn)
                edges = pd.read_sql("SELECT * FROM p3_source_schemas()", conn)
            finally:
                conn.close()
            st.dataframe(tables.pivot_table(index="source_id", values="table_name", aggfunc="count")
                         .rename(columns={"table_name": "tables"}), use_container_width=True)
            dot = ['digraph S { rankdir=LR; node [shape=box, style="rounded,filled", fillcolor="#f8fafc", fontname="Helvetica"];']
            for src, part in tables.groupby("source_id"):
                dot.append(f'subgraph cluster_{src} {{ label="{src}"; style=rounded;')
                for t in part.itertuples():
                    fill = {"hub": "#fde68a", "detail": "#fecaca", "link": "#e5e7eb"}.get(t.role, "#dbeafe")
                    dot.append(f'"{src}.{t.table_name}" [label="{t.table_name}", fillcolor="{fill}"];')
                dot.append("}")
            for e in edges.itertuples():
                dot.append(f'"{e.source_id}.{e.child_table}" -> "{e.source_id}.{e.parent_table}" '
                           f'[label="{e.child_column}", fontsize=9];')
            dot.append("}")
            st.graphviz_chart("\n".join(dot))
            st.caption("Arrows point from the referencing table (FK) to the referenced one (PK). "
                       "Yellow = hub, red = detail with free text, grey = link table.")
        except Exception as e:
            st.error(f"❌ Could not read the source schemas: {e}")


# ---------------------------------------------------------------------
# panel inside Verify
# ---------------------------------------------------------------------
def render_verify_context(get_connection, item_code, pack):
    st.markdown("### 🌐 Context from all databases and related documents")
    fields = {"item_code": item_code,
              "medicine_name": (pack or {}).get("name"),
              "manufacturer_name": (pack or {}).get("company"),
              "vendor_name": (pack or {}).get("shop"),
              "distributor_name": (pack or {}).get("distributor")}
    key = json.dumps(fields, sort_keys=True)
    if st.button("🌐 Find context and documents for this item", key=f"p3_verify_{item_code}"):
        try:
            with st.spinner("Asking the three databases and searching the documents..."):
                st.session_state["p3_verify"] = (key, _run(get_connection, "", fields,
                                                            bool(os.environ.get("ANTHROPIC_API_KEY"))))
        except Exception as e:
            st.error(f"❌ Phase 3 search failed: {e}")
    cached = st.session_state.get("p3_verify")
    if cached and cached[0] == key:
        _show_result(cached[1], "verify")
    else:
        st.caption("Batch, QC results, transport logs, complaints and outside documents for this item.")


# ---------------------------------------------------------------------
# tab: prompt, generated code, modified code (rubric item 4)
# ---------------------------------------------------------------------
CODE_FILES = [
    ("Context engine (every source)", "sources/asli_ctx_core.sql"),
    ("manufacturer_db new tables", "sources/manufacturer_07_tables.sql"),
    ("distributor_db new tables", "sources/distributor_07_tables.sql"),
    ("vendor_db new tables", "sources/vendor_07_tables.sql"),
    ("Mediator: federated context", "mediator/mediator_07_federated_context.sql"),
    ("Mediator: documents + hybrid search", "mediator/mediator_08_documents.sql"),
    ("Orchestration (Python)", "app/asli_phase3.py"),
    ("Embeddings (Python)", "app/asli_semantic.py"),
    ("AI answer (Python)", "app/asli_llm.py"),
    ("Phase 3 GUI views (Python)", "app/gui_phase3.py"),
]


def render_code_tab():
    st.subheader("🧾 Prompt, generated code and our modifications")
    prompt_file = PHASE3_DIR / "prompts" / "PROMPT_phase3.md"
    with st.expander("📜 The prompt we gave the AI", expanded=False):
        st.markdown(prompt_file.read_text(encoding="utf-8") if prompt_file.exists() else "_prompts/PROMPT_phase3.md not found_")

    label = st.selectbox("File", [l for l, _ in CODE_FILES])
    rel = dict(CODE_FILES)[label]
    gen = PHASE3_DIR / "generated" / rel
    cur = PHASE3_DIR / rel
    if not gen.exists() or not cur.exists():
        st.warning(f"Missing {gen if not gen.exists() else cur}.")
        return
    a = gen.read_text(encoding="utf-8").splitlines()
    b = cur.read_text(encoding="utf-8").splitlines()
    diff = list(difflib.unified_diff(a, b, fromfile=f"generated/{rel}", tofile=rel, lineterm="", n=2))
    added = sum(1 for l in diff if l.startswith("+") and not l.startswith("+++"))
    removed = sum(1 for l in diff if l.startswith("-") and not l.startswith("---"))
    c1, c2, c3 = st.columns(3)
    c1.metric("Generated lines", len(a))
    c2.metric("Lines we added", added)
    c3.metric("Lines we removed", removed)
    view = st.radio("Show", ["Changes (diff)", "Generated code", "Our final code"], horizontal=True)
    lang = "sql" if rel.endswith(".sql") else "python"
    if view == "Changes (diff)":
        st.code("\n".join(diff) if diff else "No changes yet: the file is exactly as generated.", language="diff")
    elif view == "Generated code":
        st.code("\n".join(a), language=lang)
    else:
        st.code("\n".join(b), language=lang)
    notes = PHASE3_DIR / "prompts" / "MODIFICATIONS.md"
    if notes.exists():
        with st.expander("✍️ Why we changed it"):
            st.markdown(notes.read_text(encoding="utf-8"))
