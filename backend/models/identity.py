"""KYC / identity verification.

One row per submission; a user may resubmit after a rejection so this is
not a 1-1 with `users`. The latest row (by `submitted_at`) is the source
of truth for "am I verified right now?". `users.is_verified` is a
denormalised mirror that lets hot-path checks (join group, payout, etc.)
avoid joining this table on every request.

Document paths are private — they're served via an admin-gated route,
never returned in the public profile payload.
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, Enum, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from core.database import Base
import uuid, enum


class VerificationStatus(str, enum.Enum):
    PENDING  = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class IdentityVerification(Base):
    __tablename__ = "identity_verifications"
    __table_args__ = (
        Index("ix_kyc_user_submitted", "user_id", "submitted_at"),
        Index("ix_kyc_status_submitted", "status", "submitted_at"),
    )

    id              = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id         = Column(UUID(as_uuid=True),
                             ForeignKey("users.id", ondelete="CASCADE"),
                             nullable=False, index=True)
    # Cameroon CNI number, free-text — we don't enforce format because the
    # ID layout has shifted across issuances. Stored as-given; verified
    # visually by the admin reviewer against the uploaded scans.
    cni_number      = Column(String(40), nullable=False)
    cni_front_path  = Column(String(500), nullable=False)
    cni_back_path   = Column(String(500), nullable=False)
    selfie_path     = Column(String(500), nullable=False)
    status          = Column(Enum(VerificationStatus),
                             default=VerificationStatus.PENDING,
                             nullable=False)
    # Set when an admin acts on this submission.
    reviewer_id     = Column(UUID(as_uuid=True),
                             ForeignKey("users.id", ondelete="SET NULL"),
                             nullable=True)
    reviewer_notes  = Column(String(500), nullable=True)
    submitted_at    = Column(DateTime(timezone=True),
                             server_default=func.now(), nullable=False)
    # Earliest moment a reviewer is allowed to approve/reject this row.
    # Set on submission to submitted_at + REVIEW_MIN_WAIT (5 min) so the
    # reviewer can't rubber-stamp; the admin UI shows a countdown until
    # this passes. Nullable so older rows (pre-migration) don't enforce
    # the gate retroactively.
    earliest_decision_at = Column(DateTime(timezone=True), nullable=True)
    reviewed_at     = Column(DateTime(timezone=True), nullable=True)
