"""Receipt OCR for Cameroonian receipts.

Pipeline:
  1. Tesseract reads raw text (English + French language packs).
  2. A receipt parser pulls likely fields out of the text:
       * total amount (XAF / FCFA / numbers near "Total")
       * date
       * vendor (top-most non-numeric line)
       * line items (best-effort)

This module is the ONE place that knows about the OCR engine. To swap to
Google Cloud Vision later, replace `_run_tesseract` and leave the parser
untouched.

Requires the `tesseract` system binary:
    brew install tesseract tesseract-lang   # macOS
    apt install tesseract-ocr tesseract-ocr-fra tesseract-ocr-eng   # debian
"""
from __future__ import annotations

import logging
import re
import shutil
from dataclasses import dataclass, asdict
from datetime import datetime, date
from typing import Optional

logger = logging.getLogger("nkapsave.ocr")


class OcrNotAvailable(RuntimeError):
    """Tesseract isn't installed or the OCR engine returned an error."""


@dataclass
class OcrLineItem:
    name:   str
    amount: Optional[float]


@dataclass
class OcrResult:
    raw_text:    str
    vendor:      Optional[str]
    total:       Optional[float]
    txn_date:    Optional[str]   # ISO YYYY-MM-DD
    items:       list[OcrLineItem]
    confidence:  float           # 0..1 rough heuristic


# ─── Engine adapter ───────────────────────────────────────────────

def is_available() -> bool:
    return shutil.which("tesseract") is not None


def _run_tesseract(image_bytes: bytes) -> str:
    """Call Tesseract on raw bytes. Returns extracted UTF-8 text."""
    if not is_available():
        raise OcrNotAvailable(
            "tesseract binary not found on PATH. "
            "Install with `brew install tesseract tesseract-lang`."
        )
    import pytesseract
    from PIL import Image
    import io

    try:
        img = Image.open(io.BytesIO(image_bytes))
    except Exception as e:
        raise OcrNotAvailable(f"Could not open image: {e}") from e

    # Light preprocessing for receipts (greyscale helps contrast).
    img = img.convert("L")
    try:
        # French + English. If lang packs aren't installed, Tesseract falls
        # back to default automatically.
        return pytesseract.image_to_string(img, lang="fra+eng")
    except pytesseract.TesseractError as e:
        # Most often "Failed loading language 'fra'". Retry default.
        logger.warning("tesseract multi-lang failed (%s); retrying default", e)
        return pytesseract.image_to_string(img)


# ─── Parser ───────────────────────────────────────────────────────

_AMOUNT_RE = re.compile(
    # Either a separator-grouped number ("1 500", "1,500", "1.500")
    # OR a plain digit run ("4600"), optionally followed by decimals.
    r"(?P<num>(?:\d{1,3}(?:[ .,]\d{3})+|\d+)(?:[.,]\d{1,2})?)\s*"
    r"(?P<unit>fcfa|f\.cfa|xaf|f\s*cfa|frs?|fr\s*cfa)?",
    re.IGNORECASE,
)
_TOTAL_HINTS = re.compile(
    r"\b(total|montant|à\s*payer|a\s*payer|net\s*à\s*payer|grand\s*total|amount)\b",
    re.IGNORECASE,
)
_DATE_RE = re.compile(
    r"\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b"
)


def _normalize_amount(raw: str) -> Optional[float]:
    s = raw.strip().replace(" ", "")
    # Cameroonian receipts use either '.' or ',' as thousands separator.
    # Drop both unless what's left after dropping looks too small to be a total.
    if s.count(".") > 1 or s.count(",") > 1:
        s = s.replace(".", "").replace(",", "")
    else:
        # Single separator — treat as thousands.
        s = s.replace(".", "").replace(",", "")
    try:
        return float(s)
    except ValueError:
        return None


def _likely_total(lines: list[str]) -> Optional[float]:
    """Score each line for total-ness, return the best candidate."""
    candidates: list[tuple[float, float]] = []  # (score, amount)
    for i, line in enumerate(lines):
        lower = line.lower()
        score = 0.0
        if _TOTAL_HINTS.search(lower):
            score += 5
        if "fcfa" in lower or "xaf" in lower or "frcfa" in lower:
            score += 2
        for m in _AMOUNT_RE.finditer(line):
            amt = _normalize_amount(m.group("num"))
            if amt is None or amt < 100:
                continue
            # Receipts: bigger numbers tend to be totals, but cap so a wild
            # 1.5M outlier doesn't dominate over a clean labelled total.
            magnitude = min(amt, 5_000_000)
            local = score + (magnitude / 5_000_000) * 3
            candidates.append((local, amt))
    if not candidates:
        return None
    candidates.sort(key=lambda x: -x[0])
    return candidates[0][1]


def _likely_date(text: str) -> Optional[str]:
    m = _DATE_RE.search(text)
    if not m:
        return None
    d, mo, y = m.groups()
    try:
        di, mi, yi = int(d), int(mo), int(y)
        if yi < 100:
            yi += 2000
        # Reject impossible dates.
        dt = date(yi, mi, di)
    except (ValueError, TypeError):
        return None
    if dt > date.today():
        return None
    if dt < date(2000, 1, 1):
        return None
    return dt.isoformat()


def _vendor(lines: list[str]) -> Optional[str]:
    # Vendor is usually the first non-empty line that isn't mostly digits.
    for line in lines[:5]:
        s = line.strip()
        if len(s) < 3:
            continue
        digit_ratio = sum(c.isdigit() for c in s) / max(len(s), 1)
        if digit_ratio > 0.4:
            continue
        return s[:60]
    return None


def _line_items(lines: list[str]) -> list[OcrLineItem]:
    items: list[OcrLineItem] = []
    for line in lines:
        s = line.strip()
        if len(s) < 4: continue
        if _TOTAL_HINTS.search(s.lower()):
            continue
        m = _AMOUNT_RE.search(s)
        if not m: continue
        amt = _normalize_amount(m.group("num"))
        if amt is None or amt < 50:
            continue
        # Strip the matched amount from the name part.
        name = (s[:m.start()] + s[m.end():]).strip(" -:|.")
        if len(name) < 2:
            continue
        items.append(OcrLineItem(name=name[:60], amount=amt))
    return items[:15]


def parse_receipt(raw_text: str) -> OcrResult:
    lines = [l for l in raw_text.splitlines() if l.strip()]
    total  = _likely_total(lines)
    vendor = _vendor(lines)
    iso_d  = _likely_date(raw_text)
    items  = _line_items(lines)

    # Rough confidence: 0.3 baseline + bonuses for each field we resolved.
    conf = 0.3
    if total:  conf += 0.3
    if vendor: conf += 0.2
    if iso_d:  conf += 0.1
    if items:  conf += 0.1
    return OcrResult(
        raw_text=raw_text,
        vendor=vendor, total=total, txn_date=iso_d,
        items=items, confidence=round(min(conf, 0.99), 2),
    )


# ─── Public entry point ───────────────────────────────────────────

def extract(image_bytes: bytes) -> OcrResult:
    text = _run_tesseract(image_bytes)
    return parse_receipt(text)


def result_to_dict(r: OcrResult) -> dict:
    return {
        "raw_text": r.raw_text,
        "vendor":   r.vendor,
        "total":    r.total,
        "txn_date": r.txn_date,
        "items":    [asdict(i) for i in r.items],
        "confidence": r.confidence,
    }
