"""Persistence for MTN MoMo integration and auto-save scheduling."""
from sqlalchemy import (
    Column, String, Float, Boolean, DateTime, ForeignKey, Integer, Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from core.database import Base
import uuid


class MoMoConnection(Base):
    """A user's linked mobile-money wallet.

    `verified` flips true once we've called validate_holder and gotten back
    a positive result. We never store the user's PIN.
    """
    __tablename__ = "momo_connections"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id      = Column(UUID(as_uuid=True),
                          ForeignKey("users.id", ondelete="CASCADE"),
                          unique=True, nullable=False, index=True)
    provider     = Column(String(20), nullable=False, default="mtn")
    phone        = Column(String(20), nullable=False)
    verified     = Column(Boolean, default=False, nullable=False)
    last_verified_at = Column(DateTime(timezone=True), nullable=True)
    created_at   = Column(DateTime(timezone=True), server_default=func.now())
    updated_at   = Column(DateTime(timezone=True), onupdate=func.now())


class AutoSavePlan(Base):
    """A per-goal recurring auto-save rule.

    `next_run_at` is what the scheduler ticks against. After each run (success
    or failure) it advances by one period of `frequency`.
    """
    __tablename__ = "auto_save_plans"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id      = Column(UUID(as_uuid=True),
                          ForeignKey("users.id", ondelete="CASCADE"),
                          nullable=False, index=True)
    goal_id      = Column(UUID(as_uuid=True),
                          ForeignKey("savings_goals.id", ondelete="CASCADE"),
                          unique=True, nullable=False, index=True)
    # Fixed amount per period; computed once when the plan is created from
    # `percent` × user's declared monthly income. We persist the resolved
    # amount because the % concept only makes sense relative to "incoming",
    # and MTN's Collection API can't see the user's incoming transactions.
    amount       = Column(Float, nullable=False)
    percent      = Column(Integer, nullable=False)  # 5..30 — for audit / display
    frequency    = Column(String(20), nullable=False)  # daily|weekly|monthly
    active       = Column(Boolean, default=True, nullable=False)
    next_run_at  = Column(DateTime(timezone=True), nullable=False, index=True)
    last_run_at  = Column(DateTime(timezone=True), nullable=True)
    consecutive_failures = Column(Integer, default=0, nullable=False)
    last_milestone_notified = Column(Integer, default=0, nullable=False)  # 0|25|50|75|100
    reminder_enabled = Column(Boolean, default=True, nullable=False)
    # Tracks the `next_run_at` value we last sent a reminder for. When the
    # plan advances after a deduction, this becomes stale and the next
    # reminder fires. Avoids double-sends without a separate audit table.
    last_reminder_for_run_at = Column(DateTime(timezone=True), nullable=True)
    created_at   = Column(DateTime(timezone=True), server_default=func.now())
    updated_at   = Column(DateTime(timezone=True), onupdate=func.now())


class MoMoTransaction(Base):
    """Audit log of every MTN Collection request we initiate.

    `reference_id` is the UUID we generated and sent as X-Reference-Id; it's
    also the key we use to poll status.
    """
    __tablename__ = "momo_transactions"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id       = Column(UUID(as_uuid=True),
                           ForeignKey("users.id", ondelete="CASCADE"),
                           nullable=False, index=True)
    plan_id       = Column(UUID(as_uuid=True),
                           ForeignKey("auto_save_plans.id", ondelete="SET NULL"),
                           nullable=True, index=True)
    goal_id       = Column(UUID(as_uuid=True),
                           ForeignKey("savings_goals.id", ondelete="SET NULL"),
                           nullable=True)
    reference_id  = Column(String(64), unique=True, nullable=False, index=True)
    external_id   = Column(String(64), nullable=False)
    amount        = Column(Float, nullable=False)
    currency      = Column(String(8), nullable=False, default="XAF")
    phone         = Column(String(20), nullable=False)
    status        = Column(String(20), nullable=False, default="PENDING")
    reason        = Column(Text, nullable=True)
    initiated_at  = Column(DateTime(timezone=True), server_default=func.now())
    completed_at  = Column(DateTime(timezone=True), nullable=True)
