"""
Asli-or-Nakli · Phase 3 · text embeddings for semantic document search.

Two back-ends, picked automatically:

1. sentence-transformers  ("all-MiniLM-L6-v2", 384 dimensions)
   A pretrained neural model: "tablets did not relieve pain" is close to
   "lack of efficacy" even with no word in common. Used when the package is
   installed:  pip install sentence-transformers  (downloads the model once).

2. LSA  (TF-IDF + truncated SVD, scikit-learn)
   No download. Learned from our own document collection when the documents are
   indexed and saved to models/asli_lsa.joblib. It captures words that occur
   together (amoxicillin ~ capsule ~ dissolution), which is weaker than a neural
   model but needs nothing outside the project.

The model name is stored with every document embedding, so a query is always
embedded with the same model as the documents it is compared with.
"""

from __future__ import annotations

import os
from pathlib import Path

import numpy as np

MODEL_DIR = Path(__file__).resolve().parent / "models"
LSA_PATH = MODEL_DIR / "asli_lsa.joblib"
ST_MODEL = os.environ.get("ASLI_EMBED_MODEL", "all-MiniLM-L6-v2")


def _st_available() -> bool:
    if os.environ.get("ASLI_EMBED_BACKEND", "").lower() == "lsa":
        return False
    try:
        import sentence_transformers  # noqa: F401
        return True
    except Exception:
        return False


class Embedder:
    """embed(texts) -> list of unit-length float vectors."""

    def __init__(self, name: str):
        self.name = name
        self._model = None

    # ---------------- construction ----------------
    @classmethod
    def for_indexing(cls, corpus: list[str]) -> "Embedder":
        """Best available model; LSA is (re)fitted on the corpus and saved."""
        if _st_available():
            return cls(f"st:{ST_MODEL}")
        e = cls("lsa:v1")
        e._fit_lsa(corpus)
        return e

    @classmethod
    def by_name(cls, name: str | None) -> "Embedder | None":
        """The model the documents were indexed with (None if it cannot be loaded)."""
        if not name:
            return None
        e = cls(name)
        try:
            e._load()
            return e
        except Exception:
            return None

    # ---------------- embedding ----------------
    def embed(self, texts: list[str]) -> list[list[float]]:
        self._load()
        if self.name.startswith("st:"):
            vecs = self._model.encode(texts, normalize_embeddings=True)
            return [list(map(float, v)) for v in vecs]
        tfidf, svd = self._model
        x = svd.transform(tfidf.transform(texts))
        norms = np.linalg.norm(x, axis=1, keepdims=True)
        norms[norms == 0] = 1
        return [list(map(float, v)) for v in (x / norms)]

    # ---------------- internals ----------------
    def _load(self):
        if self._model is not None:
            return
        if self.name.startswith("st:"):
            from sentence_transformers import SentenceTransformer
            self._model = SentenceTransformer(self.name[3:])
        else:
            import joblib
            self._model = joblib.load(LSA_PATH)

    def _fit_lsa(self, corpus: list[str]):
        import joblib
        from sklearn.decomposition import TruncatedSVD
        from sklearn.feature_extraction.text import TfidfVectorizer

        tfidf = TfidfVectorizer(stop_words="english", sublinear_tf=True, ngram_range=(1, 2), min_df=1)
        x = tfidf.fit_transform(corpus)
        k = max(2, min(64, x.shape[0] - 1, x.shape[1] - 1))
        svd = TruncatedSVD(n_components=k, random_state=7).fit(x)
        MODEL_DIR.mkdir(exist_ok=True)
        joblib.dump((tfidf, svd), LSA_PATH)
        self._model = (tfidf, svd)
