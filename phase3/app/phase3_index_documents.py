"""
Asli-or-Nakli · Phase 3 · load the unstructured documents into the mediator
and compute their embeddings.

    python phase3_index_documents.py                 # corpus/documents.json
    python phase3_index_documents.py my_docs.json    # any file in the same format

Run it on the GUI machine after mediator_08_documents.sql, and again whenever
documents are added. Existing documents (same doc_key) are updated, never
duplicated. Connection settings come from DB_CONFIG in asli_db.py.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import psycopg2

from asli_db import DB_CONFIG
from asli_semantic import Embedder

DEFAULT_CORPUS = Path(__file__).resolve().parent.parent / "corpus" / "documents.json"

UPSERT = """
INSERT INTO p3_documents (doc_key, doc_type, origin, title, issuer, published_on, url, body)
VALUES (%(doc_key)s, %(doc_type)s, %(origin)s, %(title)s, %(issuer)s, %(published_on)s, %(url)s, %(body)s)
ON CONFLICT (doc_key) DO UPDATE SET
    doc_type = EXCLUDED.doc_type, origin = EXCLUDED.origin, title = EXCLUDED.title,
    issuer = EXCLUDED.issuer, published_on = EXCLUDED.published_on, url = EXCLUDED.url,
    body = EXCLUDED.body, loaded_at = now()
"""


def fill_placeholders(conn, docs: list) -> dict:
    """Demo documents name the demo batch as {{ibuprofen_batch}} etc.; the real batch
    numbers come from each source's asli_ctx.demo_story, so they match every copy."""
    cur = conn.cursor()
    try:
        cur.execute("SELECT key, value FROM p3_demo_story()")
        story = {k: v for k, v in cur.fetchall() if v}
    except Exception as e:
        conn.rollback()
        print(f"Warning: could not read the demo story from the sources ({e}); placeholders stay generic.")
        story = {}
    for d in docs:
        for k in ("title", "body"):
            text = d.get(k) or ""
            for key, value in story.items():
                text = text.replace("{{" + key + "}}", value)
            d[k] = re.sub(r"\{\{[a-z_]+\}\}", "the affected batch", text)
    return story


def main(path: Path) -> None:
    docs = json.loads(path.read_text(encoding="utf-8"))
    required = {"doc_key", "doc_type", "origin", "title", "body"}
    for d in docs:
        missing = required - d.keys()
        if missing:
            raise SystemExit(f"{d.get('doc_key', '?')}: missing {sorted(missing)}")
        for k in ("issuer", "published_on", "url"):
            d.setdefault(k, None)

    conn = psycopg2.connect(**DB_CONFIG)
    try:
        story = fill_placeholders(conn, docs)
        if story:
            print("Demo story from the sources: " + ", ".join(f"{k}={v}" for k, v in sorted(story.items())))
        cur = conn.cursor()
        for d in docs:
            cur.execute(UPSERT, d)

        # embed EVERY document in the table (old ones too) with one model
        cur.execute("SELECT doc_id, title || '. ' || body FROM p3_documents ORDER BY doc_id")
        rows = cur.fetchall()
        embedder = Embedder.for_indexing([t for _, t in rows])
        vectors = embedder.embed([t for _, t in rows])
        for (doc_id, _), vec in zip(rows, vectors):
            cur.execute("UPDATE p3_documents SET embedding = %s::real[], embedding_model = %s WHERE doc_id = %s",
                        (vec, embedder.name, doc_id))
        conn.commit()
        print(f"Loaded {len(docs)} document(s) from {path.name}; "
              f"{len(rows)} embedded with {embedder.name} ({len(vectors[0]) if vectors else 0} dimensions).")
    finally:
        conn.close()


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CORPUS)
