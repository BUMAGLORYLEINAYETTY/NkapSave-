from sqlalchemy import Column, String, DateTime, ForeignKey, Boolean, Integer
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from core.database import Base
import uuid

class ReminderLog(Base):
    __tablename__ = "reminder_logs"
    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id     = Column(UUID(as_uuid=True),
                         ForeignKey("users.id", ondelete="CASCADE"),
                         nullable=False, index=True)
    group_id    = Column(UUID(as_uuid=True),
                         ForeignKey("njangi_groups.id", ondelete="CASCADE"),
                         nullable=False, index=True)
    cycle       = Column(Integer, nullable=False)
    channel     = Column(String(20), nullable=False)  # whatsapp | sms | both
    message     = Column(String(500), nullable=False)
    delivered   = Column(Boolean, default=True)
    sent_at     = Column(DateTime(timezone=True), server_default=func.now())
