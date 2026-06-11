"""Build (or rebuild) the NkapBot semantic-RAG knowledge index.

Embeds every passage in the knowledge base with the configured provider and
writes data/kb_index.json. The chat endpoint also builds this lazily on first
use, but running it ahead of time means the first user request isn't slowed by
embedding the whole corpus.

Usage (from the backend/ directory, with the venv active):

    python scripts/build_kb.py          # build if missing/stale
    python scripts/build_kb.py --force  # always re-embed
    python scripts/build_kb.py --status # just report, don't build
"""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

# Allow running as a plain script: ensure backend/ is importable.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from services.embeddings import active_provider, provider_signature  # noqa: E402
from services.rag_service import build_index, index_status  # noqa: E402


async def _main(force: bool, status_only: bool) -> int:
    print(f"Embedding provider: {active_provider()}  ({provider_signature()})")
    if active_provider() == "hash":
        print("  ⚠  Using the lexical fallback (no embedding key/library "
              "detected).\n     Set VOYAGE_API_KEY (recommended) or install "
              "sentence-transformers\n     for real semantic retrieval.")

    if status_only:
        print(json.dumps(await index_status(), indent=2))
        return 0

    meta = await build_index(force=force)
    print("Index ready:")
    print(json.dumps(meta, indent=2))
    print(json.dumps(await index_status(), indent=2))
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="re-embed even if up to date")
    ap.add_argument("--status", action="store_true", help="report status only")
    args = ap.parse_args()
    raise SystemExit(asyncio.run(_main(args.force, args.status)))
