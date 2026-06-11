"""NkapBot RAG context retrieval.

Given a user_id and the category of their question, builds a structured
context dict with the user's real numbers so the prompt builder can hand
Claude concrete facts to reason over instead of generic advice.

Public API:
  * detect_category(message)            → CategoryT
  * fetch_context(db, user, category)   → dict
  * INCOME_BRACKET_MIDPOINTS             → midpoint per bracket
"""
from __future__ import annotations

import re
from datetime import datetime, timedelta
from typing import Literal, Optional

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from models.expense import Expense, Budget
from models.momo import AutoSavePlan, MoMoTransaction
from models.njangi import NjangiGroup, NjangiMember
from models.savings import SavingsGoal
from models.user import User

# ─── Categories ────────────────────────────────────────────────────

CategoryT = Literal["expenses", "savings", "njangi", "health", "education"]

# Keyword buckets used by detect_category. Order matters: health is matched
# first because phrases like "how am I doing" are more often health questions
# than category-specific ones.
_KEYWORDS: dict[CategoryT, tuple[str, ...]] = {
    "health": (
        "financial health", "how am i doing", "how healthy", "score", "rating",
        "santé financière", "comment je vais", "sante financiere",
        "how i dey", "how my money dey",
    ),
    "expenses": (
        "spend", "spent", "spending", "expense", "budget", "waste",
        "where my money", "where does my money", "depense", "dépense",
        "i bought", "j'ai dépensé", "j'ai depense",
    ),
    "savings": (
        "save", "saved", "saving", "goal", "target", "épargne", "epargne",
        "objectif", "épargner", "epargner", "i wan save",
    ),
    "njangi": (
        "njangi", "tontine", "group savings", "rotating", "payout",
        "mon njangi", "ma tontine",
    ),
    "education": (
        "what is", "explain", "how do i", "how do you", "tell me about",
        "qu'est-ce que", "qu'est ce que", "comment", "explique",
        "wetin be", "wetin na",
        "emergency fund", "compound interest", "investment", "debt",
    ),
}


def detect_category(message: str) -> CategoryT:
    """Best-effort category classifier. Falls back to 'health'."""
    msg = message.lower().strip()
    # Health first — overrides others if the user explicitly asks about it.
    for kw in _KEYWORDS["health"]:
        if kw in msg:
            return "health"
    # Then specific categories.
    for cat in ("savings", "njangi", "expenses", "education"):
        for kw in _KEYWORDS[cat]:
            if kw in msg:
                return cat  # type: ignore[return-value]
    # Default
    return "health"


# ─── Income brackets ───────────────────────────────────────────────
# Discrete buckets keep the prompt + savings-rate math deterministic.
# Midpoints are in XAF.
INCOME_BRACKET_MIDPOINTS: dict[str, int] = {
    "under_50k":   30_000,
    "50k_100k":    75_000,
    "100k_300k":   200_000,
    "300k_500k":   400_000,
    "500k_1m":     750_000,
    "over_1m":   1_500_000,
}

INCOME_BRACKET_LABELS: dict[str, str] = {
    "under_50k":  "Under 50,000 XAF",
    "50k_100k":   "50,000 – 100,000 XAF",
    "100k_300k":  "100,000 – 300,000 XAF",
    "300k_500k":  "300,000 – 500,000 XAF",
    "500k_1m":    "500,000 – 1,000,000 XAF",
    "over_1m":    "Over 1,000,000 XAF",
}


def income_midpoint(bracket: Optional[str]) -> Optional[int]:
    if bracket is None:
        return None
    return INCOME_BRACKET_MIDPOINTS.get(bracket)


# ─── Time helpers ──────────────────────────────────────────────────

def _month_start(d: datetime) -> datetime:
    return datetime(d.year, d.month, 1)


def _prev_month_start(d: datetime) -> datetime:
    if d.month == 1:
        return datetime(d.year - 1, 12, 1)
    return datetime(d.year, d.month - 1, 1)


# ─── Per-category retrieval ────────────────────────────────────────

async def _fetch_expenses_context(db: AsyncSession, user_id: str) -> dict:
    now = datetime.utcnow()
    mstart = _month_start(now)
    pstart = _prev_month_start(now)

    # Current month expenses
    cm_res = await db.execute(
        select(Expense.category, func.sum(Expense.amount).label("total"))
        .where(
            Expense.user_id == user_id,
            Expense.txn_type == "EXPENSE",
            Expense.txn_date >= mstart,
        )
        .group_by(Expense.category)
    )
    current = {row.category: int(row.total or 0) for row in cm_res}

    # Previous month — for delta context
    pm_res = await db.execute(
        select(Expense.category, func.sum(Expense.amount).label("total"))
        .where(
            Expense.user_id == user_id,
            Expense.txn_type == "EXPENSE",
            Expense.txn_date >= pstart,
            Expense.txn_date < mstart,
        )
        .group_by(Expense.category)
    )
    previous = {row.category: int(row.total or 0) for row in pm_res}

    # Budgets
    b_res = await db.execute(
        select(Budget.category, Budget.amount)
        .where(Budget.user_id == user_id, Budget.period == "monthly")
    )
    budgets = {row.category: int(row.amount) for row in b_res}

    # Last 30 transactions for any pattern observations the LLM may want
    recent_res = await db.execute(
        select(Expense.name, Expense.category, Expense.amount, Expense.txn_date)
        .where(Expense.user_id == user_id, Expense.txn_type == "EXPENSE")
        .order_by(Expense.txn_date.desc().nulls_last())
        .limit(30)
    )
    recent = [
        {
            "name": r.name,
            "category": r.category,
            "amount": int(r.amount),
            "date": r.txn_date.isoformat() if r.txn_date else None,
        }
        for r in recent_res
    ]

    return {
        "month_total":         sum(current.values()),
        "prev_month_total":    sum(previous.values()),
        "by_category":         current,
        "prev_by_category":    previous,
        "budgets":             budgets,
        "recent_transactions": recent,
    }


async def _fetch_savings_context(db: AsyncSession, user_id: str) -> dict:
    goals_res = await db.execute(
        select(SavingsGoal).where(SavingsGoal.user_id == user_id)
    )
    goals = [
        {
            "id":           str(g.id),
            "name":         g.name,
            "emoji":        g.emoji,
            "target":       int(g.target),
            "current":      int(g.current),
            "is_completed": g.is_completed,
            "deadline":     g.deadline.isoformat() if g.deadline else None,
            "note":         g.note,
        }
        for g in goals_res.scalars().all()
    ]

    plans_res = await db.execute(
        select(AutoSavePlan).where(AutoSavePlan.user_id == user_id)
    )
    plans = [
        {
            "goal_id":          str(p.goal_id),
            "amount":           int(p.amount),
            "frequency":        p.frequency,
            "active":           p.active,
            "next_run_at":      p.next_run_at.isoformat() if p.next_run_at else None,
            "reminder_enabled": p.reminder_enabled,
        }
        for p in plans_res.scalars().all()
    ]

    # Auto-save consistency window: 30 days back
    cutoff = datetime.utcnow() - timedelta(days=30)
    tx_res = await db.execute(
        select(MoMoTransaction.status, func.count(MoMoTransaction.id))
        .where(
            MoMoTransaction.user_id == user_id,
            MoMoTransaction.initiated_at >= cutoff,
        )
        .group_by(MoMoTransaction.status)
    )
    tx_counts = {row.status: int(row[1]) for row in tx_res}
    attempts = sum(tx_counts.values())
    successes = tx_counts.get("SUCCESSFUL", 0)

    return {
        "goals":            goals,
        "plans":            plans,
        "auto_save_30d":    {"attempts": attempts, "successes": successes, "by_status": tx_counts},
    }


async def _fetch_njangi_context(db: AsyncSession, user_id: str) -> dict:
    # All groups the user is a member of, with their per-group trust score.
    rows = await db.execute(
        select(NjangiMember, NjangiGroup)
        .join(NjangiGroup, NjangiGroup.id == NjangiMember.group_id)
        .where(NjangiMember.user_id == user_id)
    )
    groups = []
    trust_scores: list[float] = []
    for member, group in rows:
        groups.append({
            "group_id":          str(group.id),
            "name":               group.name,
            "contribution":      int(group.contribution),
            "frequency":          group.frequency,
            "current_cycle":      group.current_cycle,
            "total_cycles":       group.total_cycles,
            "status":             str(group.status),
            "position":           member.position,
            "trust_score":        float(member.trust_score or 0),
            "has_paid":           bool(member.has_paid),
        })
        trust_scores.append(float(member.trust_score or 0))

    avg_trust = (sum(trust_scores) / len(trust_scores)) if trust_scores else None
    return {
        "groups":      groups,
        "avg_trust":   round(avg_trust, 1) if avg_trust is not None else None,
        "group_count": len(groups),
    }


async def _fetch_education_context(user: User) -> dict:
    """Education only needs the user's language + bracket for examples."""
    return {
        "preferred_language": user.preferred_language or "en",
        "income_bracket":     user.income_bracket,
        "income_midpoint":    income_midpoint(user.income_bracket),
    }


# ─── Topic lookup ──────────────────────────────────────────────────
# Maps natural-language phrases to education_topics.py keys.
_TOPIC_KEYS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"\b(emergency fund|epargne d'urgence|épargne d'urgence)\b", re.I),
     "emergency_fund"),
    (re.compile(r"\b(compound interest|interets composes|intérêts composés)\b", re.I),
     "compound_interest"),
    (re.compile(r"\b(savings rate|taux d'epargne|taux d'épargne)\b", re.I),
     "savings_rate"),
    (re.compile(r"\b(budget|build a budget|faire un budget)\b", re.I),
     "budget_building"),
    (re.compile(r"\b(debt vs savings|dette ou epargne|dette ou épargne|debt or savings)\b", re.I),
     "debt_vs_savings"),
    (re.compile(r"\b(njangi payout|payout|tour de njangi)\b", re.I),
     "njangi_payout_explained"),
    (re.compile(r"\b(mobile money safety|momo safety|securite mobile money|sécurité mobile money)\b", re.I),
     "mobile_money_safety"),
    (re.compile(r"\b(invest|investment|investir|investissement)\b", re.I),
     "investment_basics"),
)


def detect_topic_key(message: str) -> Optional[str]:
    for pat, key in _TOPIC_KEYS:
        if pat.search(message):
            return key
    return None


# ─── Public entry ──────────────────────────────────────────────────

async def fetch_context(
    db: AsyncSession,
    user: User,
    category: CategoryT,
) -> dict:
    """Return a structured context dict scoped to the user's question."""
    base = {
        "user": {
            "id":                  str(user.id),
            "full_name":           user.full_name,
            "city":                user.city,
            "income_bracket":      user.income_bracket,
            "income_midpoint":     income_midpoint(user.income_bracket),
            "preferred_language":  user.preferred_language or "en",
        },
    }

    if category == "expenses":
        base["expenses"] = await _fetch_expenses_context(db, str(user.id))
    elif category == "savings":
        base["savings"] = await _fetch_savings_context(db, str(user.id))
    elif category == "njangi":
        base["njangi"] = await _fetch_njangi_context(db, str(user.id))
    elif category == "health":
        base["expenses"] = await _fetch_expenses_context(db, str(user.id))
        base["savings"]  = await _fetch_savings_context(db, str(user.id))
        base["njangi"]   = await _fetch_njangi_context(db, str(user.id))
    elif category == "education":
        base["education"] = await _fetch_education_context(user)

    return base
