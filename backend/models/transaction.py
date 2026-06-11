from sqlalchemy import Column, String, Float, DateTime, ForeignKey, Enum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from core.database import Base
import uuid, enum
 
class TxCategory(str, enum.Enum):
    INCOME    = "Income"
    FOOD      = "Food & Drink"
    TRANSPORT = "Transport"
    UTILITIES = "Utilities"
    SHOPPING  = "Shopping"
    HOUSING   = "Housing"
    HEALTH    = "Health"
    NJANGI    = "Njangi"
    SAVINGS   = "Savings"
    OTHER     = "Other"
 
class Transaction(Base):
    __tablename__ = "transactions"
 
    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id    = Column(UUID(as_uuid=True),
                        ForeignKey("users.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    name       = Column(String(150), nullable=False)
    category   = Column(Enum(TxCategory), nullable=False)
    amount     = Column(Float, nullable=False)
    note       = Column(String(300), nullable=True)
    source     = Column(String(50), default="manual")
    created_at = Column(DateTime(timezone=True),
                        server_default=func.now(), index=True)
