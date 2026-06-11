"""Unified income/expense tracking.

Endpoints:

  GET    /expenses                Filterable list + bar-chart + budgets + insights
  GET    /expenses/trend          Daily income/expense series for a line chart
  GET    /expenses/meta           Categories + payment methods for the UI
  POST   /expenses                Log a transaction
  PATCH  /expenses/{id}           Edit a transaction
  DELETE /expenses/{id}           Remove a transaction
  GET    /budgets                 Current budget targets + progress
  PUT    /budgets                 Upsert a category target
  DELETE /budgets/{category}      Remove a target

Conventions:
  * `amount` is stored positive; the sign comes from `txn_type`.
  * `category` is a free string validated against ALL_CATEGORIES at write time.
  * Filters default to current calendar month if no date range is given.
"""
from __future__ import annotations

from datetime import datetime, date, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from fastapi.responses import StreamingResponse, Response
from sqlalchemy import select, delete, and_, or_, func
from sqlalchemy.ext.asyncio import AsyncSession
import io

from core.database import get_db
from core.security import get_current_user
from models.user import User
from models.expense import (
    Expense, Budget,
    EXPENSE_CATEGORIES, INCOME_CATEGORIES, ALL_CATEGORIES, PAYMENT_METHODS,
)
from models.expense_schemas import (
    AddExpenseRequest, UpdateExpenseRequest,
    ExpenseOut, CategorySummary,
    ExpensesResponse, BudgetProgress, TrendPoint, TrendResponse,
    SetBudgetRequest, BudgetOut, ExpenseMetaResponse,
)
from services.statement_service import (
    build_statement_data, render_csv, render_xlsx, render_pdf,
)
from services.statement_delivery import generate_and_deliver
from models.statement import Statement
from services import ocr_service
from services.email_service import is_configured as email_is_configured
from services.statement_emailer import send_statement_for_user

router = APIRouter(prefix="/expenses", tags=["Expenses"])
budgets_router = APIRouter(prefix="/budgets", tags=["Budgets"])


# HTTP header values must be latin-1 encodable. Filenames are user-derived so
# we transliterate the common non-latin-1 chars our labels generate (→, —, ·,
# accented letters) before they hit Content-Disposition.
_HEADER_TRANSLIT = str.maketrans({
    "→": "to", "←": "from", "—": "-", "–": "-", "·": "-",
    "…": "...", "“": '"', "”": '"', "‘": "'", "’": "'",
})


def _ascii_filename(name: str) -> str:
    name = name.translate(_HEADER_TRANSLIT)
    # Strip anything still outside latin-1 (e.g. emoji) as a final safety net.
    return name.encode("latin-1", "ignore").decode("latin-1")


CATEGORY_COLORS = {
    # Expense
    "Food":          "#FF7043",
    "Transport":     "#42A5F5",
    "Utilities":     "#26C6DA",
    "Rent":          "#A78BFA",
    "Healthcare":    "#EC407A",
    "Education":     "#66BB6A",
    "Business":      "#FFB627",
    "Entertainment": "#AB47BC",
    "Shopping":      "#FF8A65",
    "Other":         "#78716C",
    # Income (greens / cool tones — distinct from expense palette)
    "Salary":             "#12E8A4",
    "Business Income":    "#26A69A",
    "Investment Returns": "#7CB342",
    "Gifts":              "#FFCA28",
    "Njangi Payout":      "#FFB627",
    "Other Income":       "#9E9E9E",
}

WARN_THRESHOLD     = 0.80
CRITICAL_THRESHOLD = 0.90


def _color(cat: str) -> str:
    return CATEGORY_COLORS.get(cat, "#78716C")


def _date_label(dt: datetime) -> str:
    today = date.today()
    d = dt.date()
    if d == today:                       return "Today"
    if d == today - timedelta(days=1):   return "Yesterday"
    if (today - d).days < 7:             return dt.strftime("%A")
    if d.year == today.year:             return dt.strftime("%b %d")
    return dt.strftime("%b %d, %Y")


def _month_start(d: datetime | None = None) -> datetime:
    d = d or datetime.utcnow()
    return d.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def _txn_when(e: Expense) -> datetime:
    """Logical date for a transaction — user-provided txn_date wins."""
    return e.txn_date or e.created_at


def _to_out(e: Expense) -> ExpenseOut:
    when = _txn_when(e)
    signed = e.amount if e.txn_type == "INCOME" else -e.amount
    return ExpenseOut(
        id=str(e.id), name=e.name,
        category=e.category, txn_type=e.txn_type,
        amount=e.amount, signed_amount=signed,
        note=e.note,
        payment_method=e.payment_method,
        location=e.location,
        date_label=_date_label(when),
        iso_date=when.isoformat(),
        color_hex=_color(e.category),
        source=e.source or "manual",
    )


async def _budget_progress(
    db: AsyncSession, user_id: str, by_category: dict[str, float],
) -> list[BudgetProgress]:
    """Return progress rows for each saved budget."""
    res = await db.execute(
        select(Budget).where(Budget.user_id == user_id)
    )
    rows: list[BudgetProgress] = []
    for b in res.scalars().all():
        spent = by_category.get(b.category, 0.0)
        pct = (spent / b.amount * 100) if b.amount > 0 else 0
        if pct >= 100:
            status = "exceeded"
        elif pct >= CRITICAL_THRESHOLD * 100:
            status = "critical"
        elif pct >= WARN_THRESHOLD * 100:
            status = "warning"
        else:
            status = "ok"
        rows.append(BudgetProgress(
            category=b.category, target=b.amount,
            spent=spent, percent=round(pct, 1), status=status,
        ))
    return rows


def _build_insights(
    *, expense_categories: list[CategorySummary],
    total_expense: float, total_income: float,
    income_delta: float, spending_delta: float,
    budgets: list[BudgetProgress],
) -> list[str]:
    out: list[str] = []
    # 1) Budget warnings — most urgent, surface first.
    over = [b for b in budgets if b.status == "exceeded"]
    crit = [b for b in budgets if b.status == "critical"]
    if over:
        b = max(over, key=lambda x: x.percent)
        out.append(
            f"⚠ Over budget on {b.category}: {b.percent:.0f}% of your "
            f"{int(b.target):,} XAF target — review recent {b.category} "
            f"transactions."
        )
    elif crit:
        b = max(crit, key=lambda x: x.percent)
        out.append(
            f"You're at {b.percent:.0f}% of your {b.category} budget — "
            f"only {int(b.target - b.spent):,} XAF left this month."
        )

    # 2) Top category insight.
    if expense_categories:
        top = expense_categories[0]
        if top.percent >= 40:
            out.append(
                f"{top.name} is {top.percent:.0f}% of your spending. "
                f"Cutting it to 30% would free up "
                f"~{int(total_expense * (top.percent - 30) / 100):,} XAF/month."
            )
        elif top.delta_pct >= 30:
            out.append(
                f"{top.name} spending jumped {top.delta_pct:+.0f}% vs last month."
            )

    # 3) Income vs expense story.
    if total_income > 0 and total_expense > 0:
        rate = (total_income - total_expense) / total_income
        if rate < 0:
            out.append(
                f"You spent {abs(rate)*100:.0f}% more than you earned this month. "
                f"Time to trim a category or boost income."
            )
        elif rate >= 0.20:
            out.append(
                f"Strong month — you saved {rate*100:.0f}% of your income. "
                f"Consider raising an auto-save plan to lock it in."
            )

    if not out:
        out.append("Log a few more transactions and we'll surface trends here.")
    return out[:3]


# ─── /expenses (main dashboard endpoint) ──────────────────────────

@router.get("", response_model=ExpensesResponse)
async def get_expenses(
    date_from: Optional[date] = Query(default=None),
    date_to:   Optional[date] = Query(default=None),
    txn_type:  Optional[str]  = Query(default=None,
                                       description="EXPENSE | INCOME"),
    category:  Optional[str]  = Query(default=None,
                                       description="Filter list by category"),
    search:    Optional[str]  = Query(default=None, max_length=120),
    min_amount: Optional[float] = Query(default=None, gt=0),
    max_amount: Optional[float] = Query(default=None, gt=0),
    sort:      str = Query(default="recent",
                            description="recent | oldest | high | low"),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user["user_id"]
    now = datetime.utcnow()

    # Resolve window: default to current month.
    if date_from is None and date_to is None:
        window_start = _month_start(now)
        window_end   = now
        prev_start   = _month_start(window_start - timedelta(days=1))
        prev_end     = window_start
    else:
        window_start = (
            datetime.combine(date_from, datetime.min.time())
            if date_from else _month_start(now)
        )
        window_end = (
            datetime.combine(date_to, datetime.max.time())
            if date_to else now
        )
        span = window_end - window_start
        prev_end   = window_start
        prev_start = window_start - span

    when_col = func.coalesce(Expense.txn_date, Expense.created_at)

    # All transactions in the window — used for totals + bar chart.
    all_q = select(Expense).where(
        Expense.user_id == user_id,
        when_col >= window_start,
        when_col <= window_end,
    )
    all_rows = (await db.execute(all_q)).scalars().all()

    # Filtered transactions — used for the list only.
    filt_q = all_q
    if txn_type:
        filt_q = filt_q.where(Expense.txn_type == txn_type)
    if category and category != "All":
        filt_q = filt_q.where(Expense.category == category)
    if search:
        like = f"%{search}%"
        filt_q = filt_q.where(or_(
            Expense.name.ilike(like),
            Expense.note.ilike(like),
            Expense.location.ilike(like),
        ))
    if min_amount is not None:
        filt_q = filt_q.where(Expense.amount >= min_amount)
    if max_amount is not None:
        filt_q = filt_q.where(Expense.amount <= max_amount)

    # Sort.
    if sort == "oldest":
        filt_q = filt_q.order_by(when_col.asc())
    elif sort == "high":
        filt_q = filt_q.order_by(Expense.amount.desc())
    elif sort == "low":
        filt_q = filt_q.order_by(Expense.amount.asc())
    else:
        filt_q = filt_q.order_by(when_col.desc())

    filt_rows = (await db.execute(filt_q)).scalars().all()

    # Totals.
    total_expense = sum(r.amount for r in all_rows if r.txn_type == "EXPENSE")
    total_income  = sum(r.amount for r in all_rows if r.txn_type == "INCOME")
    net           = total_income - total_expense

    # Previous-window totals — for deltas.
    prev_q = select(Expense).where(
        Expense.user_id == user_id,
        when_col >= prev_start,
        when_col < prev_end,
    )
    prev_rows = (await db.execute(prev_q)).scalars().all()
    prev_exp = sum(r.amount for r in prev_rows if r.txn_type == "EXPENSE")
    prev_inc = sum(r.amount for r in prev_rows if r.txn_type == "INCOME")
    spending_delta = (total_expense - prev_exp) / prev_exp if prev_exp > 0 else 0.0
    income_delta   = (total_income  - prev_inc) / prev_inc if prev_inc > 0 else 0.0
    savings_rate   = net / total_income if total_income > 0 else 0.0

    # Category breakdown — separate maps so income & expense don't muddle the bar chart.
    exp_by_cat: dict[str, float] = {}
    inc_by_cat: dict[str, float] = {}
    for r in all_rows:
        m = inc_by_cat if r.txn_type == "INCOME" else exp_by_cat
        m[r.category] = m.get(r.category, 0.0) + r.amount

    # Previous-window per-category — for delta arrows.
    prev_by_cat: dict[tuple[str, str], float] = {}
    for r in prev_rows:
        key = (r.txn_type, r.category)
        prev_by_cat[key] = prev_by_cat.get(key, 0.0) + r.amount

    def _build_summary(
        by_cat: dict[str, float], total: float, kind: str,
    ) -> list[CategorySummary]:
        rows = []
        for name, amt in sorted(by_cat.items(), key=lambda x: -x[1]):
            prev = prev_by_cat.get((kind, name), 0.0)
            delta = ((amt - prev) / prev * 100) if prev > 0 else 0.0
            rows.append(CategorySummary(
                name=name, amount=amt,
                color_hex=_color(name),
                percent=round(amt / total * 100, 1) if total > 0 else 0.0,
                txn_type=kind,
                delta_pct=round(delta, 1),
            ))
        return rows

    expense_cats = _build_summary(exp_by_cat, total_expense, "EXPENSE")
    income_cats  = _build_summary(inc_by_cat, total_income, "INCOME")
    categories = expense_cats + income_cats

    # Budget progress against this-month expense spend.
    budgets = await _budget_progress(db, user_id, exp_by_cat)

    insights = _build_insights(
        expense_categories=expense_cats,
        total_expense=total_expense, total_income=total_income,
        income_delta=income_delta, spending_delta=spending_delta,
        budgets=budgets,
    )

    return ExpensesResponse(
        total_expense=total_expense,
        total_income=total_income,
        net=net,
        spending_delta=spending_delta,
        income_delta=income_delta,
        savings_rate=savings_rate,
        categories=categories,
        transactions=[_to_out(e) for e in filt_rows],
        budgets=budgets,
        insights=insights,
    )


# ─── /expenses/trend (line chart series) ──────────────────────────

@router.get("/trend", response_model=TrendResponse)
async def get_trend(
    days: int = Query(default=30, ge=1, le=365),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user["user_id"]
    now = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    start = now - timedelta(days=days - 1)

    when_col = func.coalesce(Expense.txn_date, Expense.created_at)
    res = await db.execute(
        select(
            func.date(when_col).label("d"),
            Expense.txn_type,
            func.sum(Expense.amount).label("total"),
        ).where(
            Expense.user_id == user_id,
            when_col >= start,
        ).group_by(func.date(when_col), Expense.txn_type)
    )

    buckets: dict[str, dict[str, float]] = {}
    for row in res:
        key = row.d.isoformat()
        bucket = buckets.setdefault(key, {"INCOME": 0.0, "EXPENSE": 0.0})
        bucket[row.txn_type] = float(row.total or 0)

    # Fill every day so the line chart doesn't have gaps.
    points: list[TrendPoint] = []
    for i in range(days):
        d = (start + timedelta(days=i)).date()
        b = buckets.get(d.isoformat(), {"INCOME": 0.0, "EXPENSE": 0.0})
        points.append(TrendPoint(
            date=d.isoformat(),
            income=b["INCOME"], expense=b["EXPENSE"],
        ))
    return TrendResponse(days=days, points=points)


# ─── /expenses/meta ────────────────────────────────────────────────

@router.get("/meta", response_model=ExpenseMetaResponse)
async def get_meta(_: dict = Depends(get_current_user)):
    return ExpenseMetaResponse(
        expense_categories=EXPENSE_CATEGORIES,
        income_categories=INCOME_CATEGORIES,
        payment_methods=PAYMENT_METHODS,
    )


# ─── /expenses/export (CSV / XLSX / PDF download) ─────────────────

_FORMATS = {
    "csv":  ("text/csv",
             "csv",
             render_csv),
    "xlsx": ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
             "xlsx",
             render_xlsx),
    "pdf":  ("application/pdf",
             "pdf",
             render_pdf),
}


@router.get("/export")
async def export_transactions(
    format: str = Query(default="pdf", regex="^(csv|xlsx|pdf)$"),
    date_from: Optional[date] = Query(default=None),
    date_to:   Optional[date] = Query(default=None),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return a CSV / XLSX / PDF of the user's transactions.

    Defaults to the current calendar month. Pass `date_from` and/or `date_to`
    (YYYY-MM-DD) for any custom window.
    """
    user_id = current_user["user_id"]
    res = await db.execute(select(User).where(User.id == user_id))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    now = datetime.utcnow()
    if date_from is None and date_to is None:
        start = _month_start(now)
        end   = (_month_start(start + timedelta(days=32)))
        label = start.strftime("%B %Y")
    else:
        start = (
            datetime.combine(date_from, datetime.min.time())
            if date_from else _month_start(now)
        )
        end = (
            datetime.combine(date_to, datetime.max.time())
            if date_to else now
        )
        label = None

    data = await build_statement_data(
        db, user, start=start, end=end, period_label=label,
    )

    mime, ext, renderer = _FORMATS[format]
    payload = renderer(data)
    filename = _ascii_filename(
        f"NkapSave_{(data.period_label or 'statement').replace(' ', '_')}.{ext}"
    )
    return Response(
        content=payload,
        media_type=mime,
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Content-Length": str(len(payload)),
        },
    )


# ─── Statements inbox (works for users without email too) ──────────

@router.get("/statements")
async def list_statements(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return every past statement for the user, newest first.

    Each row includes delivery-channel results so the UI can show
    'Sent to email · WhatsApp' badges or 'In-app only' for users without
    those channels.
    """
    res = await db.execute(
        select(Statement)
        .where(Statement.user_id == current_user["user_id"])
        .order_by(Statement.period_year.desc(),
                   Statement.period_month.desc())
    )
    rows = res.scalars().all()
    return [
        {
            "id":           str(r.id),
            "period_year":  r.period_year,
            "period_month": r.period_month,
            "period_label": r.period_label,
            "size_bytes":   r.size_bytes,
            "channels":     r.channels or {},
            "created_at":   r.created_at.isoformat() if r.created_at else None,
        }
        for r in rows
    ]


@router.get("/statements/{statement_id}/download")
async def download_statement(
    statement_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(Statement).where(
            Statement.id == statement_id,
            Statement.user_id == current_user["user_id"],
        )
    )
    row = res.scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Statement not found")
    filename = _ascii_filename(
        f"NkapSave_{row.period_label.replace(' ', '_')}.pdf"
    )
    return Response(
        content=row.pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Content-Length": str(row.size_bytes),
        },
    )


@router.post("/statements/generate")
async def generate_statement(
    year: int = Query(..., ge=2000, le=2100),
    month: int = Query(..., ge=1, le=12),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """On-demand statement generation.

    Used for the 'Email me last month's statement' button and for testing
    the cron path without waiting until the 1st.
    """
    user_id = current_user["user_id"]
    res = await db.execute(select(User).where(User.id == user_id))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    stmt = await generate_and_deliver(db, user, year=year, month=month)
    await db.commit()
    return {
        "id":           str(stmt.id),
        "period_label": stmt.period_label,
        "size_bytes":   stmt.size_bytes,
        "channels":     stmt.channels,
    }


@router.delete("/statements/{statement_id}", status_code=200)
async def delete_statement(
    statement_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(Statement).where(
            Statement.id == statement_id,
            Statement.user_id == current_user["user_id"],
        )
    )
    row = res.scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Statement not found")
    await db.delete(row)
    await db.commit()
    return {"message": "Statement removed"}


# ─── On-demand emailed statement ──────────────────────────────────

@router.post("/email-statement", status_code=200)
async def email_my_statement(
    year:  Optional[int] = Query(default=None, ge=2020, le=2100),
    month: Optional[int] = Query(default=None, ge=1, le=12),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Email the requesting user a PDF statement.

    Defaults to the previous calendar month (same window the cron uses).
    Returns 503 if SMTP isn't configured server-side.
    """
    if not email_is_configured():
        raise HTTPException(
            status_code=503,
            detail="Email is not configured on the server.",
        )
    if year is None or month is None:
        first_this = datetime.utcnow().replace(day=1)
        last = first_this - timedelta(days=1)
        year, month = last.year, last.month

    u_res = await db.execute(select(User).where(User.id == current_user["user_id"]))
    user = u_res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if not user.email:
        raise HTTPException(
            status_code=400, detail="Your account has no email address.",
        )

    try:
        sent = await send_statement_for_user(db, user, year, month)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Email send failed: {e}")
    if not sent:
        return {
            "message": (
                "No transactions in that month — nothing to send."
            ),
            "sent": False, "period": f"{year}-{month:02d}",
        }
    return {
        "message": f"Statement for {year}-{month:02d} sent to {user.email}",
        "sent": True, "period": f"{year}-{month:02d}",
    }


# ─── OCR ──────────────────────────────────────────────────────────

@router.post("/ocr")
async def ocr_receipt(
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    """Run OCR on an uploaded receipt image; return parsed candidate fields.

    The caller is expected to show a review screen so the user can correct
    the extracted values before saving. OCR confidence is always < 1.0 in
    practice; treat the result as suggestion, not truth.
    """
    if not ocr_service.is_available():
        raise HTTPException(
            status_code=503,
            detail=(
                "OCR engine not installed on the server. "
                "Run `brew install tesseract tesseract-lang`."
            ),
        )
    if file.content_type and not file.content_type.startswith("image/"):
        raise HTTPException(
            status_code=422,
            detail=f"Expected an image, got {file.content_type}",
        )
    # Cap upload to ~6 MB.
    blob = await file.read(6 * 1024 * 1024 + 1)
    if len(blob) > 6 * 1024 * 1024:
        raise HTTPException(
            status_code=413,
            detail="Receipt image too large (max 6 MB).",
        )

    try:
        result = ocr_service.extract(blob)
    except ocr_service.OcrNotAvailable as e:
        raise HTTPException(status_code=503, detail=str(e))
    return ocr_service.result_to_dict(result)


# ─── Write endpoints ──────────────────────────────────────────────

@router.post("", status_code=201, response_model=ExpenseOut)
async def add_expense(
    body: AddExpenseRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Sanity: expense categories shouldn't be paired with INCOME and vice versa.
    if body.txn_type == "INCOME" and body.category in EXPENSE_CATEGORIES:
        raise HTTPException(
            status_code=422,
            detail=f"'{body.category}' is an expense category. Use income category.",
        )
    if body.txn_type == "EXPENSE" and body.category in INCOME_CATEGORIES:
        raise HTTPException(
            status_code=422,
            detail=f"'{body.category}' is an income category. Use expense category.",
        )

    txn = Expense(
        user_id=current_user["user_id"],
        name=body.name.strip(),
        category=body.category,
        txn_type=body.txn_type,
        amount=body.amount,
        note=body.note,
        payment_method=body.payment_method,
        location=body.location,
        txn_date=body.txn_date,
        source="manual",
    )
    db.add(txn)

    # Mirror into running balance.
    u_res = await db.execute(select(User).where(User.id == current_user["user_id"]))
    user = u_res.scalar_one()
    if body.txn_type == "INCOME":
        user.total_balance += body.amount
    else:
        user.total_balance -= body.amount

    await db.flush()
    await db.refresh(txn)
    return _to_out(txn)


@router.patch("/{expense_id}", response_model=ExpenseOut)
async def update_expense(
    expense_id: str,
    body: UpdateExpenseRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(Expense).where(
            Expense.id == expense_id,
            Expense.user_id == current_user["user_id"],
        )
    )
    txn = res.scalar_one_or_none()
    if not txn:
        raise HTTPException(status_code=404, detail="Transaction not found")

    # Unwind the running-balance effect of the old row.
    u_res = await db.execute(select(User).where(User.id == current_user["user_id"]))
    user = u_res.scalar_one()
    if txn.txn_type == "INCOME":
        user.total_balance -= txn.amount
    else:
        user.total_balance += txn.amount

    # Apply patch.
    if body.name is not None:           txn.name = body.name.strip()
    if body.category is not None:       txn.category = body.category
    if body.amount is not None:         txn.amount = body.amount
    if body.txn_type is not None:       txn.txn_type = body.txn_type
    if body.note is not None:           txn.note = body.note
    if body.payment_method is not None: txn.payment_method = body.payment_method
    if body.location is not None:       txn.location = body.location
    if body.txn_date is not None:       txn.txn_date = body.txn_date

    # Re-apply balance with new values.
    if txn.txn_type == "INCOME":
        user.total_balance += txn.amount
    else:
        user.total_balance -= txn.amount

    await db.flush()
    await db.refresh(txn)
    return _to_out(txn)


@router.delete("/{expense_id}", status_code=200)
async def delete_expense(
    expense_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(Expense).where(
            Expense.id == expense_id,
            Expense.user_id == current_user["user_id"],
        )
    )
    txn = res.scalar_one_or_none()
    if not txn:
        raise HTTPException(status_code=404, detail="Transaction not found")

    u_res = await db.execute(select(User).where(User.id == current_user["user_id"]))
    user = u_res.scalar_one()
    if txn.txn_type == "INCOME":
        user.total_balance -= txn.amount
    else:
        user.total_balance += txn.amount

    await db.delete(txn)
    await db.flush()
    return {"message": "Transaction deleted"}


# ─── Budgets ───────────────────────────────────────────────────────

@budgets_router.get("", response_model=list[BudgetOut])
async def list_budgets(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(Budget).where(Budget.user_id == current_user["user_id"])
    )
    return [
        BudgetOut(
            category=b.category, amount=b.amount,
            period=b.period, updated_at=b.updated_at,
        )
        for b in res.scalars().all()
    ]


@budgets_router.put("", response_model=BudgetOut)
async def upsert_budget(
    body: SetBudgetRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user["user_id"]
    res = await db.execute(
        select(Budget).where(
            Budget.user_id == user_id,
            Budget.category == body.category,
        )
    )
    b = res.scalar_one_or_none()
    if b:
        b.amount = body.amount
        b.period = body.period
    else:
        b = Budget(
            user_id=user_id, category=body.category,
            amount=body.amount, period=body.period,
        )
        db.add(b)
    await db.flush()
    await db.refresh(b)
    return BudgetOut(
        category=b.category, amount=b.amount,
        period=b.period, updated_at=b.updated_at,
    )


@budgets_router.delete("/{category}", status_code=200)
async def delete_budget(
    category: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        delete(Budget).where(
            Budget.user_id == current_user["user_id"],
            Budget.category == category,
        )
    )
    if res.rowcount == 0:
        raise HTTPException(status_code=404, detail="No budget for that category")
    return {"message": "Budget removed"}
