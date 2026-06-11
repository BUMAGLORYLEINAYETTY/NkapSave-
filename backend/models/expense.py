"""Transaction (income or expense) tracked by the user.

The legacy schema only stored expenses with a strict Postgres enum for
category. We've moved to:

  * `category` as a plain string — validated at the Pydantic layer so future
    categories are zero-migration.
  * `txn_type` to explicitly mark INCOME vs EXPENSE. Amount is now stored
    as a positive number; the sign in any chart/total comes from `txn_type`.
  * `txn_date` separate from `created_at` so users can backfill (e.g. log a
    receipt from yesterday).
  * Optional `payment_method` and `location` to support filtering and the
    receipt-style breakdown in the UI.
"""
from sqlalchemy import Column, String, Float, DateTime, ForeignKey, Text, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from core.database import Base
import uuid


# Single source of truth for valid category strings. Pydantic schemas reference
# this list so an invalid category is a 422, not a silent fallback.
EXPENSE_CATEGORIES = [
    "Food", "Transport", "Utilities", "Rent",
    "Healthcare", "Education", "Business", "Entertainment",
    "Shopping", "Other",
]

INCOME_CATEGORIES = [
    "Salary", "Business Income", "Investment Returns", "Gifts",
    "Njangi Payout", "Other Income",
]

ALL_CATEGORIES = EXPENSE_CATEGORIES + INCOME_CATEGORIES


TXN_TYPES = ["EXPENSE", "INCOME"]


PAYMENT_METHODS = [
    "Cash", "MTN MoMo", "Orange Money", "Bank", "Card", "Other",
]


class Expense(Base):
    """One transaction row.

    `amount` is always stored positive — read `txn_type` to know the sign.
    This is the opposite of the legacy convention (negative for expense)
    and was changed during the income/expense unification. The migration
    flips existing rows.
    """
    __tablename__ = "expenses"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id      = Column(UUID(as_uuid=True),
                          ForeignKey("users.id", ondelete="CASCADE"),
                          nullable=False, index=True)
    name         = Column(String(150), nullable=False)
    category     = Column(String(40), nullable=False, default="Other")
    txn_type     = Column(String(10), nullable=False, default="EXPENSE")
    amount       = Column(Float, nullable=False)           # positive
    note         = Column(Text, nullable=True)
    payment_method = Column(String(30), nullable=True)
    location     = Column(String(120), nullable=True)
    txn_date     = Column(DateTime(timezone=True), nullable=True, index=True)
    source       = Column(String(50), default="manual")    # manual|sms|ocr|voice|autosave|njangi
    created_at   = Column(DateTime(timezone=True),
                          server_default=func.now(), index=True)

    __table_args__ = (
        Index("ix_expenses_user_created", "user_id", "created_at"),
        Index("ix_expenses_user_category", "user_id", "category"),
    )


class Budget(Base):
    """Per-category monthly spending target.

    `period` is currently always "monthly" — leaving the column so a weekly
    or yearly target is a config change later, not a schema change.
    """
    __tablename__ = "budgets"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id      = Column(UUID(as_uuid=True),
                          ForeignKey("users.id", ondelete="CASCADE"),
                          nullable=False, index=True)
    category     = Column(String(40), nullable=False)
    amount       = Column(Float, nullable=False)           # target, positive
    period       = Column(String(10), nullable=False, default="monthly")
    created_at   = Column(DateTime(timezone=True), server_default=func.now())
    updated_at   = Column(DateTime(timezone=True), onupdate=func.now())

    __table_args__ = (
        Index("ix_budget_user_category", "user_id", "category", unique=True),
    )
