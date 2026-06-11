"""Semantic retrieval for NkapBot.

Builds a vector index over the knowledge-base corpus (knowledge_base.py) and
answers similarity queries. This is the meaning-based half of NkapBot's RAG:
given the user's free-form question it returns the most relevant financial-
literacy passages, which the prompt builder injects as grounding KNOWLEDGE.

Storage: the index is a small JSON file (data/kb_index.json) plus an in-process
cache. The corpus is on the order of dozens of passages, so a brute-force
cosine scan in Python is instant and avoids any external vector-store / pgvector
dependency. The index is rebuilt automatically whenever the corpus text or the
embedding provider/model changes (tracked via a signature), so there's nothing
to migrate — delete the JSON file to force a clean rebuild.

For larger or per-user corpora (e.g. semantic search over a user's own
transaction notes) swap this file's `_search` for a pgvector-backed query; the
public API (`semantic_search`) stays the same.

Public API
----------
    await semantic_search(query, *, language, k=..., min_score=...) -> list[Hit]
    await build_index(force=False)   -> dict   (counts + provider info)
    await index_status()             -> dict
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import logging
from pathlib import Path
from typing import Optional, TypedDict

from core.config import settings
from data.knowledge_base import KnowledgeChunk, build_corpus, corpus_text
from services.embeddings import cosine, embed_query, embed_texts, provider_signature

logger = logging.getLogger("nkapsave.rag")

_INDEX_PATH = Path(__file__).resolve().parent.parent / "data" / "kb_index.json"

# In-process cache so we don't re-read/parse the JSON on every request.
_CACHE: Optional[dict] = None
_BUILD_LOCK = asyncio.Lock()


class Hit(TypedDict):
    id:       str
    title:    str
    content:  str
    source:   str
    language: str
    score:    float


# ─── Signatures ────────────────────────────────────────────────────

def _corpus_signature(chunks: list[KnowledgeChunk]) -> str:
    """Hash of all chunk ids + text. Changes if the corpus content changes,
    triggering a rebuild so stale embeddings are never served."""
    h = hashlib.sha256()
    for c in sorted(chunks, key=lambda x: x["id"]):
        h.update(c["id"].encode("utf-8"))
        h.update(b"\x00")
        h.update(corpus_text(c).encode("utf-8"))
        h.update(b"\x00")
    return h.hexdigest()[:16]


# ─── Build ─────────────────────────────────────────────────────────

async def build_index(force: bool = False) -> dict:
    """Embed the corpus and persist the index. No-op (returns cached meta) if
    an up-to-date index already exists, unless force=True."""
    global _CACHE
    async with _BUILD_LOCK:
        chunks = build_corpus()
        corpus_sig = _corpus_signature(chunks)
        provider_sig = provider_signature()

        if not force:
            existing = _load_from_disk()
            if (existing
                    and existing.get("corpus_signature") == corpus_sig
                    and existing.get("provider_signature") == provider_sig):
                _CACHE = existing
                return _meta(existing, rebuilt=False)

        logger.info(
            "rag: building knowledge index (%d chunks, provider=%s)",
            len(chunks), provider_sig,
        )
        vectors = await embed_texts(
            [corpus_text(c) for c in chunks], input_type="document"
        )
        records = [
            {
                "id": c["id"],
                "title": c["title"],
                "content": c["content"],
                "source": c["source"],
                "language": c["language"],
                "tags": c["tags"],
                "embedding": vec,
            }
            for c, vec in zip(chunks, vectors)
        ]
        index = {
            "version": 1,
            "corpus_signature": corpus_sig,
            "provider_signature": provider_sig,
            "count": len(records),
            "records": records,
        }
        _write_to_disk(index)
        _CACHE = index
        return _meta(index, rebuilt=True)


def _meta(index: dict, *, rebuilt: bool) -> dict:
    return {
        "count": index.get("count", 0),
        "provider_signature": index.get("provider_signature"),
        "corpus_signature": index.get("corpus_signature"),
        "rebuilt": rebuilt,
    }


# ─── Search ────────────────────────────────────────────────────────

async def _ensure_index() -> dict:
    """Return a fresh, in-memory index, building/refreshing it on demand."""
    global _CACHE
    chunks = build_corpus()
    corpus_sig = _corpus_signature(chunks)
    provider_sig = provider_signature()

    if (_CACHE
            and _CACHE.get("corpus_signature") == corpus_sig
            and _CACHE.get("provider_signature") == provider_sig):
        return _CACHE

    # Cache miss → (re)build (build_index handles the disk-cache fast path).
    await build_index(force=False)
    return _CACHE or {"records": []}


async def semantic_search(
    query: str,
    *,
    language: str = "en",
    k: Optional[int] = None,
    min_score: Optional[float] = None,
) -> list[Hit]:
    """Return up to k passages most semantically similar to `query`.

    Results are restricted to the user's language plus English as a fallback
    pool, so a French question prefers French passages but can still surface an
    English-only one when nothing better exists. Never raises — on any failure
    it returns an empty list so the chat turn degrades to structured-data-only.
    """
    if not (query or "").strip():
        return []
    k = k or settings.RAG_TOP_K
    min_score = settings.RAG_MIN_SCORE if min_score is None else min_score
    lang = (language or "en").lower()
    if lang in ("pcm",):
        lang = "pidgin"
    allowed = {lang, "en"}  # english is the universal fallback pool

    try:
        index = await _ensure_index()
        qvec = await embed_query(query)
        scored: list[Hit] = []
        for rec in index.get("records", []):
            if rec["language"] not in allowed:
                continue
            score = cosine(qvec, rec["embedding"])
            if score < min_score:
                continue
            scored.append(Hit(
                id=rec["id"],
                title=rec["title"],
                content=rec["content"],
                source=rec["source"],
                language=rec["language"],
                score=round(score, 4),
            ))
        scored.sort(key=lambda h: h["score"], reverse=True)
        return _dedupe_by_concept(scored)[:k]
    except Exception as e:  # pragma: no cover - retrieval must never break chat
        logger.warning("rag: semantic_search failed (%s)", e)
        return []


def _dedupe_by_concept(hits: list[Hit]) -> list[Hit]:
    """The same concept exists in several languages (id = source:concept:lang).
    Keep only the highest-scoring language variant per concept so we don't feed
    Claude the same passage twice."""
    seen: set[str] = set()
    out: list[Hit] = []
    for h in hits:
        parts = h["id"].split(":")
        concept = ":".join(parts[:2]) if len(parts) >= 2 else h["id"]
        if concept in seen:
            continue
        seen.add(concept)
        out.append(h)
    return out


# ─── Status / persistence ──────────────────────────────────────────

async def index_status() -> dict:
    chunks = build_corpus()
    on_disk = _load_from_disk()
    return {
        "index_exists": on_disk is not None,
        "indexed_count": (on_disk or {}).get("count", 0),
        "corpus_count": len(chunks),
        "active_provider_signature": provider_signature(),
        "index_provider_signature": (on_disk or {}).get("provider_signature"),
        "up_to_date": bool(
            on_disk
            and on_disk.get("corpus_signature") == _corpus_signature(chunks)
            and on_disk.get("provider_signature") == provider_signature()
        ),
        "path": str(_INDEX_PATH),
    }


def _load_from_disk() -> Optional[dict]:
    if not _INDEX_PATH.exists():
        return None
    try:
        with _INDEX_PATH.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        logger.warning("rag: failed to read index (%s)", e)
        return None


def _write_to_disk(index: dict) -> None:
    try:
        _INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp = _INDEX_PATH.with_suffix(".json.tmp")
        with tmp.open("w", encoding="utf-8") as f:
            json.dump(index, f)
        tmp.replace(_INDEX_PATH)
    except Exception as e:
        logger.warning("rag: failed to write index (%s)", e)
