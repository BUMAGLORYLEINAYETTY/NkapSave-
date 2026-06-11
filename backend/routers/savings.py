from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from datetime import datetime, timedelta
from core.database import get_db
from core.security import get_current_user
from models.user import User
from models.savings import SavingsGoal
from models.savings_schemas import (
    CreateGoalRequest, AddFundsRequest,
    AutoSaveUpdateRequest, GoalOut, SavingsResponse,
)
from models.momo import AutoSavePlan, MoMoConnection, MoMoTransaction
from models.momo_schemas import (
    CreateAutoSavePlanRequest, UpdateAutoSavePlanRequest,
    AutoSavePlanOut, AutoSavePlanDetail, MoMoTransactionOut,
    SavingsInsightsOut, UpcomingRunOut, ActivityItemOut, AllocationItemOut,
)
from services import auto_save_service

router = APIRouter(prefix="/savings", tags=["Savings"])


def _plan_out(p: AutoSavePlan) -> AutoSavePlanOut:
    return AutoSavePlanOut(
        id=str(p.id),
        goal_id=str(p.goal_id),
        percent=p.percent,
        amount=p.amount,
        frequency=p.frequency,
        active=p.active,
        next_run_at=p.next_run_at,
        last_run_at=p.last_run_at,
        consecutive_failures=p.consecutive_failures,
        reminder_enabled=p.reminder_enabled,
    )


def _tx_out(t: MoMoTransaction) -> MoMoTransactionOut:
    return MoMoTransactionOut(
        id=str(t.id),
        reference_id=t.reference_id,
        amount=t.amount,
        currency=t.currency,
        status=t.status,
        reason=t.reason,
        initiated_at=t.initiated_at,
        completed_at=t.completed_at,
    )


async def _load_user_goal(db: AsyncSession, user_id: str, goal_id: str) -> SavingsGoal:
    res = await db.execute(
        select(SavingsGoal).where(
            SavingsGoal.id == goal_id,
            SavingsGoal.user_id == user_id,
        )
    )
    goal = res.scalar_one_or_none()
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
    return goal


async def _load_user_plan(db: AsyncSession, user_id: str, goal_id: str) -> AutoSavePlan:
    res = await db.execute(
        select(AutoSavePlan).where(
            AutoSavePlan.goal_id == goal_id,
            AutoSavePlan.user_id == user_id,
        )
    )
    plan = res.scalar_one_or_none()
    if not plan:
        raise HTTPException(status_code=404, detail="No auto-save plan on this goal")
    return plan


def _month_start(now: datetime | None = None) -> datetime:
    now = now or datetime.utcnow()
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


# Roughly normalises a plan's per-period amount to monthly XAF.
_FREQ_MONTHLY_FACTOR = {
    "daily":   30.0,
    "weekly":  30.0 / 7.0,
    "monthly": 1.0,
}


async def _sum_successful_between(
    db: AsyncSession, user_id: str, start: datetime, end: datetime | None = None,
) -> float:
    q = select(func.coalesce(func.sum(MoMoTransaction.amount), 0.0)).where(
        MoMoTransaction.user_id == user_id,
        MoMoTransaction.status == "SUCCESSFUL",
        MoMoTransaction.completed_at >= start,
    )
    if end is not None:
        q = q.where(MoMoTransaction.completed_at < end)
    res = await db.execute(q)
    return float(res.scalar() or 0.0)


async def _monthly_commitment(db: AsyncSession, user_id: str) -> float:
    """Sum of every active plan's amount normalised to one month.

    Used to project months-to-goal even before the user has built history.
    """
    res = await db.execute(
        select(AutoSavePlan).where(
            AutoSavePlan.user_id == user_id,
            AutoSavePlan.active == True,  # noqa: E712
        )
    )
    plans = res.scalars().all()
    return sum(
        p.amount * _FREQ_MONTHLY_FACTOR.get(p.frequency, 1.0)
        for p in plans
    )


def _goal_out(g: SavingsGoal, monthly_auto: float) -> GoalOut:
    percent   = min(g.current / g.target, 1.0) if g.target > 0 else 0
    remaining = max(g.target - g.current, 0)
    months    = int(remaining / monthly_auto) + 1 if monthly_auto > 0 else 0
    return GoalOut(
        id=str(g.id), name=g.name, emoji=g.emoji,
        target=g.target, current=g.current,
        percent=round(percent * 100, 1),
        remaining=remaining,
        is_locked=g.is_locked,
        is_completed=g.is_completed,
        months_left=months,
        deadline=g.deadline,
        note=g.note,
    )


@router.get("", response_model=SavingsResponse)
async def get_savings(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user["user_id"]

    res  = await db.execute(select(User).where(User.id == user_id))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    g_res = await db.execute(
        select(SavingsGoal)
        .where(SavingsGoal.user_id == user_id)
        .order_by(SavingsGoal.created_at)
    )
    goals = g_res.scalars().all()

    # Real "saved this month" = sum of every SUCCESSFUL Collection in this calendar month.
    saved_this_month = await _sum_successful_between(db, user_id, _month_start())

    # Projection rate: prefer realized history, fall back to active-plan commitment.
    commitment_monthly = await _monthly_commitment(db, user_id)
    projection_rate = max(saved_this_month, commitment_monthly)

    total_saved   = sum(g.current for g in goals)
    total_target  = sum(g.target  for g in goals)
    overall_pct   = round(total_saved / total_target * 100, 1) if total_target > 0 else 0

    return SavingsResponse(
        total_saved=total_saved,
        total_target=total_target,
        overall_percent=overall_pct,
        saved_this_month=saved_this_month,
        auto_save_active=user.auto_save_on,
        auto_save_percent=user.auto_save_pct,
        auto_save_provider="MTN Money",
        goals=[_goal_out(g, projection_rate) for g in goals],
    )


@router.get("/insights", response_model=SavingsInsightsOut)
async def get_savings_insights(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Rich dashboard payload: trend, allocation, upcoming, activity.

    Computed live each call — for a real product, the heavier aggregates
    would be cached or pre-warmed, but at this user-volume the cost is
    a few indexed scans and the freshness is worth it.
    """
    user_id = current_user["user_id"]
    now = datetime.utcnow()
    month_start = _month_start(now)
    prev_month_start = _month_start(month_start - timedelta(days=1))

    # ── Money in / out windows ───────────────────────────────────
    monthly_saved = await _sum_successful_between(db, user_id, month_start)
    prev_month_saved = await _sum_successful_between(
        db, user_id, prev_month_start, month_start,
    )
    lifetime_saved = await _sum_successful_between(
        db, user_id, datetime(1970, 1, 1),
    )

    if prev_month_saved > 0:
        delta_pct = round((monthly_saved - prev_month_saved) / prev_month_saved * 100, 1)
    else:
        delta_pct = 100.0 if monthly_saved > 0 else 0.0

    # ── Plans / goals headline counts ────────────────────────────
    plans_res = await db.execute(
        select(AutoSavePlan).where(AutoSavePlan.user_id == user_id)
    )
    plans = plans_res.scalars().all()
    active_plans = sum(1 for p in plans if p.active)

    goals_res = await db.execute(
        select(SavingsGoal).where(SavingsGoal.user_id == user_id)
    )
    goals = goals_res.scalars().all()
    completed_goals = sum(1 for g in goals if g.is_completed)
    locked_total = sum(
        g.current for g in goals if g.is_locked and not g.is_completed
    )

    # ── Upcoming runs in next 7 days ─────────────────────────────
    week_ahead = now + timedelta(days=7)
    goals_by_id = {str(g.id): g for g in goals}
    upcoming_plans = sorted(
        (p for p in plans if p.active and p.next_run_at <= week_ahead),
        key=lambda p: p.next_run_at,
    )
    upcoming = [
        UpcomingRunOut(
            plan_id=str(p.id),
            goal_id=str(p.goal_id),
            goal_name=goals_by_id[str(p.goal_id)].name
                if str(p.goal_id) in goals_by_id else "Goal",
            goal_emoji=goals_by_id[str(p.goal_id)].emoji
                if str(p.goal_id) in goals_by_id else "🎯",
            amount=p.amount,
            frequency=p.frequency,
            next_run_at=p.next_run_at,
        )
        for p in upcoming_plans[:5]
    ]
    weekly_scheduled = sum(p.amount for p in upcoming_plans)

    # ── Recent activity ──────────────────────────────────────────
    act_res = await db.execute(
        select(MoMoTransaction)
        .where(MoMoTransaction.user_id == user_id)
        .order_by(MoMoTransaction.initiated_at.desc())
        .limit(10)
    )
    activity = []
    for tx in act_res.scalars().all():
        gid = str(tx.goal_id) if tx.goal_id else None
        g = goals_by_id.get(gid) if gid else None
        activity.append(ActivityItemOut(
            id=str(tx.id),
            reference_id=tx.reference_id,
            goal_id=gid,
            goal_name=g.name if g else None,
            goal_emoji=g.emoji if g else None,
            amount=tx.amount,
            currency=tx.currency,
            status=tx.status,
            reason=tx.reason,
            initiated_at=tx.initiated_at,
            completed_at=tx.completed_at,
        ))

    # ── Allocation by goal (only goals with > 0 saved) ───────────
    total_saved = sum(g.current for g in goals)
    allocation: list[AllocationItemOut] = []
    if total_saved > 0:
        funded = sorted(
            (g for g in goals if g.current > 0),
            key=lambda g: g.current, reverse=True,
        )
        for g in funded:
            allocation.append(AllocationItemOut(
                goal_id=str(g.id),
                goal_name=g.name,
                goal_emoji=g.emoji,
                current=g.current,
                target=g.target,
                percent_of_total=round(g.current / total_saved * 100, 1),
            ))

    return SavingsInsightsOut(
        lifetime_saved=lifetime_saved,
        monthly_saved=monthly_saved,
        prev_month_saved=prev_month_saved,
        monthly_delta_pct=delta_pct,
        active_plans=active_plans,
        completed_goals=completed_goals,
        locked_total=locked_total,
        weekly_scheduled=weekly_scheduled,
        upcoming=upcoming,
        recent_activity=activity,
        allocation=allocation,
    )
 
@router.post("/goals", status_code=201)
async def create_goal(
    body: CreateGoalRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    goal = SavingsGoal(
        user_id=current_user["user_id"],
        name=body.name.strip(),
        emoji=body.emoji,
        target=body.target,
        note=body.note,
        deadline=body.deadline,
    )
    db.add(goal)
    await db.flush()
    return {"message": "Goal created", "id": str(goal.id)}
 
@router.patch("/goals/{goal_id}/add-funds", status_code=200)
async def add_funds(
    goal_id: str,
    body: AddFundsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res  = await db.execute(
        select(SavingsGoal).where(
            SavingsGoal.id      == goal_id,
            SavingsGoal.user_id == current_user["user_id"],
        ))
    goal = res.scalar_one_or_none()
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
 
    goal.current += body.amount
    if goal.current >= goal.target:
        goal.current     = goal.target
        goal.is_completed = True
        goal.is_locked    = False
 
    # Deduct from user balance
    u_res = await db.execute(
        select(User).where(User.id == current_user["user_id"]))
    user = u_res.scalar_one()
    user.total_balance -= body.amount
    await db.flush()
 
    return {
        "message": "Funds added",
        "new_amount": goal.current,
        "completed": goal.is_completed,
    }
 
@router.patch("/goals/{goal_id}/withdraw", status_code=200)
async def withdraw(
    goal_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res  = await db.execute(
        select(SavingsGoal).where(
            SavingsGoal.id      == goal_id,
            SavingsGoal.user_id == current_user["user_id"],
        ))
    goal = res.scalar_one_or_none()
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
 
    # 10% early withdrawal penalty
    penalty = goal.current * 0.10
    payout  = goal.current - penalty
 
    u_res = await db.execute(
        select(User).where(User.id == current_user["user_id"]))
    user        = u_res.scalar_one()
    user.total_balance += payout
    goal.current        = 0
    goal.is_completed   = False
    goal.is_locked      = True
    await db.flush()
 
    return {
        "message": "Early withdrawal processed",
        "payout":  payout,
        "penalty": penalty,
    }
 
@router.delete("/goals/{goal_id}", status_code=200)
async def delete_goal(
    goal_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res  = await db.execute(
        select(SavingsGoal).where(
            SavingsGoal.id      == goal_id,
            SavingsGoal.user_id == current_user["user_id"],
        ))
    goal = res.scalar_one_or_none()
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")
 
    # Return funds if any
    if goal.current > 0:
        u_res = await db.execute(
            select(User).where(User.id == current_user["user_id"]))
        user = u_res.scalar_one()
        user.total_balance += goal.current
 
    await db.delete(goal)
    await db.flush()
    return {"message": "Goal deleted"}
 
@router.patch("/auto-save", status_code=200)
async def update_auto_save(
    body: AutoSaveUpdateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res  = await db.execute(
        select(User).where(User.id == current_user["user_id"]))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.auto_save_pct = body.percent
    user.auto_save_on  = body.active
    await db.flush()

    return {
        "message":  "Auto-save updated",
        "percent":  user.auto_save_pct,
        "active":   user.auto_save_on,
    }


# ─── Per-goal auto-save plans (real MoMo Collections) ──────────────

@router.post("/goals/{goal_id}/auto-save", response_model=AutoSavePlanOut, status_code=201)
async def create_auto_save_plan(
    goal_id: str,
    body: CreateAutoSavePlanRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Attach a recurring auto-save plan to a goal.

    Requires a verified MoMo wallet. Either `amount` is given outright, or
    we compute it from `percent` × `assumed_monthly_income`.
    """
    user_id = current_user["user_id"]
    goal = await _load_user_goal(db, user_id, goal_id)
    if goal.is_completed:
        raise HTTPException(status_code=400, detail="Goal is already completed.")

    conn_res = await db.execute(
        select(MoMoConnection).where(
            MoMoConnection.user_id == user_id,
            MoMoConnection.verified == True,  # noqa: E712
        )
    )
    if not conn_res.scalar_one_or_none():
        raise HTTPException(
            status_code=400,
            detail="Link and verify your MoMo wallet before setting up auto-save.",
        )

    if body.amount is not None:
        amount = body.amount
    elif body.assumed_monthly_income is not None:
        # If the user picks weekly/daily, scale the monthly basis down.
        scale = {"daily": 1 / 30, "weekly": 7 / 30, "monthly": 1.0}[body.frequency]
        amount = body.assumed_monthly_income * (body.percent / 100) * scale
    else:
        raise HTTPException(
            status_code=422,
            detail="Provide either `amount` or `assumed_monthly_income`.",
        )

    if amount < 1:
        raise HTTPException(status_code=422, detail="Computed amount is too small.")

    try:
        plan = await auto_save_service.create_plan(
            db, user_id=user_id, goal_id=goal_id,
            percent=body.percent, frequency=body.frequency, amount=amount,
            reminder_enabled=body.reminder_enabled,
        )
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    await db.commit()
    await db.refresh(plan)
    return _plan_out(plan)


@router.get("/goals/{goal_id}/auto-save", response_model=AutoSavePlanDetail)
async def get_auto_save_plan(
    goal_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user["user_id"]
    plan = await _load_user_plan(db, user_id, goal_id)
    tx_res = await db.execute(
        select(MoMoTransaction)
        .where(MoMoTransaction.plan_id == plan.id)
        .order_by(MoMoTransaction.initiated_at.desc())
        .limit(20)
    )
    txs = tx_res.scalars().all()
    return AutoSavePlanDetail(plan=_plan_out(plan), transactions=[_tx_out(t) for t in txs])


@router.patch("/goals/{goal_id}/auto-save", response_model=AutoSavePlanOut)
async def patch_auto_save_plan(
    goal_id: str,
    body: UpdateAutoSavePlanRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user["user_id"]
    plan = await _load_user_plan(db, user_id, goal_id)
    plan = await auto_save_service.update_plan(
        db, plan,
        percent=body.percent, frequency=body.frequency,
        amount=body.amount, active=body.active,
        reminder_enabled=body.reminder_enabled,
    )
    await db.commit()
    await db.refresh(plan)
    return _plan_out(plan)


@router.delete("/goals/{goal_id}/auto-save", status_code=200)
async def delete_auto_save_plan(
    goal_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user["user_id"]
    plan = await _load_user_plan(db, user_id, goal_id)
    await db.delete(plan)
    await db.commit()
    return {"message": "Auto-save plan cancelled"}
