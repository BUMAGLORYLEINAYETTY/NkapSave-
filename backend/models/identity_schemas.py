from pydantic import BaseModel, Field
from typing import Optional, List


class VerificationStatusOut(BaseModel):
    """Returned to the owning user. Hides document paths — those are
    only readable by reviewers via a separate admin endpoint."""
    status:          str                    # 'unsubmitted' | 'pending' | 'approved' | 'rejected'
    cni_number:      Optional[str] = None   # last 4 only, redacted client-side anyway
    submitted_at:    Optional[str] = None
    reviewed_at:     Optional[str] = None
    reviewer_notes:  Optional[str] = None
    can_resubmit:    bool = True


class PendingVerificationOut(BaseModel):
    """Admin view — includes everything a reviewer needs to make a call."""
    id:              str
    user_id:         str
    user_name:       str
    user_email:      str
    user_phone:      Optional[str] = None
    cni_number:      str
    cni_front_url:   str
    cni_back_url:    str
    selfie_url:      str
    status:          str
    submitted_at:    str
    reviewed_at:     Optional[str] = None
    reviewer_notes:  Optional[str] = None


class PendingListResponse(BaseModel):
    items: List[PendingVerificationOut]


class ReviewDecisionRequest(BaseModel):
    notes: Optional[str] = Field(default=None, max_length=500)
