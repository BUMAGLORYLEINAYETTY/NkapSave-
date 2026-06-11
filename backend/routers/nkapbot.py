"""NkapBot chat endpoint — RAG over real user data, answered by Claude."""
from __future__ import annotations

import logging
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.config import settings
from core.database import get_db
from core.security import get_current_user
from data.education_topics import get_topic
from models.user import User
from services.financial_health_service import compute_health
from services.nkapbot_context_service import (
    detect_category,
    detect_topic_key,
    fetch_context,
)
from services.prompt_builder import build_system_prompt
from services.rag_service import index_status, semantic_search
from services.spending_pattern_service import detect_patterns

# Anthropic SDK is optional — if not installed the endpoint still works,
# returning the fallback message and the structured context.
try:
    from anthropic import AsyncAnthropic
    _ANTHROPIC_IMPORT_ERROR: Optional[str] = None
except Exception as e:  # pragma: no cover
    AsyncAnthropic = None  # type: ignore[assignment]
    _ANTHROPIC_IMPORT_ERROR = str(e)


logger = logging.getLogger("nkapsave.nkapbot")
router = APIRouter(prefix="/nkapbot", tags=["NkapBot"])


# ─── Request / response models ─────────────────────────────────────

class ChatTurn(BaseModel):
    role:    str = Field(pattern="^(user|assistant)$")
    content: str


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    conversation_history: list[ChatTurn] = Field(default_factory=list)
    enabled_features: list[str] = Field(default_factory=list)


class ChatResponse(BaseModel):
    message:   str
    category:  str
    card_type: str   # none | health_score | spending_breakdown | goal_projection
                     #      | education | monthly_comparison | pattern_alert
    card_data: dict[str, Any] = Field(default_factory=dict)


# ─── Helpers ───────────────────────────────────────────────────────

def _fallback_message(language: str) -> str:
    if language == "fr":
        return ("Je n'arrive pas à atteindre l'IA en ce moment. "
                "Vos chiffres sont chargés, mais l'analyse détaillée est "
                "indisponible — réessayez dans quelques instants.")
    if language in ("pidgin", "pcm"):
        return ("AI no dey reach me right now. I get your numbers, but the deep "
                "analysis no fit work — try again small.")
    return ("I can't reach the AI right now. Your numbers loaded fine, but the "
            "deeper analysis isn't available — try again in a moment.")


def _pick_card_type(
    category: str,
    has_health: bool,
    has_patterns: bool,
    has_topic: bool,
    monthly_compare: bool,
    goal_projection: bool,
) -> str:
    if has_health:    return "health_score"
    if has_topic:     return "education"
    if monthly_compare: return "monthly_comparison"
    if goal_projection: return "goal_projection"
    if has_patterns:  return "pattern_alert"
    if category == "expenses": return "spending_breakdown"
    return "none"


def _spending_breakdown_card(expenses: dict) -> dict:
    by_cat = expenses.get("by_category") or {}
    budgets = expenses.get("budgets") or {}
    bars = []
    for cat, amt in sorted(by_cat.items(), key=lambda kv: -kv[1]):
        limit = budgets.get(cat)
        bars.append({
            "category": cat,
            "amount":   int(amt),
            "limit":    int(limit) if limit is not None else None,
            "over":     bool(limit is not None and amt > limit),
        })
    return {
        "month_total":      int(expenses.get("month_total") or 0),
        "prev_month_total": int(expenses.get("prev_month_total") or 0),
        "bars":             bars,
    }


def _monthly_compare_card(expenses: dict) -> dict:
    by_cat   = expenses.get("by_category") or {}
    prev     = expenses.get("prev_by_category") or {}
    top_cat  = max(by_cat, key=lambda k: by_cat[k]) if by_cat else None
    top_prev = max(prev, key=lambda k: prev[k]) if prev else None
    return {
        "this_month": {
            "expenses":     int(expenses.get("month_total") or 0),
            "top_category": top_cat,
        },
        "last_month": {
            "expenses":     int(expenses.get("prev_month_total") or 0),
            "top_category": top_prev,
        },
    }


def _goal_projection_card(savings: dict) -> Optional[dict]:
    goals = [g for g in (savings.get("goals") or []) if not g.get("is_completed")]
    if not goals:
        return None
    # Pair every goal with its plan, then pick the one furthest from done.
    plans_by_goal = {p["goal_id"]: p for p in (savings.get("plans") or [])}
    pick = None
    pick_remaining = -1
    for g in goals:
        remaining = max(int(g["target"]) - int(g["current"]), 0)
        if remaining > pick_remaining:
            pick_remaining = remaining
            pick = g
    if pick is None:
        return None
    plan = plans_by_goal.get(pick["id"])
    per_period: Optional[int] = int(plan["amount"]) if plan else None
    freq = plan["frequency"] if plan else "weekly"
    period_days = {"daily": 1, "weekly": 7, "monthly": 30}.get(freq, 7)
    weeks_at_current = None
    weeks_at_bumped = None
    bumped_amount = None
    if per_period and per_period > 0:
        periods_left = max((pick["target"] - pick["current"] + per_period - 1) // per_period, 0)
        weeks_at_current = max(round(periods_left * period_days / 7), 1)
        bumped_amount = int(per_period * 1.5)
        periods_left_b = max((pick["target"] - pick["current"] + bumped_amount - 1) // bumped_amount, 0)
        weeks_at_bumped = max(round(periods_left_b * period_days / 7), 1)
    return {
        "name":             pick["name"],
        "emoji":            pick.get("emoji") or "🎯",
        "current":          int(pick["current"]),
        "target":           int(pick["target"]),
        "per_period":       per_period,
        "frequency":        freq,
        "weeks_at_current": weeks_at_current,
        "bumped_amount":    bumped_amount,
        "weeks_at_bumped":  weeks_at_bumped,
    }


# ─── Endpoint ──────────────────────────────────────────────────────

@router.get("/diagnose")
async def diagnose() -> dict:
    """Reports whether the Claude integration is reachable end-to-end.

    Intentionally unauthenticated — reveals no user data, only whether
    the Anthropic SDK is installed, whether a key is configured, and the
    result of one tiny test call. Safe for local debugging; remove or
    gate behind a dev-only flag before going to production.

    Returns sdk_installed, key_set, model, and either ok=True with the
    model's actual reply to a 1-token ping, or ok=False with the real
    exception string. Useful for surfacing "can't reach the AI" causes
    without needing to read uvicorn logs.
    """
    info: dict[str, object] = {
        "sdk_installed": AsyncAnthropic is not None,
        "sdk_import_error": _ANTHROPIC_IMPORT_ERROR,
        "key_set":       bool(settings.ANTHROPIC_API_KEY),
        "key_prefix":    (settings.ANTHROPIC_API_KEY or "")[:7] + "..."
                         if settings.ANTHROPIC_API_KEY else None,
        "model":         settings.ANTHROPIC_MODEL,
        "max_tokens":    settings.ANTHROPIC_MAX_TOKENS,
    }
    if AsyncAnthropic is None or not settings.ANTHROPIC_API_KEY:
        info["ok"] = False
        info["error"] = ("SDK not installed" if AsyncAnthropic is None
                         else "ANTHROPIC_API_KEY not set in .env")
        return info
    try:
        client = AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
        resp = await client.messages.create(
            model=settings.ANTHROPIC_MODEL,
            max_tokens=16,
            messages=[{"role": "user", "content": "Reply with just: ok"}],
        )
        text = ""
        for block in resp.content:
            t = getattr(block, "text", None)
            if t:
                text += t
        info["ok"] = True
        info["sample_reply"] = text.strip()[:120]
    except Exception as e:
        info["ok"] = False
        info["error"] = f"{type(e).__name__}: {e}"
    return info


@router.get("/kb/status")
async def kb_status() -> dict:
    """Report the semantic-RAG knowledge index: which embedding provider is
    active, how many passages are indexed, and whether the index is current.

    Unauthenticated by design — exposes no user data, only corpus/provider
    metadata. Handy for confirming embeddings are wired up. Calling it also
    lazily builds the index if it's missing or stale."""
    status = await index_status()
    if not status.get("up_to_date"):
        from services.rag_service import build_index
        status["build"] = await build_index(force=False)
        status = await index_status()
    return status


@router.post("/chat", response_model=ChatResponse)
async def chat(
    body: ChatRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ChatResponse:
    """Run one turn of the NkapBot conversation."""
    # 1. Load user
    user_id = current_user["user_id"]
    res = await db.execute(select(User).where(User.id == user_id))
    user = res.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    language = user.preferred_language or "en"

    # 2. Detect category + topic
    category = detect_category(body.message)
    topic_key = detect_topic_key(body.message) if category == "education" else None

    # 3. Pull RAG context
    context = await fetch_context(db, user, category)

    # 4. Augment context with computed slices
    if category == "health" or topic_key is None and category in ("expenses", "savings", "njangi", "health"):
        pass  # placeholder for symmetry
    if category == "health":
        context["health"] = compute_health(context)
    if category == "expenses":
        context["patterns"] = detect_patterns(context.get("expenses") or {})

    topic = None
    if category == "education" and topic_key:
        midpoint = (context.get("user") or {}).get("income_midpoint")
        topic = get_topic(topic_key, language=language, income_midpoint=midpoint)

    # 4b. Semantic retrieval — pull the knowledge-base passages most relevant
    #     to the raw question by meaning (not keywords). This grounds Claude on
    #     concepts the structured slices above don't cover (Njangi defaults,
    #     MoMo fraud, inflation, …). Failures never break the turn.
    if settings.RAG_ENABLED:
        knowledge = await semantic_search(body.message, language=language)
        if knowledge:
            context["knowledge"] = knowledge

    # 5. Build the prompt + call Claude
    system_prompt = build_system_prompt(
        context, category, body.enabled_features or None, topic=topic
    )
    messages: list[dict[str, str]] = []
    for turn in body.conversation_history[-10:]:   # cap history at last 10 turns
        messages.append({"role": turn.role, "content": turn.content})
    messages.append({"role": "user", "content": body.message})

    reply_text = await _call_claude(system_prompt, messages, language)

    # 6. Pick card_type + assemble structured payload
    monthly_compare_keywords = ("compare", "this month", "last month", "ce mois", "mois dernier")
    wants_compare = any(k in body.message.lower() for k in monthly_compare_keywords)
    goal_keywords = ("when do i hit", "when will i reach", "quand vais-je", "weeks to go", "reach my goal")
    wants_projection = category == "savings" and any(k in body.message.lower() for k in goal_keywords)

    has_patterns = bool((context.get("patterns") or []) and category == "expenses")
    has_health   = "health" in context
    card_type = _pick_card_type(
        category,
        has_health=has_health,
        has_patterns=has_patterns,
        has_topic=topic is not None,
        monthly_compare=wants_compare and category == "expenses",
        goal_projection=wants_projection,
    )

    card_data: dict[str, Any] = {}
    if card_type == "health_score":
        card_data = context["health"]
    elif card_type == "education" and topic is not None:
        card_data = topic
    elif card_type == "monthly_comparison":
        card_data = _monthly_compare_card(context.get("expenses") or {})
    elif card_type == "goal_projection":
        proj = _goal_projection_card(context.get("savings") or {})
        if proj is not None:
            card_data = proj
        else:
            card_type = "none"
    elif card_type == "pattern_alert":
        card_data = {"patterns": context.get("patterns") or []}
    elif card_type == "spending_breakdown":
        card_data = _spending_breakdown_card(context.get("expenses") or {})

    return ChatResponse(
        message=reply_text,
        category=category,
        card_type=card_type,
        card_data=card_data,
    )


# ─── Claude call ───────────────────────────────────────────────────

async def _call_claude(
    system_prompt: str,
    messages: list[dict[str, str]],
    language: str,
) -> str:
    """Call Anthropic. Returns a fallback string on any failure so the
    user never sees a raw error from the SDK."""
    if AsyncAnthropic is None:
        logger.warning("nkapbot: anthropic SDK missing (%s)", _ANTHROPIC_IMPORT_ERROR)
        return _fallback_message(language)
    if not settings.ANTHROPIC_API_KEY:
        logger.warning("nkapbot: ANTHROPIC_API_KEY not configured")
        return _fallback_message(language)

    try:
        client = AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
        resp = await client.messages.create(
            model=settings.ANTHROPIC_MODEL,
            max_tokens=settings.ANTHROPIC_MAX_TOKENS,
            system=system_prompt,
            messages=messages,
        )
        # The Anthropic SDK returns a list of content blocks; concatenate text.
        parts: list[str] = []
        for block in resp.content:
            text = getattr(block, "text", None)
            if text:
                parts.append(text)
        if not parts:
            return _fallback_message(language)
        return "\n".join(parts).strip()
    except Exception as e:
        logger.exception("nkapbot: Claude call failed: %s", e)
        return _fallback_message(language)
