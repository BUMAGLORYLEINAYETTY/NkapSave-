from pydantic import BaseModel
from typing import List, Optional
 
# ── Auth ──────────────────────────────────────────────────────
class RegisterRequest(BaseModel):
    full_name: str
    email: str
    phone: str
    password: str
 
class LoginRequest(BaseModel):
    email: str
    password: str
 
class TokenResponse(BaseModel):
    access_token:  str
    refresh_token: str
    token_type:    str = "bearer"
    user_id:       str
    full_name:     str
    email:         str
 
# ── Transactions ──────────────────────────────────────────────
class TransactionOut(BaseModel):
    id:        str
    name:      str
    category:  str
    amount:    float
    date:      str
    color_hex: str
 
class AddTransactionRequest(BaseModel):
    name:     str
    category: str
    amount:   float
    note:     Optional[str] = None
 
# ── Dashboard ─────────────────────────────────────────────────
class WeeklySpendPoint(BaseModel):
    day:    str
    amount: float
 
class NjangiAlertOut(BaseModel):
    group_name: str
    amount:     float
 
class DashboardResponse(BaseModel):
    total_balance:            float
    monthly_income:           float
    monthly_expenses:         float
    saved_this_month:         float
    auto_save_active:         bool
    auto_save_percent:        int
    weekly_spend:             List[WeeklySpendPoint]
    recent_transactions:      List[TransactionOut]
    njangi_alert:             Optional[NjangiAlertOut] = None
    savings_progress:         float
    spending_vs_last_month:   float
