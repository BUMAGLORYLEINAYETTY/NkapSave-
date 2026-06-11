"""Pydantic schemas for the unified income/expense tracking system."""
from __future__ import annotations

from datetime import date, datetime
from typing import List, Literal, Optional

from pydantic import BaseModel, Field, field_validator

from models.expense import (
    ALL_CATEGORIES, EXPENSE_CATEGORIES, INCOME_CATEGORIES,
    PAYMENT_METHODS, TXN_TYPES,
)


TxnType = Literal["EXPENSE", "INCOME"]


def _validate_category(v: str, txn_type: str | None = None) -> str:
    if v not in ALL_CATEGORIES:
        raise ValueError(
            f"Unknown category '{v}'. Allowed: {', '.join(ALL_CATEGORIES)}"
        )
    return v


class AddExpenseRequest(BaseModel):
    name:           str = Field(min_length=1, max_length=150)
    category:       str
    amount:         float = Field(gt=0)
    txn_type:       TxnType = "EXPENSE"
    note:           Optional[str] = None
    payment_method: Optional[str] = None
    location:       Optional[str] = None
    txn_date:       Optional[datetime] = None

    @field_validator("category")
    @classmethod
    def _cat(cls, v: str) -> str:
        return _validate_category(v)

    @field_validator("payment_method")
    @classmethod
    def _pm(cls, v: str | None) -> str | None:
        if v is None: return v
        if v not in PAYMENT_METHODS:
            raise ValueError(
                f"Unknown payment method '{v}'. "
                f"Allowed: {', '.join(PAYMENT_METHODS)}"
            )
        return v


class UpdateExpenseRequest(BaseModel):
    name:           Optional[str] = Field(default=None, max_length=150)
    category:       Optional[str] = None
    amount:         Optional[float] = Field(default=None, gt=0)
    txn_type:       Optional[TxnType] = None
    note:           Optional[str] = None
    payment_method: Optional[str] = None
    location:       Optional[str] = None
    txn_date:       Optional[datetime] = None

    @field_validator("category")
    @classmethod
    def _cat(cls, v: str | None) -> str | None:
        return None if v is None else _validate_category(v)


class ExpenseOut(BaseModel):
    id:             str
    name:           str
    category:       str
    txn_type:       str
    amount:         float          # always positive
    signed_amount:  float          # negative for expense, positive for income
    note:           Optional[str]
    payment_method: Optional[str]
    location:       Optional[str]
    date_label:     str            # "Today"/"Yesterday"/"Jan 4"
    iso_date:       str            # "2026-05-14T18:32:00+00:00"
    color_hex:      str
    source:         str


class CategorySummary(BaseModel):
    name:          str
    amount:        float
    color_hex:     str
    percent:       float           # 0..100
    txn_type:      str             # EXPENSE or INCOME
    delta_pct:     float           # vs same window last period; 0 if no history


class BudgetProgress(BaseModel):
    category:      str
    target:        float
    spent:         float
    percent:       float           # 0..100+ (can exceed)
    status:        str             # ok | warning | critical | exceeded


class ExpensesResponse(BaseModel):
    # Totals
    total_expense:    float
    total_income:     float
    net:              float            # income − expense
    spending_delta:   float            # +0.12 = +12% vs prior month
    income_delta:     float
    savings_rate:     float            # net / income, 0..1, 0 if no income

    # Category bar chart data
    categories:       List[CategorySummary]

    # Filtered transaction list (respects all filters)
    transactions:     List[ExpenseOut]

    # Budget progress for any category that has a target
    budgets:          List[BudgetProgress]

    # Personalised insight strings (1-3 items)
    insights:         List[str]


# ─── Trend (line chart) ────────────────────────────────────────────

class TrendPoint(BaseModel):
    date:    str        # YYYY-MM-DD
    income:  float
    expense: float


class TrendResponse(BaseModel):
    days:    int
    points:  List[TrendPoint]


# ─── Budgets ───────────────────────────────────────────────────────

class SetBudgetRequest(BaseModel):
    category: str
    amount:   float = Field(gt=0)
    period:   Literal["monthly"] = "monthly"

    @field_validator("category")
    @classmethod
    def _cat(cls, v: str) -> str:
        # Only expense categories can have a budget — saving against
        # "Salary" makes no sense.
        if v not in EXPENSE_CATEGORIES:
            raise ValueError(
                f"Budgets can only target expense categories. "
                f"Allowed: {', '.join(EXPENSE_CATEGORIES)}"
            )
        return v


class BudgetOut(BaseModel):
    category: str
    amount:   float
    period:   str
    updated_at: Optional[datetime]


# ─── Metadata for the add-transaction sheet ────────────────────────

class ExpenseMetaResponse(BaseModel):
    expense_categories: List[str]
    income_categories:  List[str]
    payment_methods:    List[str]
