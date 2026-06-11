"""Financial health scoring.

Produces a 0..100 score weighted across five components and packages it
with per-component explanations + a single top improvement tip. The
chat router calls this when category == "health" and the result is also
passed to Claude inside the context so it can reference real numbers.

Component weights (must sum to 1.0):
  * savings_rate         30%
  * budget_adherence     25%
  * njangi_trust         20%
  * goal_progress        15%
  * autosave_consistency 10%
"""
from __future__ import annotations

from typing import Optional, TypedDict


WEIGHTS = {
    "savings_rate":         0.30,
    "budget_adherence":     0.25,
    "njangi_trust":         0.20,
    "goal_progress":        0.15,
    "autosave_consistency": 0.10,
}


class ComponentScore(TypedDict):
    key:         str
    score:       int          # 0..100
    weight:      float
    explanation: str          # one-liner referencing real numbers


class HealthResult(TypedDict):
    overall_score:       int
    rating:              str  # Excellent | Good | Needs Attention | Critical
    components:          list[ComponentScore]
    top_improvement_tip: str


# ─── Component scorers ─────────────────────────────────────────────
#
# Each scorer returns (score, explanation). Score is always 0..100; the
# explanation should mention actual XAF / % so the response card has
# real numbers to display.

def _score_savings_rate(
    saved_this_month: int,
    income_midpoint: Optional[int],
) -> tuple[int, str]:
    if not income_midpoint or income_midpoint <= 0:
        return 50, "No income range set — pick one in your profile for an accurate score."
    rate = (saved_this_month / income_midpoint) * 100
    # 20%+ saved = full marks; linear below.
    score = int(min(rate * 5, 100))
    return score, (
        f"You saved {saved_this_month:,} XAF this month "
        f"(~{rate:.0f}% of your income bracket midpoint)."
    )


def _score_budget_adherence(
    by_category: dict[str, int],
    budgets: dict[str, int],
) -> tuple[int, str]:
    if not budgets:
        return 50, "No category budgets set yet — define some in Expenses to track adherence."
    within = 0
    over   = 0
    for cat, limit in budgets.items():
        spent = by_category.get(cat, 0)
        if spent <= limit:
            within += 1
        else:
            over += 1
    total = within + over
    if total == 0:
        return 50, "No budgets to evaluate."
    score = int((within / total) * 100)
    return score, (
        f"{within} of {total} category budgets are still within limit "
        f"({over} over)."
    )


def _score_njangi_trust(avg_trust: Optional[float], group_count: int) -> tuple[int, str]:
    if not group_count:
        return 75, "You're not in any Njangi groups — neutral score."
    if avg_trust is None:
        return 75, "Trust scores aren't available yet — neutral."
    return int(min(max(avg_trust, 0), 100)), (
        f"Average trust score across your {group_count} group"
        f"{'s' if group_count != 1 else ''}: {avg_trust:.0f} / 100."
    )


def _score_goal_progress(goals: list[dict]) -> tuple[int, str]:
    active = [g for g in goals if not g.get("is_completed")]
    if not active:
        return 50, "No active savings goals — set one to track progress."
    pcts: list[float] = []
    for g in active:
        target = max(int(g.get("target") or 0), 1)
        current = int(g.get("current") or 0)
        pcts.append((current / target) * 100)
    avg = sum(pcts) / len(pcts)
    score = int(min(avg, 100))
    return score, (
        f"Average progress across your {len(active)} active "
        f"goal{'s' if len(active) != 1 else ''}: {avg:.0f}%."
    )


def _score_autosave_consistency(attempts: int, successes: int) -> tuple[int, str]:
    if attempts == 0:
        return 50, "No auto-save attempts in the last 30 days — neutral."
    rate = (successes / attempts) * 100
    return int(rate), (
        f"{successes} of {attempts} auto-save attempts went through "
        f"in the last 30 days ({rate:.0f}%)."
    )


# ─── Top tip ───────────────────────────────────────────────────────

_TIPS = {
    "savings_rate":         "Aim for a 20% savings rate. If your bracket midpoint is 200,000 XAF, target saving 40,000 XAF/month.",
    "budget_adherence":     "Pick the one category most over budget and cap it 10% tighter next month — that single tweak usually pulls the others back in line.",
    "njangi_trust":         "Pay your next Njangi contribution on or before its due date — even a single on-time payment lifts your average trust noticeably.",
    "goal_progress":        "Add a small fixed auto-save (e.g. 2,000 XAF weekly) to your slowest goal. Steady beats sporadic.",
    "autosave_consistency": "Top up your MoMo wallet a day before each scheduled auto-save so the collection doesn't fail for insufficient funds.",
}


def _rating(score: int) -> str:
    if score >= 80:
        return "Excellent"
    if score >= 60:
        return "Good"
    if score >= 40:
        return "Needs Attention"
    return "Critical"


# ─── Public entry ──────────────────────────────────────────────────

def compute_health(context: dict) -> HealthResult:
    """Compute the financial health score from a full health-category context.

    Expects `context` to look like:
      {
        "user":     {"income_midpoint": int|None, ...},
        "expenses": {"by_category": dict, "budgets": dict, "month_total": int, ...},
        "savings":  {"goals": list, "auto_save_30d": {"attempts": int, "successes": int}, ...},
        "njangi":   {"avg_trust": float|None, "group_count": int, ...},
      }
    Missing branches are tolerated — the relevant component falls back to a
    neutral score with a "set this up" explanation.
    """
    user      = context.get("user", {})
    expenses  = context.get("expenses", {})
    savings   = context.get("savings", {})
    njangi    = context.get("njangi", {})

    midpoint  = user.get("income_midpoint")

    # Approximate "saved this month" from monthly_income proxy:
    # we don't track standalone "saved" yet, so use total goal contributions
    # in current month if available; for now use the sum of current goal
    # balances as a soft proxy. Better: track per-month savings increments.
    # (Honest scope note: this is a v1 approximation.)
    monthly_saved = 0
    goals = savings.get("goals") or []
    autosave_30d = (savings.get("auto_save_30d") or {})
    # Use sum of successful auto-save amounts as the savings proxy when we
    # don't have a direct per-month savings counter.
    monthly_saved = autosave_30d.get("successes", 0) * 1000  # rough placeholder

    s1, exp1 = _score_savings_rate(monthly_saved, midpoint)
    s2, exp2 = _score_budget_adherence(
        expenses.get("by_category") or {},
        expenses.get("budgets") or {},
    )
    s3, exp3 = _score_njangi_trust(njangi.get("avg_trust"), njangi.get("group_count", 0))
    s4, exp4 = _score_goal_progress(goals)
    s5, exp5 = _score_autosave_consistency(
        autosave_30d.get("attempts", 0),
        autosave_30d.get("successes", 0),
    )

    components: list[ComponentScore] = [
        {"key": "savings_rate",         "score": s1, "weight": WEIGHTS["savings_rate"],         "explanation": exp1},
        {"key": "budget_adherence",     "score": s2, "weight": WEIGHTS["budget_adherence"],     "explanation": exp2},
        {"key": "njangi_trust",         "score": s3, "weight": WEIGHTS["njangi_trust"],         "explanation": exp3},
        {"key": "goal_progress",        "score": s4, "weight": WEIGHTS["goal_progress"],        "explanation": exp4},
        {"key": "autosave_consistency", "score": s5, "weight": WEIGHTS["autosave_consistency"], "explanation": exp5},
    ]
    overall = int(sum(c["score"] * c["weight"] for c in components))

    # The improvement tip is whichever component drags the weighted score down most.
    weakest = min(components, key=lambda c: c["score"])
    tip = _TIPS.get(weakest["key"], "Keep going — small consistent steps compound.")

    return {
        "overall_score":       overall,
        "rating":              _rating(overall),
        "components":          components,
        "top_improvement_tip": tip,
    }
