"""Spending-pattern detector.

Surfaces concrete, actionable observations from the user's expense history:
  * weekend vs weekday ratio
  * single most overspent category (largest absolute over-budget delta)
  * daily average burn rate over the trailing window
  * month-over-month delta per category (top movers)

Returns a list of pattern dicts the chat router can pass to Claude AND
hand to the Flutter pattern-alert / breakdown cards. Everything is
computed from the already-fetched expense context to avoid extra DB
round-trips.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional, TypedDict


class Pattern(TypedDict):
    pattern_type: str          # weekend_skew | category_overspend | burn_rate | mom_delta
    severity:     str          # info | warn | critical
    description:  str          # human-readable, references XAF
    amount:       int          # central number powering the alert (XAF)
    suggestion:   str          # what to do about it


@dataclass
class _Tx:
    name: str
    category: str
    amount: int
    date: Optional[datetime]


def _parse(recent: list[dict]) -> list[_Tx]:
    out: list[_Tx] = []
    for r in recent:
        d = r.get("date")
        dt: Optional[datetime] = None
        if d:
            try:
                dt = datetime.fromisoformat(d)
            except ValueError:
                dt = None
        out.append(_Tx(
            name=r.get("name") or "",
            category=r.get("category") or "Other",
            amount=int(r.get("amount") or 0),
            date=dt,
        ))
    return out


# ─── Individual detectors ──────────────────────────────────────────

def _weekend_skew(txs: list[_Tx]) -> Optional[Pattern]:
    if not txs:
        return None
    weekend = sum(t.amount for t in txs if t.date and t.date.weekday() >= 5)
    weekday = sum(t.amount for t in txs if t.date and t.date.weekday() < 5)
    total = weekend + weekday
    if total < 5_000:  # too little signal to bother
        return None
    weekend_share = weekend / total
    # Two days out of seven ≈ 28.6% expected.
    if weekend_share < 0.45:
        return None
    return {
        "pattern_type": "weekend_skew",
        "severity":     "warn" if weekend_share < 0.6 else "critical",
        "description":  f"{int(weekend_share * 100)}% of your spending happened on weekends "
                        f"({weekend:,} XAF vs {weekday:,} weekday).",
        "amount":       weekend,
        "suggestion":   "Set a weekend cap — e.g. cash a fixed envelope on Friday and stop when it's empty.",
    }


def _category_overspend(by_cat: dict[str, int], budgets: dict[str, int]) -> Optional[Pattern]:
    if not budgets:
        return None
    worst_cat: Optional[str] = None
    worst_over = 0
    for cat, limit in budgets.items():
        spent = by_cat.get(cat, 0)
        over = spent - limit
        if over > worst_over:
            worst_over = over
            worst_cat  = cat
    if not worst_cat or worst_over <= 0:
        return None
    return {
        "pattern_type": "category_overspend",
        "severity":     "critical" if worst_over > budgets[worst_cat] * 0.25 else "warn",
        "description":  f"{worst_cat} is {worst_over:,} XAF over budget this month "
                        f"({by_cat.get(worst_cat, 0):,} spent vs {budgets[worst_cat]:,} cap).",
        "amount":       worst_over,
        "suggestion":   f"Trim {worst_cat} by {int(worst_over * 1.1):,} XAF next month to claw the overage back.",
    }


def _burn_rate(txs: list[_Tx]) -> Optional[Pattern]:
    if not txs:
        return None
    now = datetime.utcnow()
    cutoff = now - timedelta(days=30)
    dated = [t for t in txs if t.date and t.date >= cutoff]
    if not dated:
        return None
    total = sum(t.amount for t in dated)
    days = max((now - min(t.date for t in dated)).days, 1)
    per_day = total // days
    if per_day <= 0:
        return None
    return {
        "pattern_type": "burn_rate",
        "severity":     "info",
        "description":  f"Your daily spending averages {per_day:,} XAF over the last {days} day"
                        f"{'s' if days != 1 else ''} "
                        f"({total:,} XAF total).",
        "amount":       per_day,
        "suggestion":   "Plot this against your income — anything above 60% of daily income is a sign to tighten up.",
    }


def _month_over_month(current: dict[str, int], previous: dict[str, int]) -> Optional[Pattern]:
    """Biggest absolute jump in any single category vs last month."""
    if not previous:
        return None
    movers: list[tuple[str, int, int]] = []  # (category, delta, prev)
    for cat, prev_amt in previous.items():
        cur = current.get(cat, 0)
        delta = cur - prev_amt
        if delta > 0:
            movers.append((cat, delta, prev_amt))
    if not movers:
        return None
    movers.sort(key=lambda m: m[1], reverse=True)
    cat, delta, prev_amt = movers[0]
    if delta < 5_000:
        return None
    pct = (delta / prev_amt * 100) if prev_amt > 0 else 100.0
    return {
        "pattern_type": "mom_delta",
        "severity":     "warn" if pct >= 30 else "info",
        "description":  f"{cat} jumped {delta:,} XAF (+{pct:.0f}%) versus last month "
                        f"({current.get(cat, 0):,} vs {prev_amt:,}).",
        "amount":       delta,
        "suggestion":   f"Look at your last {cat} transactions to spot the new spend, "
                        "then decide if it's a one-off or a habit forming.",
    }


# ─── Public entry ──────────────────────────────────────────────────

def detect_patterns(expenses_context: dict) -> list[Pattern]:
    """Run all detectors against the expenses-category context. Returns a
    possibly-empty list of patterns in descending severity then amount."""
    txs           = _parse(expenses_context.get("recent_transactions") or [])
    by_cat        = expenses_context.get("by_category") or {}
    prev_by_cat   = expenses_context.get("prev_by_category") or {}
    budgets       = expenses_context.get("budgets") or {}

    out: list[Pattern] = []
    for detector in (
        lambda: _category_overspend(by_cat, budgets),
        lambda: _weekend_skew(txs),
        lambda: _month_over_month(by_cat, prev_by_cat),
        lambda: _burn_rate(txs),
    ):
        try:
            p = detector()
        except Exception:
            p = None
        if p is not None:
            out.append(p)

    _sev_order = {"critical": 0, "warn": 1, "info": 2}
    out.sort(key=lambda p: (_sev_order.get(p["severity"], 99), -p["amount"]))
    return out
