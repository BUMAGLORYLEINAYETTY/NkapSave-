from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from datetime import datetime, date, timedelta
from core.database import get_db
from core.security import get_current_user
from models.user import User
from models.transaction import Transaction, TxCategory
from models.schemas import (
    DashboardResponse, WeeklySpendPoint,
    TransactionOut, AddTransactionRequest,
)
 
router = APIRouter(prefix="/dashboard", tags=["Dashboard"])
 
COLORS = {
    "Income":       "#12E8A4",
    "Food & Drink": "#FF7043",
    "Transport":    "#42A5F5",
    "Utilities":    "#AB47BC",
    "Shopping":     "#EC407A",
    "Housing":      "#A78BFA",
    "Health":       "#26C6DA",
    "Njangi":       "#FFB627",
    "Savings":      "#60A5FA",
    "Other":        "#78716C",
}
 
def _fmt_date(dt: datetime) -> str:
    today = date.today()
    if dt.date() == today:
        return "Today"
    if dt.date() == today - timedelta(days=1):
        return "Yesterday"
    return dt.strftime("%b %d")
 
@router.get("", response_model=DashboardResponse)
async def get_dashboard(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id     = current_user["user_id"]
    now         = datetime.utcnow()
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
 
    # User
    result = await db.execute(select(User).where(User.id == user_id))
    user   = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
 
    # Monthly totals
    m_res  = await db.execute(
        select(Transaction).where(
            Transaction.user_id   == user_id,
            Transaction.created_at >= month_start,
        ))
    m_txns           = m_res.scalars().all()
    monthly_income   = sum(t.amount for t in m_txns if t.amount > 0)
    monthly_expenses = sum(abs(t.amount) for t in m_txns if t.amount < 0)
    saved_this_month = (
        monthly_income * (user.auto_save_pct / 100) if user.auto_save_on else 0
    )
 
    # Weekly spend
    week_start = now - timedelta(days=6)
    w_res      = await db.execute(
        select(Transaction).where(
            Transaction.user_id    == user_id,
            Transaction.created_at >= week_start,
            Transaction.amount     < 0,
        ))
    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    week_map  = {d: 0.0 for d in day_names}
    for t in w_res.scalars().all():
        week_map[day_names[t.created_at.weekday()]] += abs(t.amount)
    weekly_spend = [WeeklySpendPoint(day=d, amount=week_map[d]) for d in day_names]
 
    # Recent transactions
    r_res  = await db.execute(
        select(Transaction)
        .where(Transaction.user_id == user_id)
        .order_by(Transaction.created_at.desc())
        .limit(10))
    recent_out = [
        TransactionOut(
            id=str(t.id), name=t.name, category=t.category.value,
            amount=t.amount, date=_fmt_date(t.created_at),
            color_hex=COLORS.get(t.category.value, "#78716C"),
        )
        for t in r_res.scalars().all()
    ]
 
    # Spending delta vs last month
    last_start = (month_start - timedelta(days=1)).replace(day=1)
    l_res      = await db.execute(
        select(func.sum(Transaction.amount)).where(
            Transaction.user_id    == user_id,
            Transaction.created_at >= last_start,
            Transaction.created_at <  month_start,
            Transaction.amount     < 0,
        ))
    last_exp = abs(l_res.scalar() or 0)
    delta    = (monthly_expenses - last_exp) / last_exp if last_exp > 0 else 0.0
 
    return DashboardResponse(
        total_balance=user.total_balance,
        monthly_income=monthly_income,
        monthly_expenses=monthly_expenses,
        saved_this_month=saved_this_month,
        auto_save_active=user.auto_save_on,
        auto_save_percent=user.auto_save_pct,
        weekly_spend=weekly_spend,
        recent_transactions=recent_out,
        njangi_alert=None,
        savings_progress=min(user.total_balance / 1_000_000, 1.0),
        spending_vs_last_month=delta,
    )
 
@router.post("/transactions", status_code=201)
async def add_transaction(
    body: AddTransactionRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        cat = TxCategory(body.category)
    except ValueError:
        cat = TxCategory.OTHER
 
    tx = Transaction(
        user_id=current_user["user_id"],
        name=body.name,
        category=cat,
        amount=body.amount,
        note=body.note,
        source="manual",
    )
    db.add(tx)
 
    res  = await db.execute(select(User).where(User.id == current_user["user_id"]))
    user = res.scalar_one()
    user.total_balance += body.amount
    await db.flush()
 
    return {"message": "Transaction added", "id": str(tx.id)}
