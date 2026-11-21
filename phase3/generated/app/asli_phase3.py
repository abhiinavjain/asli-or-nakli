"""
Asli-or-Nakli · Phase 3 · orchestration of one query.

    result = ask(conn, "Is Ibuprofen from Sunrise sold at CityCare safe?")
    result = ask(conn, "", fields={"item_code": "ITEM000041", "vendor_name": "CityCare Medical Store"})

1. p3_run (mediator, SQL)       parse -> federated discovery on the 3 machines (dblink, 2 rounds)
2. p3_context_terms             the query context as weighted search terms
3. embedding                    query + top context terms (same model as the documents)
4. p3_search_documents          hybrid search over the unstructured documents
5. p3_signals + document rules  risk signals from both
6. assessment + written answer  rule-based level; optional LLM summary that cites the evidence
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass, field

import pandas as pd

from asli_llm import summarize
from asli_semantic import Embedder

# columns worth showing when a context row is summarised in one line
SUMMARY_KEYS = [
    "unique_item_code", "product_code", "item_identifier", "batch_no", "medicine_name", "drug_name",
    "manufacturer_name", "vendor_name", "shop_name", "distributor_name", "plant_name", "city",
    "gmp_valid_until", "release_status", "test_name", "result", "measured_value", "temp_c", "note",
    "complaint_text", "status", "invoice_no", "invoice_date", "shipment_no", "dispatched_on",
    "supply_date", "received_date", "sale_date", "expiry_date", "exp_date", "expiry", "remarks",
]

DOC_RISK_TYPES = {"REGULATOR_ALERT": 3, "RECALL_NOTICE": 3, "INSPECTION_REPORT": 2,
                  "PHARMACOVIGILANCE": 2, "NEWS": 2, "CONSUMER_REVIEW": 1, "ADVISORY": 1}
STRONG_ENTITIES = {"batch_no", "item_code"}


@dataclass
class Phase3Result:
    query_id: int
    question: str
    seeds: list
    calls: pd.DataFrame
    context: pd.DataFrame
    terms: pd.DataFrame
    documents: pd.DataFrame
    signals: list
    assessment: dict
    answer: str
    answer_how: str
    timings: dict = field(default_factory=dict)


def _df(conn, sql, params=None):
    cur = conn.cursor()
    cur.execute(sql, params)
    cols = [c[0] for c in cur.description]
    rows = cur.fetchall()
    cur.close()
    return pd.DataFrame(rows, columns=cols)


def summarize_row(row_data) -> str:
    r = row_data if isinstance(row_data, dict) else json.loads(row_data)
    parts = [f"{k}={r[k]}" for k in SUMMARY_KEYS if k in r and r[k] not in (None, "")]
    text = ", ".join(parts) or ", ".join(f"{k}={v}" for k, v in list(r.items())[:6])
    return text if len(text) <= 400 else text[:397] + "..."


def ask(conn, question: str, fields: dict | None = None, k_docs: int = 8, use_llm: bool = True) -> Phase3Result:
    t = {}
    fields = {k: v for k, v in (fields or {}).items() if v}
    cur = conn.cursor()

    # 1. federated discovery (one SQL call; the mediator talks to the three machines)
    t0 = time.perf_counter()
    cur.execute("SELECT p3_run(%s, %s::jsonb)", (question or "", json.dumps(fields)))
    qid = cur.fetchone()[0]
    conn.commit()
    t["federated discovery"] = time.perf_counter() - t0

    seeds = _df(conn, "SELECT seeds FROM p3_queries WHERE query_id = %s", (qid,)).iloc[0]["seeds"] or []
    calls = _df(conn, """SELECT round, source_id, status, rows_back, elapsed_ms,
                                jsonb_array_length(coalesce(seeds, '[]')) AS seeds_sent, seeds, error
                         FROM p3_source_calls WHERE query_id = %s ORDER BY round, source_id""", (qid,))
    context = _df(conn, "SELECT * FROM p3_top_context(%s)", (qid,))
    if not context.empty:
        context["summary"] = context["row_data"].map(summarize_row)

    # 2-4. context -> terms -> hybrid document search
    t0 = time.perf_counter()
    terms = _df(conn, "SELECT * FROM p3_context_terms(%s)", (qid,))
    model_name = _df(conn, "SELECT max(embedding_model) AS m FROM p3_documents").iloc[0]["m"]
    embedder = Embedder.by_name(model_name)
    qvec = None
    if embedder is not None:
        text = " ".join([question or ""] + list(terms["term"].head(10)) + [str(v) for v in fields.values()])
        qvec = embedder.embed([text])[0]
    documents = _df(conn, "SELECT * FROM p3_search_documents(%s, %s, %s::real[], %s)",
                    (qid, question or " ".join(map(str, fields.values())), qvec, k_docs))
    documents = documents.merge(_df(conn, "SELECT doc_id, body FROM p3_documents"), on="doc_id", how="left")
    t["document search"] = time.perf_counter() - t0

    # 5. risk signals: rules on the context (SQL) + rules on the documents (here)
    sig = _df(conn, "SELECT * FROM p3_signals(%s) ORDER BY severity DESC, relevance DESC", (qid,))
    signals = [{"rule": r.rule_id, "severity": int(r.severity), "source": r.source_id, "table": r.table_name,
                "relevance": float(r.relevance), "message": r.message, "path": r.path} for r in sig.itertuples()]
    term_kind = dict(zip(terms["term"], terms["term_kind"])) if not terms.empty else {}
    for d in documents.itertuples():
        hits = list(d.entity_hits or [])
        strong = [h for h in hits if term_kind.get(h) in STRONG_ENTITIES]
        base = DOC_RISK_TYPES.get(d.doc_type)
        if base and (strong or (hits and base >= 2 and d.score >= 0.5)):
            sev = base if strong else min(base, 2)
            signals.append({"rule": "DOCUMENT", "severity": sev, "source": "documents", "table": d.doc_type,
                            "relevance": float(d.score),
                            "message": f"{d.doc_type.replace('_', ' ').title()} mentions {', '.join(hits)}: "
                                       f"\"{d.title}\" ({d.issuer}, {d.published_on})"
                                       + (" — demo document" if d.origin == "SYNTHETIC" else ""),
                            "path": "documents"})
    # the same finding reached through several rows (e.g. one excursion logged on
    # three shipments) is shown once, with its highest relevance
    best = {}
    for s in signals:
        key = (s["rule"], s["message"])
        if key not in best or s["relevance"] > best[key]["relevance"]:
            best[key] = s
    signals = sorted(best.values(), key=lambda s: (-s["severity"], -s["relevance"]))

    assessment = assess(signals, context)

    # 6. written answer
    t0 = time.perf_counter()
    ctx_list = [{"source": r.source_id, "table": r.table_name, "relevance": float(r.relevance),
                 "path": r.path, "summary": r.summary} for r in context.head(20).itertuples()] if not context.empty else []
    doc_list = [{"origin": d.origin, "doc_type": d.doc_type, "issuer": d.issuer, "published_on": str(d.published_on),
                 "title": d.title, "body": d.body or "", "entity_hits": list(d.entity_hits or [])}
                for d in documents.itertuples()]
    if use_llm:
        answer, how = summarize(question or json.dumps(fields), assessment, signals[:10], ctx_list, doc_list)
    else:
        from asli_llm import _template
        answer, how = _template(question, assessment, signals, ctx_list, doc_list), "template"
    t["answer"] = time.perf_counter() - t0
    cur.close()

    return Phase3Result(qid, question, seeds, calls, context, terms, documents, signals,
                        assessment, answer, how, t)


def _short(text: str, n: int = 110) -> str:
    text = text.split(": \"")[0] if ": \"" in text else text
    return text if len(text) <= n else text[:n].rsplit(" ", 1)[0] + " …"


SIGNAL_MIN_RELEVANCE = 0.15   # a signal on a barely related row does not decide the level


def assess(signals: list, context: pd.DataFrame) -> dict:
    strong = [s for s in signals if s["relevance"] >= SIGNAL_MIN_RELEVANCE]
    serious = [s for s in strong if s["severity"] >= 3]
    warn = [s for s in strong if s["severity"] == 2]
    if context.empty:
        return {"level": "NOT FOUND", "headline": "No source database recognised anything in this query.",
                "next_step": "Check the item code or name, or verify the pack on the Verify tab."}
    if serious:
        return {"level": "HIGH RISK",
                "headline": f"{len(serious)} serious signal(s), the strongest: {_short(serious[0]['message'])}",
                "next_step": "Do not use the pack; return it to the shop, ask for the purchase invoice, "
                             "and report it (Reports tab / national pharmacovigilance helpline)."}
    if warn:
        return {"level": "CAUTION", "headline": f"{len(warn)} warning(s), the strongest: {_short(warn[0]['message'])}",
                "next_step": "Compare the pack with the manufacturer's record (Verify tab) and keep the bill."}
    return {"level": "NO RED FLAGS FOUND",
            "headline": "The three databases and the documents show no quality, transport or complaint issue.",
            "next_step": "Verify the item code on the pack to confirm the supply chain."}
