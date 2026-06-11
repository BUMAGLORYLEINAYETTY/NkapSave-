from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

class CreateGoalRequest(BaseModel):
    name:     str
    emoji:    str   = "🎯"
    target:   float = Field(gt=0)
    note:     Optional[str] = None
    deadline: Optional[datetime] = None

class AddFundsRequest(BaseModel):
    amount: float = Field(gt=0)

class GoalOut(BaseModel):
    id:           str
    name:         str
    emoji:        str
    target:       float
    current:      float
    percent:      float
    remaining:    float
    is_locked:    bool
    is_completed: bool
    months_left:  int
    deadline:     Optional[datetime] = None
    note:         Optional[str] = None
 
class AutoSaveUpdateRequest(BaseModel):
    percent:  int  = Field(ge=1, le=100)
    provider: str  = "MTN Money"
    active:   bool = True
 
class SavingsResponse(BaseModel):
    total_saved:       float
    total_target:      float
    overall_percent:   float
    saved_this_month:  float
    auto_save_active:  bool
    auto_save_percent: int
    auto_save_provider: str
    goals:             List[GoalOut]
