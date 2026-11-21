"""
Asli-or-Nakli · Phase 3 · the written answer.

With an API key (environment variable ANTHROPIC_API_KEY, package `anthropic`)
a Claude model writes a short answer from the federated context, the risk signals
and the documents, citing each fact as [C3] (context row), [S2] (signal) or
[D1] (document). Without a key, a template answer is built from the same
evidence, so the GUI always works.

The model only sees what the mediator found; it is told not to add facts.
"""

from __future__ import annotations

import os

DEFAULT_MODEL = os.environ.get("ASLI_LLM_MODEL", "claude-sonnet-5-5")

SYSTEM_PROMPT = """You are the analyst of a medicine-authenticity system that integrates a manufacturer,
a distributor and a vendor database with outside documents (regulator alerts, recalls, inspection
reports, news). Answer the user's question using ONLY the evidence provided.

Rules:
- Start with one line: "Assessment: <HIGH RISK | CAUTION | NO RED FLAGS FOUND> — <one-sentence reason>".
- Then at most 6 short bullet points, most important first. Cite every fact with its tag: [C#] context
  row, [S#] risk signal, [D#] document. Never state a fact without a tag.
- Documents marked SYNTHETIC are fictional demo data; say "(demo document)" when you rely on one.
- Distinguish a quality problem of a genuine batch (substandard) from signs of a counterfeit pack, and say
  which one applies. Severity-1 signals are about OTHER batches or shipments: never blame this item for them.
- End with one line "Next step:" giving one concrete action for the buyer or pharmacist.
- If the evidence does not answer the question, say so plainly. Do not guess."""


def _evidence_text(question, assessment, signals, context, docs) -> str:
    lines = [f"QUESTION: {question}", f"RULE-BASED ASSESSMENT: {assessment['level']} — {assessment['headline']}",
             "PROBLEM TYPES: " + (", ".join(assessment.get("categories") or []) or "none"), ""]
    lines.append("RISK SIGNALS:")
    for i, s in enumerate(signals, 1):
        lines.append(f"[S{i}] severity {s['severity']} (1 = context only, not about this item) · "
                     f"{s['source']}.{s['table']} · {s['message']}")
    lines.append("")
    lines.append("CONTEXT ROWS (from the three databases, most relevant first):")
    for i, c in enumerate(context, 1):
        lines.append(f"[C{i}] {c['source']}.{c['table']} (relevance {c['relevance']}, path {c['path']}): {c['summary']}")
    lines.append("")
    lines.append("DOCUMENTS:")
    for i, d in enumerate(docs, 1):
        lines.append(f"[D{i}] {d['origin']} {d['doc_type']} · {d['issuer']} · {d['published_on']} · {d['title']}\n"
                     f"     {d['body'][:900]}")
    return "\n".join(lines)


def summarize(question, assessment, signals, context, docs, model: str | None = None):
    """Returns (text, how) where how is 'llm:<model>' or 'template'."""
    key = os.environ.get("ANTHROPIC_API_KEY")
    if key:
        try:
            import anthropic
            client = anthropic.Anthropic(api_key=key)
            msg = client.messages.create(
                model=model or DEFAULT_MODEL,
                max_tokens=700,
                system=SYSTEM_PROMPT,
                messages=[{"role": "user", "content": _evidence_text(question, assessment, signals, context, docs)}],
            )
            text = "".join(b.text for b in msg.content if getattr(b, "type", "") == "text").strip()
            if text:
                return text, f"llm:{model or DEFAULT_MODEL}"
        except Exception as e:  # network, quota, wrong model name ... fall back, never crash
            return _template(question, assessment, signals, context, docs) + f"\n\n_(AI summary unavailable: {e})_", "template"
    return _template(question, assessment, signals, context, docs), "template"


def _template(question, assessment, signals, context, docs) -> str:
    out = [f"**Assessment: {assessment['level']}** — {assessment['headline']}", ""]
    if assessment.get("categories"):
        out.insert(1, "**Problem type:** " + " · ".join(assessment["categories"]))
    shown = [(i, s) for i, s in enumerate(signals, 1) if s["severity"] >= 2][:6]
    for i, s in shown:
        out.append(f"- {s['message']} [S{i}]")
    if not shown:   # no signal: still point to the closest documents
        for i, d in [(i, d) for i, d in enumerate(docs, 1) if d.get("entity_hits")][:3]:
            tag = " (demo document)" if d["origin"] == "SYNTHETIC" else ""
            out.append(f"- Related document: *{d['title']}*{tag} [D{i}]")
    if len(out) == 2:
        out.append("- No risk signal was found in the three databases or the documents for this query.")
    out.append("")
    out.append("**Next step:** " + assessment["next_step"])
    return "\n".join(out)
