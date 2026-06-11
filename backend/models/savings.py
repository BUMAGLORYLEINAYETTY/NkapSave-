from sqlalchemy import Column, String, Float, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from core.database import Base
import uuid
 
class SavingsGoal(Base):
    __tablename__ = "savings_goals"
 
    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id      = Column(UUID(as_uuid=True),
                          ForeignKey("users.id", ondelete="CASCADE"),
                          nullable=False, index=True)
    name         = Column(String(100), nullable=False)
    emoji        = Column(String(10), default="🎯")
    target       = Column(Float, nullable=False)
    current      = Column(Float, default=0.0)
    is_locked    = Column(Boolean, default=True)
    is_completed = Column(Boolean, default=False)
    note         = Column(Text, nullable=True)
    deadline     = Column(DateTime(timezone=True), nullable=True)
    created_at   = Column(DateTime(timezone=True), server_default=func.now())
    updated_at   = Column(DateTime(timezone=True), onupdate=func.now())
