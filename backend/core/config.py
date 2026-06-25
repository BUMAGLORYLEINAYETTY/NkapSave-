from typing import List, Optional
from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # ── Core ─────────────────────────────────────────────────
    DATABASE_URL: str
    SECRET_KEY: str

    @field_validator("DATABASE_URL", mode="before")
    @classmethod
    def coerce_async_db_url(cls, v: str) -> str:
        """Railway injects postgresql:// — asyncpg needs postgresql+asyncpg://."""
        if v.startswith("postgresql://") or v.startswith("postgres://"):
            return v.replace("://", "+asyncpg://", 1)
        return v
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30
    APP_NAME: str = "NkapSave"
    APP_VERSION: str = "1.0.0"
    ENVIRONMENT: str = "development"  # development | staging | production
    # Public URL used to build email links (verification, statements).
    # Set to your production domain in prod (e.g. https://nkapsave.com).
    APP_BASE_URL: str = "http://localhost:8000"

    # ── Feature flags ────────────────────────────────────────
    # CNI / identity verification flow. Off while we redesign the review
    # pipeline. When false: /api/v1/kyc/* is unregistered (see main.py)
    # and `_require_verified` short-circuits so njangi money endpoints
    # don't 403 users who can't submit ID anyway.
    KYC_ENABLED: bool = False

    # Demo / presentation mode. When true, MoMo API calls are simulated
    # (no real Fapshi requests) so auto-save and Njangi payments succeed
    # instantly without real credentials or USSD prompts.
    # NEVER enable in production.
    DEMO_MODE: bool = False

    # ── CORS ─────────────────────────────────────────────────
    # Comma-separated list of allowed origins. Empty in prod = locked down.
    ALLOWED_ORIGINS: str = "http://localhost:3000,http://127.0.0.1:3000"

    # ── Reminder delivery (Twilio) ───────────────────────────
    REMINDER_PROVIDER: str = "twilio"
    TWILIO_ACCOUNT_SID: Optional[str] = None
    TWILIO_AUTH_TOKEN: Optional[str] = None
    TWILIO_FROM_NUMBER: Optional[str] = None       # e.g. +15555550123 (SMS)
    TWILIO_WHATSAPP_FROM: Optional[str] = None     # e.g. whatsapp:+14155238886

    # ── Push notifications (Firebase Cloud Messaging) ────────
    # Path to a service-account JSON file (server-side credential).
    FCM_CREDENTIALS_PATH: Optional[str] = None
    FCM_PROJECT_ID: Optional[str] = None

    # ── Email (SMTP — monthly statements & on-demand reports) ─
    # Leave SMTP_HOST blank to disable email entirely.
    # For Gmail: host=smtp.gmail.com, port=587, user=you@gmail, pass=APP_PASSWORD
    SMTP_HOST:     Optional[str] = None
    SMTP_PORT:     int           = 587
    SMTP_USER:     Optional[str] = None
    SMTP_PASSWORD: Optional[str] = None
    SMTP_FROM:     Optional[str] = None     # "NkapSave <hello@example.com>"
    SMTP_STARTTLS: bool          = True
    # Hour (UTC) on the 1st of each month when statements go out.
    STATEMENT_HOUR_UTC: int      = 6

    # ── Fapshi (Cameroon-native MoMo aggregator) ─────────────
    # Sandbox: sandboxapi.fapshi.com  |  Production: live.fapshi.com
    # Sign up at https://fapshi.com → Dashboard → API Credentials.
    # Each service has its own apiuser + apikey pair.
    FAPSHI_ENV: str = "sandbox"
    FAPSHI_COLLECTION_USER: Optional[str] = None  # apiuser for pay-in
    FAPSHI_COLLECTION_KEY:  Optional[str] = None  # apikey  for pay-in
    FAPSHI_PAYOUT_USER:     Optional[str] = None  # apiuser for pay-out
    FAPSHI_PAYOUT_KEY:      Optional[str] = None  # apikey  for pay-out

    # Default phone country code for normalization (Cameroon = 237).
    DEFAULT_COUNTRY_CODE: str = "237"

    # ── NkapBot (Anthropic Claude) ───────────────────────────
    # Required for the chatbot. Without it the /nkapbot/chat endpoint returns
    # a graceful fallback message — context retrieval still works.
    ANTHROPIC_API_KEY: Optional[str] = None
    # Model + token budget. Override per environment if you want cheaper/faster.
    ANTHROPIC_MODEL: str = "claude-sonnet-4-6"
    ANTHROPIC_MAX_TOKENS: int = 1000

    # ── NkapBot semantic RAG (embeddings) ────────────────────
    # The chatbot retrieves financial-literacy passages by *meaning* (not just
    # keywords) and feeds the best matches to Claude. Retrieval needs an
    # embedding model. Provider selection:
    #   auto   → Voyage if VOYAGE_API_KEY set, else local lib if installed,
    #            else a deterministic lexical fallback (works with no key, but
    #            lower quality — set a real provider for production).
    #   voyage → Voyage AI (recommended; multilingual, generous free tier).
    #   openai → OpenAI embeddings.
    #   local  → sentence-transformers running on this machine (offline, free;
    #            `pip install sentence-transformers`).
    #   hash   → deterministic lexical fallback (no deps, no key — dev/testing).
    RAG_ENABLED: bool = True
    EMBEDDING_PROVIDER: str = "auto"
    # Leave EMBEDDING_MODEL blank to use each provider's sensible default
    # (voyage-3.5 / text-embedding-3-small / multilingual MiniLM).
    EMBEDDING_MODEL: Optional[str] = None
    # Dimensionality used only by the `hash` fallback provider.
    EMBEDDING_DIM: int = 256
    # Embedding-provider API keys (Voyage is Anthropic's recommended partner).
    VOYAGE_API_KEY: Optional[str] = None
    OPENAI_API_KEY: Optional[str] = None

    # ── Resend (transactional email — preferred over SMTP on Railway) ─────────
    # Sign up at https://resend.com — free tier: 3,000 emails/month.
    # When set, Resend is used instead of SMTP (Railway blocks port 587).
    RESEND_API_KEY: Optional[str] = None
    # Retrieval tuning: how many passages to inject and the minimum cosine
    # similarity a passage must clear to be considered relevant.
    RAG_TOP_K: int = 4
    RAG_MIN_SCORE: float = 0.20

    @field_validator("SECRET_KEY")
    @classmethod
    def secret_key_must_be_strong(cls, v: str) -> str:
        if not v or len(v) < 32:
            raise ValueError(
                "SECRET_KEY must be at least 32 characters. "
                "Generate one with: python -c \"import secrets; print(secrets.token_urlsafe(48))\""
            )
        if "change-in-production" in v.lower() or "super-secret" in v.lower():
            raise ValueError(
                "SECRET_KEY looks like a placeholder. Rotate it before starting."
            )
        return v

    @property
    def cors_origins(self) -> List[str]:
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",") if o.strip()]

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT.lower() == "production"


settings = Settings()
