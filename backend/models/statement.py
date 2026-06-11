"""Persistent monthly statement records.

Each Statement holds the full PDF bytes so the user can re-download forever,
and a JSON record of which channels we tried to notify on (email, whatsapp,
in_app). This is what makes "users without email" work: we always have the
PDF in-app even when we can't deliver it elsewhere.

Unique on (user_id, period_year, period_month) — re-generating a statement
for the same month overwrites the previous version.
"""
from sqlalchemy import (
    Column, String, DateTime, ForeignKey, Integer, LargeBinary, Index,
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.sql import func
from core.database import Base
import uuid


class Statement(Base):
    __tablename__ = "statements"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id       = Column(UUID(as_uuid=True),
                            ForeignKey("users.id", ondelete="CASCADE"),
                            nullable=False, index=True)
    period_year   = Column(Integer, nullable=False)
    period_month  = Column(Integer, nullable=False)        # 1..12
    period_label  = Column(String(40), nullable=False)
    pdf_bytes     = Column(LargeBinary, nullable=False)
    size_bytes    = Column(Integer, nullable=False, default=0)
    # JSON: {"email": "sent"|"failed"|"skipped",
    #        "whatsapp": "sent"|"failed"|"skipped",
    #        "in_app": "sent"}
    channels      = Column(JSONB, nullable=False, default=dict)
    created_at    = Column(DateTime(timezone=True),
                            server_default=func.now())

    __table_args__ = (
        Index("ix_statements_user_period",
              "user_id", "period_year", "period_month",
              unique=True),
    )
