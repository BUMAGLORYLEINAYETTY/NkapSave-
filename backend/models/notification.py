from sqlalchemy import (
    Column, String, DateTime, Boolean, ForeignKey, UniqueConstraint, Index,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from core.database import Base
import uuid


class PushToken(Base):
    """Per-device FCM registration token for a user.

    A user can have multiple devices; each device's token is unique.
    """
    __tablename__ = "push_tokens"
    __table_args__ = (
        UniqueConstraint("token", name="uq_push_tokens_token"),
        Index("ix_push_tokens_user_active", "user_id", "is_active"),
    )

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id    = Column(UUID(as_uuid=True),
                        ForeignKey("users.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    token      = Column(String(512), nullable=False)
    platform   = Column(String(20), nullable=False)  # ios | android | web
    device_id  = Column(String(120), nullable=True)
    is_active  = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())


class Notification(Base):
    """Persisted in-app notification record. Used both as the source of truth
    for the Notifications feed and as a delivery audit log for FCM pushes.
    """
    __tablename__ = "notifications"
    __table_args__ = (
        Index("ix_notifications_user_created", "user_id", "created_at"),
    )

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id    = Column(UUID(as_uuid=True),
                        ForeignKey("users.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    title      = Column(String(150), nullable=False)
    body       = Column(String(500), nullable=False)
    category   = Column(String(40), nullable=False, default="general")
    deep_link  = Column(String(300), nullable=True)
    read       = Column(Boolean, default=False, nullable=False)
    push_sent  = Column(Boolean, default=False, nullable=False)
    push_error = Column(String(300), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
