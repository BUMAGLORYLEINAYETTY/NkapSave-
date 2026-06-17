from sqlalchemy import Column, String, Boolean, DateTime, Float, Integer
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from core.database import Base
import uuid
 
class User(Base):
    __tablename__ = "users"
 
    id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    full_name     = Column(String(100), nullable=False)
    email         = Column(String(150), unique=True, nullable=False, index=True)
    phone         = Column(String(20),  unique=True, nullable=True)
    password_hash = Column(String(255), nullable=False)
    pin_hash      = Column(String(255), nullable=True)
    is_active     = Column(Boolean, default=True)
    is_verified   = Column(Boolean, default=False)
    # Grants access to the KYC admin review queue. Granted manually in
    # the database — there's no self-service path to become a reviewer.
    is_kyc_reviewer = Column(Boolean, default=False)
    total_balance = Column(Float,   default=0.0)
    trust_score   = Column(Float,   default=100.0)
    auto_save_pct = Column(Integer, default=10)
    auto_save_on  = Column(Boolean, default=False)
    profile_picture = Column(String(500), nullable=True)
    bio             = Column(String(300), nullable=True)
    location        = Column(String(100), nullable=True)
    occupation      = Column(String(100), nullable=True)
    date_of_birth   = Column(String(20), nullable=True)
    city            = Column(String(100), nullable=True)
    email_verified      = Column(Boolean, default=False, nullable=False)
    email_verify_token  = Column(String(64), nullable=True)
    # NkapBot personalisation
    # Discrete bracket so the prompt builder can pick a midpoint without parsing
    # free text. See INCOME_BRACKET_MIDPOINTS in services/nkapbot_context_service.py.
    # Allowed: under_50k, 50k_100k, 100k_300k, 300k_500k, 500k_1m, over_1m.
    income_bracket     = Column(String(20), nullable=True)
    # ISO-ish language tag the bot replies in. Allowed: en, fr, pidgin.
    preferred_language = Column(String(10), nullable=True, default="en")
    created_at    = Column(DateTime(timezone=True), server_default=func.now())
    updated_at    = Column(DateTime(timezone=True), onupdate=func.now())
