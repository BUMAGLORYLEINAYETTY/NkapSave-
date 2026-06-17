from pydantic import BaseModel, Field
from typing import List, Optional

class CreateGroupRequest(BaseModel):
    name:         str
    description:  Optional[str] = None
    contribution: float = Field(gt=0)
    frequency:    str   = "Monthly"
    max_members:  int   = Field(ge=2, default=10)
    start_date:   Optional[str] = None  # ISO date string

class JoinGroupRequest(BaseModel):
    invite_code: str

class ContributeRequest(BaseModel):
    phone:    str   # local 9-digit MSISDN, e.g. "670000000"
    provider: str   # "MTN" | "Orange" — display/logging only; Campay routes by number

class MemberOut(BaseModel):
    id:              str
    position:        int
    user_id:         str
    name:            str
    profile_picture: Optional[str] = None
    bio:             Optional[str] = None
    trust_score:     float
    has_paid:        bool
    payout_received: bool
    is_me:           bool
    is_admin:        bool = False
    # Whether this member has cleared CNI/KYC verification. Surfaced on
    # member rows in the app so peers can see at a glance who's been
    # ID-verified. Defaults to False so older clients still parse.
    is_verified:     bool = False

class GroupOut(BaseModel):
    id:             str
    name:           str
    description:    Optional[str] = None
    invite_code:    str
    contribution:   float
    frequency:      str
    max_members:    int
    member_count:   int
    current_cycle:  int
    total_cycles:   int
    status:         str
    my_position:    int
    is_admin:       bool = False
    my_trust_score: float
    pool_amount:    float
    is_my_turn:     bool
    next_recipient: str
    members:        List[MemberOut]
    progress_pct:   float

class NjangiResponse(BaseModel):
    groups:      List[GroupOut]
    trust_score: float


# ── Group chat ──────────────────────────────────────────────
class SendMessageRequest(BaseModel):
    content: str = Field(min_length=1, max_length=2000)


class MessageOut(BaseModel):
    id:              str
    group_id:        str
    sender_id:       str
    sender_name:     str
    sender_picture:  Optional[str] = None
    content:         str
    created_at:      str
    is_me:           bool


class MessagesResponse(BaseModel):
    messages: List[MessageOut]
