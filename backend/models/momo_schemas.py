"""Pydantic schemas for MoMo linking and auto-save plans."""
from datetime import datetime
from typing import List, Literal, Optional

from pydantic import BaseModel, Field


# ─── MoMo wallet link ──────────────────────────────────────────────

class LinkMoMoRequest(BaseModel):
    phone: str = Field(min_length=8, max_length=20)


class MoMoConnectionOut(BaseModel):
    id:           str
    provider:     str
    phone:        str
    verified:     bool
    last_verified_at: Optional[datetime]


# ─── Auto-save plan ────────────────────────────────────────────────

Frequency = Literal["daily", "weekly", "monthly"]


class CreateAutoSavePlanRequest(BaseModel):
    percent:   int = Field(ge=1, le=100)
    frequency: Frequency
    # Either `amount` is provided explicitly OR we compute it from
    # percent × `assumed_monthly_income` for the user.
    amount:                  Optional[float] = Field(default=None, gt=0)
    assumed_monthly_income:  Optional[float] = Field(default=None, gt=0)
    reminder_enabled:        bool = True
    # Hour (0-23) in WAT when the user wants the USSD prompt to arrive.
    # Default 8 = 8 AM morning deduction.
    preferred_hour:          int  = Field(default=8, ge=0, le=23)


class UpdateAutoSavePlanRequest(BaseModel):
    percent:          Optional[int]       = Field(default=None, ge=1, le=100)
    frequency:        Optional[Frequency] = None
    amount:           Optional[float]     = Field(default=None, gt=0)
    active:           Optional[bool]      = None
    reminder_enabled: Optional[bool]      = None
    preferred_hour:   Optional[int]       = Field(default=None, ge=0, le=23)


class AutoSavePlanOut(BaseModel):
    id:          str
    goal_id:     str
    percent:     int
    amount:      float
    frequency:   Frequency
    active:      bool
    next_run_at: datetime
    last_run_at: Optional[datetime]
    consecutive_failures: int
    reminder_enabled:     bool = True
    preferred_hour:       int  = 8


# ─── MoMo transaction log ──────────────────────────────────────────

class MoMoTransactionOut(BaseModel):
    id:           str
    reference_id: str
    amount:       float
    currency:     str
    status:       str         # PENDING|SUCCESSFUL|FAILED
    reason:       Optional[str]
    initiated_at: datetime
    completed_at: Optional[datetime]


class AutoSavePlanDetail(BaseModel):
    plan:         AutoSavePlanOut
    transactions: List[MoMoTransactionOut]


# ─── Savings dashboard insights ────────────────────────────────────

class UpcomingRunOut(BaseModel):
    plan_id:     str
    goal_id:     str
    goal_name:   str
    goal_emoji:  str
    amount:      float
    frequency:   str
    next_run_at: datetime


class ActivityItemOut(BaseModel):
    id:            str
    reference_id:  str
    goal_id:       Optional[str]
    goal_name:     Optional[str]
    goal_emoji:    Optional[str]
    amount:        float
    currency:      str
    status:        str          # PENDING|SUCCESSFUL|FAILED
    reason:        Optional[str]
    initiated_at:  datetime
    completed_at:  Optional[datetime]


class AllocationItemOut(BaseModel):
    goal_id:     str
    goal_name:   str
    goal_emoji:  str
    current:     float
    target:      float
    percent_of_total: float   # 0..100, share of total savings


class SavingsInsightsOut(BaseModel):
    lifetime_saved:        float
    monthly_saved:         float
    prev_month_saved:      float
    monthly_delta_pct:     float    # +Inf-safe: 0 if no prior month
    active_plans:          int
    completed_goals:       int
    locked_total:          float
    weekly_scheduled:      float    # sum of plan.amount × runs in next 7d
    upcoming:              List[UpcomingRunOut]
    recent_activity:       List[ActivityItemOut]
    allocation:            List[AllocationItemOut]
