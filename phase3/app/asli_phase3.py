"""
Asli-or-Nakli · Phase 3 · orchestration of one query.

    result = ask(conn, "Is Ibuprofen from Sunrise sold at CityCare safe?")
    result = ask(conn, "", fields={"item_code": "ITEM000041", "vendor_name": "CityCare Medical Store"})

1. p3_run (mediator, SQL)       parse -> federated discovery on the 3 machines (dblink, 2 rounds)
2. item checks (Phase 1 + 2)    every typed item code is matched (search_by_pack) and verified
                                (verify_item): unknown code, cloned code, unapproved, expired,
                                distributor mismatch ... and its own batch / shipment is found
3. p3_context_terms             the query context as weighted search terms
4. embedding                    query + top context terms (same model as the documents)
5. p3_search_documents          hybrid search over the unstructured documents
6. signals                      rules on the context (SQL) + item checks + document rules,
                                limited to the item's OWN batch / shipment / stock record
7. assessment + written answer  one combined level and category; optional LLM summary
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass, field
from datetime import date

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
OLD_DOCUMENT_DAYS = 730          # older documents count one severity level less

# A document counts against a medicine only if a sentence that names the medicine
# also reports a problem. "Telmisartan 40mg: of standard quality" or "out of stock"
# is information, not a warning.
PROBLEM_WORDS = re.compile(
    r"not of standard quality|\bnsq\b|substandard|spurious|counterfeit|fake|falsified|"
    r"recall|quarantin|fail|contaminat|impurit|excursion|seal (?:was |found )?broken|"
    r"did not relieve|no relief|crumbly|sticky|softened|leaked|altered|re-?sealed|"
    r"seized|unregistered|does not exist|not valid|expired|lapsed|suspend|adulterat|misbranded",
    re.I)


REAL_DOC_SLOTS = 2               # of the k documents shown, keep up to 2 for real outside sources


def _pick_documents(pool: pd.DataFrame, k: int) -> pd.DataFrame:
    """Top-k by score, but keep up to REAL_DOC_SLOTS real (non-demo) documents that
    matched: demo documents name our own shops and batches, so they always score
    higher, and real regulator alerts would otherwise never be shown."""
    if pool.empty or len(pool) <= k:
        return pool.reset_index(drop=True)
    top = pool.head(k)
    real_in_top = int((top["origin"] == "REAL").sum())
    need = max(0, REAL_DOC_SLOTS - real_in_top)
    extra = pool.iloc[k:][pool.iloc[k:]["origin"] == "REAL"].head(need)
    if extra.empty:
        return top.reset_index(drop=True)
    keep = pd.concat([top.head(k - len(extra)), extra])
    return keep.sort_values("score", ascending=False, kind="stable").reset_index(drop=True)


def _problem_mention(text: str, medicines: set) -> bool:
    """True if some sentence names one of the medicines and reports a problem."""
    for sentence in re.split(r"(?<=[.!?;])\s+|\n+", text):
        s = sentence.lower()
        if any(m in s for m in medicines) and PROBLEM_WORDS.search(s):
            return True
    return False

# signal rule -> category of problem (one combined verdict, H1 of the review)
CATEGORY = {
    "UNKNOWN_CODE": "COUNTERFEIT", "CLONED_CODE": "COUNTERFEIT", "PACK_MISMATCH": "COUNTERFEIT",
    "BATCH_MISMATCH": "COUNTERFEIT",
    "UNAPPROVED": "UNAPPROVED", "EXPIRED": "EXPIRED",
    "DISTRIBUTOR_MISMATCH": "SUPPLY CHAIN", "SUPPLY_GAP": "SUPPLY CHAIN", "AMBIGUOUS_CODE": "SUPPLY CHAIN",
    "WRONG_CODE": "SUPPLY CHAIN", "CODE_CORRECTED": "CHECK THE CODE", "CODE_NOT_FOUND": "CHECK THE CODE", "ITEM_CHECK_UNAVAILABLE": "CHECK THE CODE",
    "QC_FAIL": "SUBSTANDARD BATCH", "BATCH_STATUS": "SUBSTANDARD BATCH", "GMP_EXPIRED": "SUBSTANDARD BATCH",
    "TEMP_EXCURSION": "TRANSPORT DAMAGE", "TRANSPORT_NOTE": "TRANSPORT DAMAGE",
    "COMPLAINT": "CUSTOMER COMPLAINTS", "DOCUMENT": "OUTSIDE REPORTS",
}
CATEGORY_ORDER = ["COUNTERFEIT", "UNAPPROVED", "EXPIRED", "SUBSTANDARD BATCH", "TRANSPORT DAMAGE",
                  "SUPPLY CHAIN", "CHECK THE CODE", "OUTSIDE REPORTS", "CUSTOMER COMPLAINTS"]


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
    items: list = field(default_factory=list)       # item checks (Phase 1 + 2) per typed code
    timings: dict = field(default_factory=dict)


def _df(conn, sql, params=None):
    cur = conn.cursor()
    cur.execute(sql, params)
    cols = [c[0] for c in cur.description]
    rows = cur.fetchall()
    cur.close()
    return pd.DataFrame(rows, columns=cols)


def _row(r):
    return r if isinstance(r, dict) else json.loads(r)


def summarize_row(row_data) -> str:
    r = _row(row_data)
    parts = [f"{k}={r[k]}" for k in SUMMARY_KEYS if k in r and r[k] not in (None, "")]
    text = ", ".join(parts) or ", ".join(f"{k}={v}" for k, v in list(r.items())[:6])
    return text if len(text) <= 400 else text[:397] + "..."


def _norm_batch(b) -> str:
    """SUN MED005 2511 = SUN-MED005-2511 = sun-med005-2511"""
    return re.sub(r"[^A-Z0-9]", "", str(b or "").upper())


def _fold(code: str) -> str:
    """Same idea as asli.fold, enough for comparing codes found in context rows."""
    c = re.sub(r"[\s._-]", "", (code or "").upper())
    tr = str.maketrans({"O": "0", "I": "1", "L": "1", "S": "5", "B": "8", "Z": "2", "G": "6"})
    m = re.match(r"^(ITEM|ITM|1TEM|LTEM|ITRM)(.*)$", c)
    if not m:
        return c
    digits = m.group(2).translate(tr)
    return "ITEM" + (digits.zfill(6) if digits.isdigit() else digits)


# ---------------------------------------------------------------------
# Phase 1 + 2 checks for every typed item code
# ---------------------------------------------------------------------
def check_items(conn, seeds: list, fields: dict, context: pd.DataFrame, manufacturer_down: bool = False) -> list:
    codes = []
    for s in seeds:
        if s.get("kind") == "item_code" and s.get("value") not in codes:
            codes.append(s["value"])
    out = []
    for code in codes[:3]:
        info = {"code": code, "verdict": None, "item": None, "risk": None, "reasons": [], "signals": [],
                "batch": None, "shipment_id": None, "vendor_inventory_ids": set(), "corrected": False}
        if manufacturer_down:
            # without the manufacturer nobody can say whether a code was made: never call it counterfeit
            info["signals"].append(("ITEM_CHECK_UNAVAILABLE", 2,
                                    f"The item check for {code} is unavailable: the manufacturer machine did not "
                                    "answer. The answer below uses the distributor and the vendor only."))
            out.append(info)
            continue
        try:
            _check_one(conn, code, info, fields, context)
        except Exception as e:      # e.g. the manufacturer machine is offline
            try:
                conn.rollback()
            except Exception:
                pass
            info["signals"].append(("ITEM_CHECK_UNAVAILABLE", 2,
                                    f"The item check for {code} is unavailable (a source machine did not answer: "
                                    f"{str(e).splitlines()[0][:120]}). The answer below uses the other sources."))
        out.append(info)
    return out


def _check_one(conn, code, info, fields, context):
    if True:
        cand = _df(conn, "SELECT * FROM search_by_pack(%s, %s, %s, %s, %s, 5, %s, %s)",
                   (code, fields.get("medicine_name"), fields.get("manufacturer_name"), fields.get("mfg"),
                    fields.get("expiry"), fields.get("vendor_name"), fields.get("distributor_name")))
        sig = info["signals"]
        if cand.empty:
            info["verdict"] = "NO MATCH"
            held = []
            if not context.empty:
                for r in context.itertuples():
                    d = _row(r.row_data)
                    for k in ("item_identifier", "product_code"):
                        if k in d and _fold(d[k]) == _fold(code):
                            held.append({"vendor": "a shop's stock (vendor_db)",
                                         "distributor": "a distributor's stock (distributor_db)"}.get(r.source_id, r.source_id))
            if held:   # a shop or distributor stocks a code nobody made: counterfeit sign
                sig.append(("UNKNOWN_CODE", 3, f"No manufacturer ever made a code like {code} — yet it is held by "
                                               f"{', '.join(sorted(set(held)))}. A code that only exists at a shop "
                                               "or distributor is a counterfeit sign."))
            else:      # probably mistyped: ask the buyer to check the pack
                sig.append(("CODE_NOT_FOUND", 2, f"No item with the code {code}. Check the code printed on the pack."))
            return
        top = cand.iloc[0]
        verdict, decided = top["verdict"], top["decided_item"] if pd.notna(top["decided_item"]) else None
        info["verdict"] = verdict
        if verdict == "REVIEW":
            options = ", ".join(cand["item_code"].head(3))
            sig.append(("AMBIGUOUS_CODE", 2, f"{code} fits several real items ({options}); "
                                             "add the medicine name or batch to tell them apart."))
        elif verdict == "POSSIBLE CLONED CODE":
            sig.append(("CLONED_CODE", 3, f"{code} is a real code, but the pack details contradict the "
                                          "manufacturer's record of it: a genuine code copied onto another pack."))
            decided = cand.loc[cand["code_edit_cost"].astype(float) == 0, "item_code"].head(1).tolist()
            decided = decided[0] if decided else None
        elif verdict == "CONTEXT ERROR":
            sig.append(("PACK_MISMATCH", 3, f"{code} exists, but the pack's details (expiry / maker) differ from "
                                            "the manufacturer's record: possible tampering."))
        elif verdict == "WRONG CODE":
            sig.append(("WRONG_CODE", 2, f"{code} belongs to another medicine; the details fit {decided}."))
        elif verdict == "NO MATCH":
            sig.append(("UNKNOWN_CODE", 3, f"No real item resembles {code}."))
        info["item"] = decided
        # the typed code was swapped for a DIFFERENT real code (not just cleaned of noise):
        # say so, unless the medicine name or the batch on the pack confirms the item
        if decided and _fold(decided) != _fold(code) and verdict in ("MATCH", "WRONG CODE"):
            name_ok = bool(fields.get("medicine_name")) and float(top.get("name_score") or 0) >= 0.8
            info["corrected"] = not name_ok
            if not name_ok and verdict == "MATCH":
                sig.append(("CODE_CORRECTED", 2, f"You typed {code}; the closest real item is {decided}. "
                                                 "Check the code on the pack (add the medicine name or batch to confirm)."))
        if decided:
            ver = _df(conn, "SELECT * FROM verify_item(%s) LIMIT 1", (decided,))
            if not ver.empty:
                v = ver.iloc[0]
                info["risk"] = v["risk_status"]
                reasons = [x.strip() for x in str(v["suspicion_reason"] or "").split("|") if x.strip()]
                info["reasons"] = reasons
                for rsn in reasons:
                    if "UNAPPROVED" in rsn:
                        sig.append(("UNAPPROVED", 3, f"{decided} is not approved by the manufacturer (NAKALI)."))
                    elif "EXPIRED" in rsn:
                        sig.append(("EXPIRED", 3, f"{decided} expired on {v['expiry_date']}."))
                    elif rsn == "DISTRIBUTOR ID MISMATCH":
                        sig.append(("DISTRIBUTOR_MISMATCH", 3,
                                    f"{decided}: the distributor says distributor {v['distributor_id']}, the shop "
                                    f"says {v['vendor_distributor_id']}."))
                    elif "NOT FOUND" in rsn:
                        sig.append(("SUPPLY_GAP", 2, f"{decided}: {rsn.lower()}."))
                info["vendor_name"] = v["vendor_name"]
                info["sale_date"] = v["sale_date"]
            b = _df(conn, "SELECT * FROM p3_item_batch(%s)", (decided,))
            if not b.empty:
                info["batch"] = b.iloc[0].to_dict()
                pack_batch = (fields.get("batch_no") or "").strip().upper()
                if pack_batch and _norm_batch(pack_batch) == _norm_batch(info["batch"]["batch_no"]):
                    info["corrected"] = False          # the batch confirms the item
                if pack_batch and _norm_batch(pack_batch) != _norm_batch(info["batch"]["batch_no"]):
                    sig.append(("BATCH_MISMATCH", 3,
                                f"The pack says batch {pack_batch}, but {decided} belongs to batch "
                                f"{info['batch']['batch_no']}: the code or the batch print is not genuine."))
            # the item's own shipment and shop stock records, from the federated context
            if not context.empty:
                for r in context.itertuples():
                    d = _row(r.row_data)
                    if r.table_name == "shipment_lines" and _fold(d.get("product_code", "")) == _fold(decided):
                        info["shipment_id"] = d.get("shipment_id")
                    if r.table_name == "vendor_inventory" and _fold(d.get("item_identifier", "")) == _fold(decided):
                        info["vendor_inventory_ids"].add(d.get("inventory_id"))


ITEM_SPECIFIC_TABLES = {"qc_reports", "production_batches", "plants", "temperature_logs", "customer_complaints"}


def _own_row_one(t: str, d: dict, item: dict) -> bool | None:
    """Does this batch / plant / shipment / complaint row belong to ONE resolved item?
    When the item's own batch / shipment / stock record is unknown, the row is NOT counted
    as the item's (False): an unknown link must never blame the item for another batch."""
    b = item.get("batch") or {}
    if t in ("qc_reports", "production_batches"):
        return bool(b) and d.get("batch_id") == b.get("batch_id")
    if t == "plants":
        return bool(b) and d.get("plant_id") == b.get("plant_id")
    if t == "temperature_logs":
        return item.get("shipment_id") is not None and d.get("shipment_id") == item["shipment_id"]
    if t == "customer_complaints":
        return d.get("inventory_id") is not None and d.get("inventory_id") in item["vendor_inventory_ids"]
    return None


def _own_row(sig_row: dict, items: list) -> bool | None:
    """True if the row belongs to ANY item asked about, False if it belongs to none of them,
    None if it is not item-specific or no item was resolved."""
    resolved = [i for i in items if i.get("item")]
    if not resolved or sig_row["table"] not in ITEM_SPECIFIC_TABLES:
        return None
    results = [_own_row_one(sig_row["table"], sig_row["row"], i) for i in resolved]
    if any(r is True for r in results):
        return True
    if any(r is False for r in results):
        return False
    return None


# The embedding model is loaded once per process, not once per query: importing
# scikit-learn / loading the model takes several seconds (much more on /mnt/c in WSL).
_EMBEDDERS: dict = {}


def _embedder(name):
    if name and _EMBEDDERS.get(name) is None:      # a model that failed to load is tried again next time
        _EMBEDDERS[name] = Embedder.by_name(name)
    return _EMBEDDERS.get(name)


def warm_up(conn) -> None:
    """Load the embedding model before the first question (called once by the GUI)."""
    try:
        _embedder(_df(conn, "SELECT max(embedding_model) AS m FROM p3_documents").iloc[0]["m"])
    except Exception:
        pass


def ask(conn, question: str, fields: dict | None = None, k_docs: int = 8, use_llm: bool = True) -> Phase3Result:
    t = {}
    fields = {k: v for k, v in (fields or {}).items() if v}
    if fields.get("batch_no"):   # "SUN MED005 2511" -> "SUN-MED005-2511" (the stored form)
        fields["batch_no"] = re.sub(r"[^A-Z0-9]+", "-", str(fields["batch_no"]).upper()).strip("-")
    seed_fields = {k: fields[k] for k in ("item_code", "batch_no", "medicine_name", "manufacturer_name",
                                          "vendor_name", "distributor_name") if k in fields}
    cur = conn.cursor()

    # 1. federated discovery (one SQL call; the mediator talks to the three machines)
    t0 = time.perf_counter()
    cur.execute("SELECT p3_run(%s, %s::jsonb)", (question or "", json.dumps(seed_fields)))
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

    # 2. Phase 1 + 2 checks of every typed item code
    t0 = time.perf_counter()
    all_ctx = _df(conn, "SELECT source_id, table_name, row_key, row_data FROM p3_context WHERE query_id = %s", (qid,))
    mfr_down = bool(_df(conn, """SELECT 1 FROM p3_source_calls c JOIN asli_sources s USING (source_id)
                                 WHERE c.query_id = %s AND s.kind = 'MANUFACTURER' AND c.round = 1
                                   AND c.status IN ('ERROR', 'TIMEOUT')""", (qid,)).shape[0])
    items = check_items(conn, seeds, fields, all_ctx, manufacturer_down=mfr_down)
    t["item checks"] = time.perf_counter() - t0

    # 3-5. context -> terms -> hybrid document search
    t0 = time.perf_counter()
    terms = _df(conn, "SELECT * FROM p3_context_terms(%s)", (qid,))
    model_name = _df(conn, "SELECT max(embedding_model) AS m FROM p3_documents").iloc[0]["m"]
    embedder = _embedder(model_name)
    qvec = None
    if embedder is not None:
        text = " ".join([question or ""] + list(terms["term"].head(10)) + [str(v) for v in fields.values()])
        qvec = embedder.embed([text])[0]
    t["embedding"] = time.perf_counter() - t0
    t0 = time.perf_counter()
    pool = _df(conn, "SELECT * FROM p3_search_documents(%s, %s, %s::real[], %s)",
               (qid, question or " ".join(map(str, fields.values())), qvec, k_docs * 3))
    documents = _pick_documents(pool, k_docs)
    if not documents.empty:
        bodies = _df(conn, "SELECT doc_id, body FROM p3_documents WHERE doc_id = ANY(%s)",
                     (documents["doc_id"].astype(int).tolist(),))
        documents = documents.merge(bodies, on="doc_id", how="left")
    else:
        documents["body"] = []
    t["document search"] = time.perf_counter() - t0

    # 6. signals
    signals = []
    for it in items:
        for rule, sev, msg in it["signals"]:
            signals.append({"rule": rule, "severity": sev, "source": "verification", "table": "Phase 1/2",
                            "relevance": 1.0, "message": msg, "path": f"search_by_pack / verify_item({it['code']})",
                            "items": [it["item"] or it["code"]]})

    rows = {(r.source_id, r.table_name, r.row_key): _row(r.row_data) for r in all_ctx.itertuples()}
    sig = _df(conn, "SELECT * FROM p3_signals(%s) ORDER BY severity DESC, relevance DESC", (qid,))
    for r in sig.itertuples():
        s = {"rule": r.rule_id, "severity": int(r.severity), "source": r.source_id, "table": r.table_name,
             "relevance": float(r.relevance), "message": r.message, "path": r.path,
             "row": rows.get((r.source_id, r.table_name, r.row_key), {})}
        own = _own_row(s, items)
        s["items"] = [i["item"] for i in items if i.get("item")
                      and _own_row_one(s["table"], s["row"], i) is True] if own else []
        if own is False:   # another batch / shipment / record of the same medicine: context only
            s["severity"] = 1
            s["message"] = "(not this item's batch/shipment) " + s["message"]
        signals.append(s)

    # documents: a product + batch/item match is evidence about THIS case;
    # a document that only names the same company is information only
    term_kind = dict(zip(terms["term"], terms["term_kind"])) if not terms.empty else {}
    medicines = {str(x).split()[0].lower() for x, k in term_kind.items() if k == "medicine" and str(x).split()}
    # if the question names a medicine, only documents about THAT medicine count
    # ("paracetamol from ABC Pharma" is not about ABC Pharma's cetirizine)
    asked_text = " ".join([question or ""] + [str(v) for v in fields.values()]).lower()
    asked_meds = {m for m in medicines if len(m) >= 4 and m in asked_text}
    if asked_meds:
        medicines = asked_meds
    own_batches = {_norm_batch(i["batch"]["batch_no"]) for i in items if i.get("batch")}
    asked_codes = {_fold(i["item"]) for i in items if i.get("item")} | {_fold(i["code"]) for i in items}
    for d in documents.itertuples():
        hits = list(d.entity_hits or [])
        base = DOC_RISK_TYPES.get(d.doc_type)
        if not base:
            continue
        text = f"{d.title} {d.body or ''}".lower()
        strong = [h for h in hits if term_kind.get(h) in STRONG_ENTITIES]
        if items:   # only the asked items' own batch / code counts as a strong match
            strong = [h for h in strong
                      if (term_kind.get(h) == "batch_no" and _norm_batch(h) in own_batches)
                      or (term_kind.get(h) == "item_code" and _fold(h) in asked_codes)]
        medicine_match = any(m in text for m in medicines)
        item = next((i for i in items if i.get("item")), None)
        if item is not None:
            # a specific item: only its own batch / code, or its own shop, is about this case
            own_shop = str(item.get("vendor_name") or "").lower()
            shop_hit = bool(own_shop) and any(term_kind.get(h) == "shop" and h.lower() == own_shop for h in hits)
            if strong and medicine_match:
                sev = base
            elif shop_hit and medicine_match:
                sev = min(base, 2)
            else:
                sev = 1
        elif strong and medicine_match:
            sev = base
        elif medicine_match and hits and float(d.score) >= 0.5 \
                and _problem_mention(f"{d.title}. {d.body or ''}", medicines):
            sev = min(base, 2)
        else:
            sev = 1
        if d.published_on and (date.today() - d.published_on).days > OLD_DOCUMENT_DAYS:
            sev = max(1, sev - 1)
        owners = [i["item"] for i in items if i.get("item") and (
                      _fold(i["item"]) in {_fold(h) for h in strong if term_kind.get(h) == "item_code"}
                      or (i.get("batch") and _norm_batch(i["batch"]["batch_no"]) in
                          {_norm_batch(h) for h in strong if term_kind.get(h) == "batch_no"}))]
        signals.append({"rule": "DOCUMENT", "severity": sev, "source": "documents", "table": d.doc_type, "items": owners,
                        "relevance": float(d.score),
                        "message": f"{d.doc_type.replace('_', ' ').title()} mentions {', '.join(hits) or 'related terms'}: "
                                   f"\"{d.title}\" ({d.issuer}, {d.published_on})"
                                   + (" — demo document" if d.origin == "SYNTHETIC" else ""),
                        "path": "documents"})

    # the same finding reached through several rows (one note on many shipments, one
    # excursion on several days) is shown once, with its highest severity / relevance
    best = {}
    for s in signals:
        key = (s["rule"], re.sub(r"\d{4}-\d{2}-\d{2}", "", s["message"]))
        if key not in best or (s["severity"], s["relevance"]) > (best[key]["severity"], best[key]["relevance"]):
            best[key] = s
    signals = sorted(best.values(), key=lambda s: (-s["severity"], -s["relevance"]))
    for s in signals:
        s.pop("row", None)

    assessment = assess(signals, context, items)

    # 7. written answer (customer columns are already masked at the source)
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
                        assessment, answer, how, items, t)


def _short(text: str, n: int = 110) -> str:
    text = text.split(": \"")[0] if ": \"" in text else text
    return text if len(text) <= n else text[:n].rsplit(" ", 1)[0] + " …"


SIGNAL_MIN_RELEVANCE = 0.15   # a signal on a barely related row does not decide the level


def assess(signals: list, context: pd.DataFrame, items: list | None = None) -> dict:
    items = items or []
    counted = [s for s in signals if s["severity"] >= 2 and s["relevance"] >= SIGNAL_MIN_RELEVANCE]
    serious = [s for s in counted if s["severity"] >= 3]
    cats = sorted({CATEGORY.get(s["rule"], "OTHER") for s in counted},
                  key=lambda c: CATEGORY_ORDER.index(c) if c in CATEGORY_ORDER else 99)
    genuine = any(i.get("risk") == "GENUINE" and not i.get("corrected") for i in items)
    resolved_items = [i["item"] for i in items if i.get("item")]
    if len(resolved_items) > 1:
        # several items asked about: say which problem belongs to which item
        parts = []
        for it in resolved_items:
            mine = sorted({CATEGORY.get(s["rule"], "OTHER") for s in counted if it in (s.get("items") or [])},
                          key=lambda c: CATEGORY_ORDER.index(c) if c in CATEGORY_ORDER else 99)
            parts.append(f"{it}: {' + '.join(mine)}" if mine else f"{it}: no issue")
        level = "HIGH RISK" if serious else ("CAUTION" if counted else "NO RED FLAGS FOUND")
        strongest = (serious or counted)
        return {"level": level, "categories": cats,
                "headline": "; ".join(parts) + (f". Strongest: {_short(strongest[0]['message'])}" if strongest else "."),
                "next_step": ("Do not use the affected pack; return it to the shop and report it." if serious else
                              "Compare each pack with the manufacturer's record (Verify page) and keep the bills."
                              if counted else "Keep the bills; nothing else to do.")}
    resolved = ", ".join(sorted({i["item"] for i in items if i.get("item") and not i.get("corrected")}))

    if context.empty and not items:
        return {"level": "NOT FOUND", "categories": [], "headline": "No source database recognised anything in this query.",
                "next_step": "Check the item code or name, or verify the pack on the Verify tab."}
    if serious:
        lead = cats[0] if cats else "RISK"
        if lead == "COUNTERFEIT":
            head = "Signs of a counterfeit pack"
        elif lead in ("UNAPPROVED", "EXPIRED"):
            head = f"The item is {lead.lower()}"
        elif genuine:
            head = f"The code is genuine ({resolved}), but: {' + '.join(cats)}"
        else:
            head = " + ".join(cats)
        return {"level": "HIGH RISK", "categories": cats,
                "headline": f"{head}. Strongest: {_short(serious[0]['message'])}",
                "next_step": "Do not use the pack; return it to the shop, ask for the purchase invoice, "
                             "and report it (Reports tab / national pharmacovigilance helpline)."}
    if counted:
        head = (f"The code is genuine ({resolved}), but: " if genuine else "") + " + ".join(cats)
        return {"level": "CAUTION", "categories": cats,
                "headline": f"{head}. Strongest: {_short(counted[0]['message'])}",
                "next_step": "Compare the pack with the manufacturer's record (Verify tab) and keep the bill."}
    if genuine:
        return {"level": "NO RED FLAGS FOUND", "categories": [],
                "headline": f"{resolved} is GENUINE, and its batch, transport and shop show no issue.",
                "next_step": "Keep the bill; nothing else to do."}
    return {"level": "NO RED FLAGS FOUND", "categories": [],
            "headline": "The three databases and the documents show no quality, transport or complaint issue.",
            "next_step": "Verify the item code on the pack to confirm the supply chain."}
