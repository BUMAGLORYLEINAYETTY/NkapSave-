"""Embedding provider abstraction for NkapBot's semantic RAG.

Turns text into vectors so the chatbot can retrieve financial-literacy
passages by *meaning* rather than keyword overlap. The provider is chosen
from settings (see EMBEDDING_PROVIDER) and degrades gracefully:

    auto  → voyage (if key) → local (if installed) → hash fallback

so the pipeline always runs — with zero new API keys or heavy dependencies
in development, and production-grade quality the moment a real provider is
configured. The same abstraction is used to embed the corpus at index-build
time and to embed the user's question at query time.

Public API
----------
    await embed_texts(texts, input_type=...) -> list[list[float]]
    await embed_query(text)                  -> list[float]
    active_provider()                        -> str   ("voyage"|"openai"|"local"|"hash")
    provider_signature()                     -> str   (provider:model:dim, for cache keys)
"""
from __future__ import annotations

import asyncio
import hashlib
import logging
import math
import re
from typing import Literal, Optional

import httpx

from core.config import settings

logger = logging.getLogger("nkapsave.embeddings")

InputType = Literal["document", "query"]

# Provider defaults — overridable via settings.EMBEDDING_MODEL.
_DEFAULT_MODELS = {
    "voyage": "voyage-3.5",
    "openai": "text-embedding-3-small",
    "local":  "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
}

_VOYAGE_URL = "https://api.voyageai.com/v1/embeddings"
_OPENAI_URL = "https://api.openai.com/v1/embeddings"

# Lazily-loaded sentence-transformers model (kept process-wide).
_LOCAL_MODEL = None  # type: ignore[var-annotated]


# ─── Provider resolution ───────────────────────────────────────────

def active_provider() -> str:
    """Resolve the configured provider, honouring the 'auto' policy."""
    choice = (settings.EMBEDDING_PROVIDER or "auto").lower().strip()
    if choice in ("voyage", "openai", "local", "hash"):
        return choice
    # auto
    if settings.VOYAGE_API_KEY:
        return "voyage"
    if settings.OPENAI_API_KEY:
        return "openai"
    if _local_available():
        return "local"
    return "hash"


def _model_for(provider: str) -> str:
    return settings.EMBEDDING_MODEL or _DEFAULT_MODELS.get(provider, "hash")


def provider_signature() -> str:
    """Stable key identifying the current embedding space. Changing provider,
    model, or dim invalidates a previously-built index cache."""
    provider = active_provider()
    if provider == "hash":
        return f"hash:lexical:{settings.EMBEDDING_DIM}"
    return f"{provider}:{_model_for(provider)}"


def _local_available() -> bool:
    try:
        import sentence_transformers  # noqa: F401
        return True
    except Exception:
        return False


# ─── Public API ────────────────────────────────────────────────────

async def embed_texts(
    texts: list[str],
    *,
    input_type: InputType = "document",
) -> list[list[float]]:
    """Embed a batch of texts with the active provider. Always returns one
    L2-normalised vector per input; never raises for empty input."""
    if not texts:
        return []
    provider = active_provider()
    try:
        if provider == "voyage":
            return await _embed_voyage(texts, input_type)
        if provider == "openai":
            return await _embed_openai(texts)
        if provider == "local":
            return await _embed_local(texts)
    except Exception as e:  # pragma: no cover - network/runtime guard
        logger.warning(
            "embeddings: provider '%s' failed (%s) — falling back to lexical hash",
            provider, e,
        )
    return [_hash_embed(t) for t in texts]


async def embed_query(text: str) -> list[float]:
    vecs = await embed_texts([text], input_type="query")
    return vecs[0] if vecs else _hash_embed(text)


# ─── Voyage AI (recommended) ───────────────────────────────────────

async def _embed_voyage(texts: list[str], input_type: InputType) -> list[list[float]]:
    if not settings.VOYAGE_API_KEY:
        raise RuntimeError("VOYAGE_API_KEY not set")
    payload = {
        "input": texts,
        "model": _model_for("voyage"),
        "input_type": input_type,  # Voyage tunes doc vs query embeddings
    }
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(
            _VOYAGE_URL,
            headers={"Authorization": f"Bearer {settings.VOYAGE_API_KEY}"},
            json=payload,
        )
        resp.raise_for_status()
        data = resp.json()["data"]
    # API preserves input order via the `index` field; sort to be safe.
    ordered = sorted(data, key=lambda d: d.get("index", 0))
    return [_normalise(d["embedding"]) for d in ordered]


# ─── OpenAI ────────────────────────────────────────────────────────

async def _embed_openai(texts: list[str]) -> list[list[float]]:
    if not settings.OPENAI_API_KEY:
        raise RuntimeError("OPENAI_API_KEY not set")
    payload = {"input": texts, "model": _model_for("openai")}
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(
            _OPENAI_URL,
            headers={"Authorization": f"Bearer {settings.OPENAI_API_KEY}"},
            json=payload,
        )
        resp.raise_for_status()
        data = resp.json()["data"]
    ordered = sorted(data, key=lambda d: d.get("index", 0))
    return [_normalise(d["embedding"]) for d in ordered]


# ─── Local (sentence-transformers, offline) ────────────────────────

def _load_local():
    global _LOCAL_MODEL
    if _LOCAL_MODEL is None:
        from sentence_transformers import SentenceTransformer  # heavy import
        _LOCAL_MODEL = SentenceTransformer(_model_for("local"))
    return _LOCAL_MODEL


async def _embed_local(texts: list[str]) -> list[list[float]]:
    model = await asyncio.to_thread(_load_local)
    # encode() is CPU-bound + synchronous → keep it off the event loop.
    vectors = await asyncio.to_thread(
        lambda: model.encode(texts, normalize_embeddings=True).tolist()
    )
    return [list(map(float, v)) for v in vectors]


# ─── Deterministic lexical fallback (no deps, no key) ──────────────

_TOKEN_RE = re.compile(r"[a-zàâçéèêëîïôûùüÿñæœ0-9]+", re.IGNORECASE)


def _hash_embed(text: str) -> list[float]:
    """A bag-of-words vector hashed into EMBEDDING_DIM buckets and L2
    normalised. This is *lexical*, not semantic — cosine similarity here
    reflects shared tokens. It exists so the RAG pipeline runs (and tests
    pass) with no embedding key or library installed; set a real provider
    for genuine meaning-based retrieval."""
    dim = max(settings.EMBEDDING_DIM, 16)
    vec = [0.0] * dim
    tokens = _TOKEN_RE.findall(text.lower())
    for tok in tokens:
        h = hashlib.md5(tok.encode("utf-8")).digest()
        idx = int.from_bytes(h[:4], "big") % dim
        sign = 1.0 if h[4] & 1 else -1.0
        vec[idx] += sign
    return _normalise(vec)


# ─── Shared helpers ────────────────────────────────────────────────

def _normalise(vec: list[float]) -> list[float]:
    norm = math.sqrt(sum(x * x for x in vec))
    if norm == 0.0:
        return [float(x) for x in vec]
    return [float(x) / norm for x in vec]


def cosine(a: list[float], b: list[float]) -> float:
    """Cosine similarity. Inputs are expected pre-normalised (this module
    always normalises), so this reduces to a dot product, but we guard for
    safety in case a raw vector slips through."""
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    return max(-1.0, min(1.0, dot))
