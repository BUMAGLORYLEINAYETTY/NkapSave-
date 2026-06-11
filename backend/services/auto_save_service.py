"""Auto-save orchestration.

Public entry points:

  * run_due_plans(db)
        Picks every active AutoSavePlan with next_run_at <= now and initiates
        a MoMo Collection request. Called by the APScheduler tick.

  * settle_pending(db)
        Polls MTN for PENDING transactions and credits the goal on SUCCESS.
        Called by the same tick.

  * create_plan / update_plan / cancel_plan
        Used by HTTP endpoints. Kept here so business rules (goal must exist,
        wallet must be verified, etc.) stay in one place.

Frequencies:
  daily   -> next run 24h later
  weekly  -> next run 7d later
  monthly -> next run ~30d later (calendar-aware month-step would be nicer;
             30 days is fine for v1 and matches what the user picked).
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.momo import AutoSavePlan, MoMoConnection, MoMoTransaction
from models.savings import SavingsGoal
from models.user import User
from services import momo_provider
from services.notification_service import notify_user

logger = logging.getLogger("nkapsave.autosave")

# After this many back-to-back failed pulls we stop scheduling fresh
# requests against the wallet. The most common cause is an empty MoMo
# balance — retrying every period just spams the user with failure pushes.
# Keep low enough to be noticeable (3 ≈ 3 weeks for a weekly plan), but
# high enough that one bad PIN entry or a transient MTN outage doesn't
# pause anyone immediately.
MAX_CONSECUTIVE_FAILURES = 3

# Maps the raw `reason` string MTN/Campay returns into:
#   (category, human_message)
# Category is used by [_notify_failure] to pick the right push title and
# decide whether the failure is "structural" (no money / wrong PIN) or
# transient (network blip). When we don't recognise the reason we fall
# back to a generic message that still names the amount.
_REASON_MAP: dict[str, tuple[str, str]] = {
    "NOT_ENOUGH_FUNDS":   ("low_balance",
        "Your MoMo balance was too low for today's auto-save."),
    "INSUFFICIENT_FUNDS": ("low_balance",
        "Your MoMo balance was too low for today's auto-save."),
    "PAYER_LIMIT_REACHED": ("low_balance",
        "You've hit your MoMo daily limit. Auto-save couldn't go through."),
    "EXPIRED":            ("not_approved",
        "You didn't approve the MoMo prompt in time, so the deduction was cancelled."),
    "REJECTED":           ("not_approved",
        "You rejected the MoMo prompt, so nothing was deducted."),
    "INVALID_USER_PIN":   ("pin_problem",
        "Wrong MoMo PIN. We didn't take any money."),
    "WRONG_PIN":          ("pin_problem",
        "Wrong MoMo PIN. We didn't take any money."),
    "PAYER_NOT_FOUND":    ("number_problem",
        "Your linked MoMo number couldn't be reached. Re-link it in Settings."),
    "INVALID_NUMBER":     ("number_problem",
        "Your linked MoMo number isn't valid. Re-link it in Settings."),
}


def _describe_reason(raw: str | None, amount: float) -> tuple[str, str]:
    """Turn a Campay reason code into a (category, friendly message).

    Unknown reasons get a generic "we couldn't take X today" body so the
    user always sees a real amount, not "no reason given".
    """
    if raw:
        key = raw.strip().upper()
        if key in _REASON_MAP:
            return _REASON_MAP[key]
    return ("unknown",
        f"We couldn't take {amount:,.0f} XAF from your MoMo today.")


_FREQ_DELTA = {
    "daily":   timedelta(days=1),
    "weekly":  timedelta(days=7),
    "monthly": timedelta(days=30),
}

_MILESTONES = (25, 50, 75, 100)


def _advance(plan: AutoSavePlan) -> datetime:
    delta = _FREQ_DELTA.get(plan.frequency, _FREQ_DELTA["monthly"])
    return datetime.utcnow() + delta


# ─── Plan CRUD (used by HTTP layer) ───────────────────────────────

async def create_plan(
    db: AsyncSession, *, user_id: str, goal_id: str,
    percent: int, frequency: str, amount: float,
    reminder_enabled: bool = True,
) -> AutoSavePlan:
    # One plan per goal — enforce.
    existing = await db.execute(
        select(AutoSavePlan).where(AutoSavePlan.goal_id == goal_id)
    )
    if existing.scalar_one_or_none():
        raise ValueError("This goal already has an auto-save plan.")

    plan = AutoSavePlan(
        user_id=user_id,
        goal_id=goal_id,
        amount=amount,
        percent=percent,
        frequency=frequency,
        active=True,
        reminder_enabled=reminder_enabled,
        next_run_at=datetime.utcnow() + _FREQ_DELTA.get(frequency, _FREQ_DELTA["monthly"]),
    )
    db.add(plan)
    await db.flush()
    return plan


async def update_plan(
    db: AsyncSession, plan: AutoSavePlan, *,
    percent: Optional[int] = None,
    frequency: Optional[str] = None,
    amount: Optional[float] = None,
    active: Optional[bool] = None,
    reminder_enabled: Optional[bool] = None,
) -> AutoSavePlan:
    if percent is not None:
        plan.percent = percent
    if amount is not None:
        plan.amount = amount
    if frequency is not None and frequency != plan.frequency:
        plan.frequency = frequency
        # Recompute next_run_at from the new cadence, starting from now.
        plan.next_run_at = datetime.utcnow() + _FREQ_DELTA.get(frequency, _FREQ_DELTA["monthly"])
    if active is not None:
        plan.active = active
        if active and plan.next_run_at < datetime.utcnow():
            plan.next_run_at = datetime.utcnow() + _FREQ_DELTA.get(plan.frequency, _FREQ_DELTA["monthly"])
    if reminder_enabled is not None:
        plan.reminder_enabled = reminder_enabled
    await db.flush()
    return plan


# ─── Scheduler tick ────────────────────────────────────────────────

async def run_due_plans(db: AsyncSession) -> dict:
    """Initiate a Collection for every plan whose next_run_at has passed."""
    if not momo_provider.is_configured():
        return {"initiated": 0, "skipped_reason": "momo_not_configured"}

    now = datetime.utcnow()
    res = await db.execute(
        select(AutoSavePlan).where(
            AutoSavePlan.active == True,        # noqa: E712
            AutoSavePlan.next_run_at <= now,
        )
    )
    plans = res.scalars().all()

    initiated = 0
    for plan in plans:
        conn_res = await db.execute(
            select(MoMoConnection).where(
                MoMoConnection.user_id == plan.user_id,
                MoMoConnection.verified == True,    # noqa: E712
            )
        )
        conn = conn_res.scalar_one_or_none()
        if not conn:
            # No verified wallet — push the plan one period out and continue.
            plan.next_run_at = _advance(plan)
            logger.warning("autosave: plan %s has no verified MoMo link; deferring", plan.id)
            continue

        goal_res = await db.execute(select(SavingsGoal).where(SavingsGoal.id == plan.goal_id))
        goal = goal_res.scalar_one_or_none()
        if not goal or goal.is_completed:
            plan.active = False
            continue

        external_id = uuid.uuid4().hex[:32]
        try:
            ref_id = momo_provider.request_to_pay(
                phone=conn.phone,
                amount=int(plan.amount),
                external_id=external_id,
                payer_message="NkapSave auto-save",
                payee_note=f"Auto-save toward goal {goal.name}"[:160],
            )
        except (momo_provider.MoMoApiError, momo_provider.MoMoNotConfigured) as e:
            logger.error("autosave: requestToPay failed plan=%s: %s", plan.id, e)
            plan.consecutive_failures += 1
            plan.last_run_at = now
            plan.next_run_at = _advance(plan)
            continue

        db.add(MoMoTransaction(
            user_id=plan.user_id,
            plan_id=plan.id,
            goal_id=goal.id,
            reference_id=ref_id,
            external_id=external_id,
            amount=plan.amount,
            currency="XAF",
            phone=conn.phone,
            status="PENDING",
        ))
        plan.last_run_at = now
        plan.next_run_at = _advance(plan)
        initiated += 1

    await db.flush()
    return {"initiated": initiated}


async def settle_pending(db: AsyncSession) -> dict:
    """Poll MTN for the status of every PENDING transaction and credit goals."""
    if not momo_provider.is_configured():
        return {"settled": 0}

    res = await db.execute(
        select(MoMoTransaction).where(MoMoTransaction.status == "PENDING")
    )
    pending = res.scalars().all()

    settled = 0
    for tx in pending:
        try:
            data = momo_provider.get_status(tx.reference_id)
        except (momo_provider.MoMoApiError, momo_provider.MoMoNotConfigured) as e:
            logger.warning("autosave: get_status failed ref=%s: %s", tx.reference_id, e)
            continue

        status = (data.get("status") or "PENDING").upper()
        if status == "PENDING":
            continue

        tx.status = status
        tx.completed_at = datetime.utcnow()
        tx.reason = data.get("reason")

        if status == "SUCCESSFUL":
            await _credit_goal(db, tx)
            # Plan's failure streak resets on success.
            plan_res = await db.execute(
                select(AutoSavePlan).where(AutoSavePlan.id == tx.plan_id)
            )
            plan = plan_res.scalar_one_or_none()
            if plan:
                plan.consecutive_failures = 0
        elif status == "FAILED":
            plan_res = await db.execute(
                select(AutoSavePlan).where(AutoSavePlan.id == tx.plan_id)
            )
            plan = plan_res.scalar_one_or_none()
            paused_now = False
            if plan:
                plan.consecutive_failures += 1
                # Stop scheduling more pulls once we've crossed the
                # threshold. The user has to re-enable the plan from
                # the Savings screen — that's the moment to top up.
                if plan.consecutive_failures >= MAX_CONSECUTIVE_FAILURES \
                        and plan.active:
                    plan.active = False
                    paused_now = True
                    logger.warning(
                        "autosave: plan %s auto-paused after %d failures",
                        plan.id, plan.consecutive_failures)
            await _notify_failure(db, tx, paused=paused_now)
        settled += 1

    await db.flush()
    return {"settled": settled}


# ─── Helpers ───────────────────────────────────────────────────────

async def _credit_goal(db: AsyncSession, tx: MoMoTransaction) -> None:
    goal_res = await db.execute(select(SavingsGoal).where(SavingsGoal.id == tx.goal_id))
    goal: Optional[SavingsGoal] = goal_res.scalar_one_or_none()
    if not goal:
        return

    before_pct = (goal.current / goal.target * 100) if goal.target else 0
    goal.current += tx.amount
    if goal.current >= goal.target:
        goal.current = goal.target
        goal.is_completed = True
        goal.is_locked = False
    after_pct = (goal.current / goal.target * 100) if goal.target else 0

    await _maybe_notify_milestone(db, tx, goal, before_pct, after_pct)


async def _maybe_notify_milestone(
    db: AsyncSession, tx: MoMoTransaction, goal: SavingsGoal,
    before_pct: float, after_pct: float,
) -> None:
    plan_res = await db.execute(
        select(AutoSavePlan).where(AutoSavePlan.id == tx.plan_id)
    )
    plan = plan_res.scalar_one_or_none()
    if not plan:
        return

    crossed = next(
        (m for m in _MILESTONES
         if before_pct < m <= after_pct and m > plan.last_milestone_notified),
        None,
    )
    if crossed is None:
        return

    plan.last_milestone_notified = crossed
    title = f"{goal.emoji or '🎯'} {crossed}% of {goal.name} saved"
    if crossed == 100:
        body = (
            f"You hit your target for {goal.name}! "
            f"The funds are unlocked — open NkapSave to use them."
        )
    else:
        body = (
            f"Great progress on {goal.name}: {goal.current:,.0f} of "
            f"{goal.target:,.0f} XAF saved."
        )
    await notify_user(
        db, user_id=str(tx.user_id),
        title=title, body=body,
        category="savings_milestone",
        deep_link=f"/savings/{goal.id}",
    )


async def _notify_failure(
        db: AsyncSession,
        tx: MoMoTransaction,
        *,
        paused: bool = False) -> None:
    """Push a friendly failure notification.

    The title and follow-up sentence depend on:
      * the [category] resolved from the raw MTN reason — so
        "low_balance" reads as "Top up your wallet…", not
        "Reason: NOT_ENOUGH_FUNDS";
      * whether [paused] is True, meaning we've already disabled the
        plan because the user has hit MAX_CONSECUTIVE_FAILURES.
    """
    category, message = _describe_reason(tx.reason, tx.amount)

    if paused:
        title  = "Auto-save paused"
        follow = ("We tried "
                  f"{MAX_CONSECUTIVE_FAILURES} times and stopped "
                  "scheduling more deductions. Re-enable it from "
                  "the Savings screen once you've topped up.")
    elif category == "low_balance":
        title  = "Top up your MoMo"
        follow = "We'll try again on the next scheduled date."
    elif category == "not_approved":
        title  = "Auto-save was cancelled"
        follow = "We'll try again on the next scheduled date."
    elif category == "pin_problem":
        title  = "MoMo PIN issue"
        follow = "Check your PIN and we'll try again on the next date."
    elif category == "number_problem":
        title  = "MoMo number unreachable"
        follow = "Re-link your wallet in Settings to fix this."
    else:
        title  = "Auto-save couldn't go through"
        follow = "We'll try again on the next scheduled date."

    await notify_user(
        db, user_id=str(tx.user_id),
        title=title,
        body=f"{message} {follow}",
        category="autosave_paused" if paused else "autosave_failed",
        deep_link="/savings",
    )


# ─── Pre-deduction reminders ──────────────────────────────────────
#
# Fires up to once per `next_run_at`. The fields `reminder_enabled` and
# `last_reminder_for_run_at` on AutoSavePlan are the two knobs:
#
#   * reminder_enabled  : user opted in when creating/editing the plan
#   * last_reminder_for_run_at : the `next_run_at` value we last reminded
#     about. When the plan advances to the next period, this becomes stale
#     and the next reminder fires automatically.
#
# Anchor window: deduction is happening within REMINDER_LEAD_HOURS hours.

REMINDER_LEAD_HOURS = 24


async def send_auto_save_reminders(db: AsyncSession) -> dict:
    """Send a 'deduction tomorrow' push for every plan due within the lead window.

    Returns aggregate counts. Idempotent per `next_run_at` value: once we send
    a reminder for a given run, we won't re-send until the plan advances.
    """
    now = datetime.utcnow()
    cutoff = now + timedelta(hours=REMINDER_LEAD_HOURS)

    res = await db.execute(
        select(AutoSavePlan).where(
            AutoSavePlan.active == True,             # noqa: E712
            AutoSavePlan.reminder_enabled == True,   # noqa: E712
            AutoSavePlan.next_run_at > now,
            AutoSavePlan.next_run_at <= cutoff,
        )
    )
    plans = res.scalars().all()

    sent = 0
    skipped_already_reminded = 0
    skipped_no_goal = 0
    for plan in plans:
        if (
            plan.last_reminder_for_run_at is not None
            and plan.last_reminder_for_run_at == plan.next_run_at
        ):
            skipped_already_reminded += 1
            continue

        goal_res = await db.execute(
            select(SavingsGoal).where(SavingsGoal.id == plan.goal_id)
        )
        goal = goal_res.scalar_one_or_none()
        if goal is None or goal.is_completed:
            skipped_no_goal += 1
            continue

        hours_left = max(int((plan.next_run_at - now).total_seconds() // 3600), 1)
        if hours_left <= 1:
            when = "in less than an hour"
        elif hours_left <= 24:
            when = f"in about {hours_left} hours"
        else:
            when = f"in {hours_left // 24} day{'s' if hours_left // 24 != 1 else ''}"

        await notify_user(
            db, user_id=str(plan.user_id),
            title="Auto-save coming up",
            body=(
                f"{plan.amount:,.0f} XAF will be moved to "
                f"{goal.emoji} {goal.name} {when}. "
                "Make sure your wallet has the funds."
            ),
            category="autosave_reminder",
            deep_link=f"/savings/{goal.id}",
        )
        plan.last_reminder_for_run_at = plan.next_run_at
        sent += 1

    await db.flush()
    return {
        "sent": sent,
        "skipped_already_reminded": skipped_already_reminded,
        "skipped_no_goal": skipped_no_goal,
    }
