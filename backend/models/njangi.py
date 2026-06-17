from sqlalchemy import (
    Column, String, Float, Boolean, DateTime, ForeignKey, Integer, Enum,
    UniqueConstraint, Index,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from core.database import Base
import uuid, enum


class GroupStatus(str, enum.Enum):
    PENDING   = "pending"
    ACTIVE    = "active"
    PAUSED    = "paused"
    COMPLETED = "completed"


class PayoutStatus(str, enum.Enum):
    PENDING = "pending"
    PAID    = "paid"
    PARTIAL = "partial"


class NjangiGroup(Base):
    __tablename__ = "njangi_groups"
    id             = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name           = Column(String(100), nullable=False)
    description    = Column(String(500), nullable=True)
    invite_code    = Column(String(6), unique=True, nullable=False, index=True)
    creator_id     = Column(UUID(as_uuid=True),
                            ForeignKey("users.id", ondelete="CASCADE"),
                            nullable=False, index=True)
    contribution   = Column(Float, nullable=False)
    frequency      = Column(String(20), default="Monthly")
    max_members    = Column(Integer, default=10)
    current_cycle  = Column(Integer, default=1)
    total_cycles   = Column(Integer, default=1)
    status         = Column(Enum(GroupStatus), default=GroupStatus.PENDING)
    escrow_balance = Column(Float, default=0.0)
    cycle_start_date = Column(DateTime(timezone=True), nullable=True)
    start_date     = Column(DateTime(timezone=True), nullable=True)
    created_at     = Column(DateTime(timezone=True), server_default=func.now())


class NjangiMember(Base):
    __tablename__ = "njangi_members"
    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_njangi_member_group_user"),
        Index("ix_njangi_members_user_group", "user_id", "group_id"),
    )

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    group_id     = Column(UUID(as_uuid=True),
                          ForeignKey("njangi_groups.id", ondelete="CASCADE"),
                          nullable=False, index=True)
    user_id      = Column(UUID(as_uuid=True),
                          ForeignKey("users.id", ondelete="CASCADE"),
                          nullable=False, index=True)
    position     = Column(Integer, nullable=False)
    trust_score  = Column(Float, default=100.0)
    has_paid     = Column(Boolean, default=False)
    payout_received = Column(Boolean, default=False)
    is_admin        = Column(Boolean, default=False)
    joined_at    = Column(DateTime(timezone=True), server_default=func.now())


class NjangiContribution(Base):
    __tablename__ = "njangi_contributions"
    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    group_id   = Column(UUID(as_uuid=True),
                        ForeignKey("njangi_groups.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    member_id  = Column(UUID(as_uuid=True),
                        ForeignKey("njangi_members.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    amount     = Column(Float, nullable=False)
    cycle      = Column(Integer, nullable=False)
    provider   = Column(String(30), default="MTN Money")
    # MoMo payment tracking. New contributions start "pending" and only
    # flip to "successful" once Campay confirms the Collect; "failed"
    # contributions don't count toward `has_paid`. Pre-existing rows (from
    # before this column existed) default to "successful" since they were
    # created at the moment a contribution was recorded as paid.
    status         = Column(String(20), nullable=False, default="successful")
    momo_reference = Column(String(64), nullable=True)
    phone          = Column(String(20), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class NjangiMessage(Base):
    """One chat message in a njangi group. Membership at the time of
    posting is enforced at the route layer; rows persist even if the
    sender later leaves the group so history stays readable."""
    __tablename__ = "njangi_messages"
    __table_args__ = (
        Index("ix_njangi_messages_group_created", "group_id", "created_at"),
    )

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    group_id   = Column(UUID(as_uuid=True),
                        ForeignKey("njangi_groups.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    sender_id  = Column(UUID(as_uuid=True),
                        ForeignKey("users.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    content    = Column(String(2000), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class NjangiPayout(Base):
    """One row per cycle payout. Recorded when every member has paid for
    the current cycle and the recipient (positioned at current_cycle) gets
    paid out. Persisting this in its own table keeps history queryable
    even after `current_cycle` advances and `payout_received` flags reset.
    """
    __tablename__ = "njangi_payouts"
    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    group_id      = Column(UUID(as_uuid=True),
                           ForeignKey("njangi_groups.id", ondelete="CASCADE"),
                           nullable=False, index=True)
    recipient_id  = Column(UUID(as_uuid=True),
                           ForeignKey("njangi_members.id", ondelete="CASCADE"),
                           nullable=False, index=True)
    cycle         = Column(Integer, nullable=False)
    # Gross = contribution * members; net is what actually paid out
    # (gross * trust_score / 100); escrow holds the rest.
    gross_amount  = Column(Float, nullable=False)
    net_amount    = Column(Float, nullable=False)
    escrow_amount = Column(Float, default=0.0)
    trust_score   = Column(Float, nullable=False)
    created_at    = Column(DateTime(timezone=True), server_default=func.now())
