import asyncio
import secrets
from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from pydantic import BaseModel, Field, EmailStr, validator
from typing import Optional
import re
from core.database import get_db
from core.security import (
    hash_password, verify_password, create_access_token,
    create_refresh_token,
)
from jose import jwt, JWTError
from core.config import settings
from models.user import User
from services.email_service import send_email

router = APIRouter(prefix="/auth", tags=["Authentication"])

# ═══════════════════════════════════════════════════════════════
# Schemas
# ═══════════════════════════════════════════════════════════════

PHONE_MIN_DIGITS = 9  # Cameroon mobile numbers are 9 digits without country code.


def _digits(s: str) -> str:
    return re.sub(r"[^0-9]", "", s or "")


class RegisterRequest(BaseModel):
    full_name:     str = Field(..., min_length=3, max_length=100)
    email:         EmailStr
    phone:         str = Field(..., min_length=9)
    password:      str = Field(..., min_length=6)
    date_of_birth: Optional[str] = None
    city:          Optional[str] = None

    @validator("phone")
    def validate_phone(cls, v):
        if len(_digits(v)) < PHONE_MIN_DIGITS:
            raise ValueError(f"Phone must have at least {PHONE_MIN_DIGITS} digits")
        return v

    @validator("password")
    def validate_password(cls, v):
        if len(v) < 6:
            raise ValueError("Password must be at least 6 characters")
        if not re.search(r"\d", v):
            raise ValueError("Password must contain at least one number")
        return v


class LoginRequest(BaseModel):
    """Login is email-only. Phone/full-name identifiers are no longer accepted."""
    identifier: EmailStr
    password:   str = Field(..., min_length=1)


class LoginResponseV2(BaseModel):
    access_token:  str
    refresh_token: str
    token_type:    str = "bearer"
    user_id:       str
    full_name:     str
    email:         str


class RegisterResponse(BaseModel):
    message: str
    email:   str


class ResendRequest(BaseModel):
    email: str  # validated manually so we never 422 — always return 200


class RefreshRequest(BaseModel):
    refresh_token: str


def _build_token_response(user: User) -> LoginResponseV2:
    return LoginResponseV2(
        access_token=create_access_token({"sub": str(user.id), "email": user.email}),
        refresh_token=create_refresh_token({"sub": str(user.id)}),
        user_id=str(user.id),
        full_name=user.full_name,
        email=user.email,
    )


# ═══════════════════════════════════════════════════════════════
# Email helper
# ═══════════════════════════════════════════════════════════════

async def _send_verification_email(email: str, token: str) -> None:
    verify_url = (
        f"{settings.APP_BASE_URL}/api/v1/auth/verify-email?token={token}"
    )
    html = f"""
<!DOCTYPE html>
<html>
<body style="font-family:Arial,sans-serif;background:#0D0D14;margin:0;padding:40px 20px;">
  <div style="max-width:520px;margin:0 auto;background:#1A1A2E;border-radius:16px;
              padding:40px;border:1px solid #2A2A4A;">
    <div style="text-align:center;margin-bottom:32px;">
      <div style="background:#A855F7;width:60px;height:60px;border-radius:14px;
                  margin:0 auto 16px;line-height:60px;font-size:28px;">💜</div>
      <h1 style="color:#F1F1F9;font-size:22px;margin:0 0 6px;">NkapSave</h1>
      <p style="color:#8B8BA7;margin:0;font-size:14px;">
        Intelligent financial management for Cameroon
      </p>
    </div>
    <h2 style="color:#F1F1F9;font-size:18px;margin:0 0 12px;">
      Verify your email address
    </h2>
    <p style="color:#C5C5D8;line-height:1.6;margin:0 0 28px;font-size:15px;">
      Thanks for creating your NkapSave account! Click the button below to
      confirm your email address and activate your account.
    </p>
    <div style="text-align:center;margin-bottom:32px;">
      <a href="{verify_url}"
         style="background:#A855F7;color:#fff;text-decoration:none;
                padding:14px 36px;border-radius:12px;font-weight:700;
                font-size:16px;display:inline-block;">
        Verify Email Address
      </a>
    </div>
    <p style="color:#8B8BA7;font-size:13px;text-align:center;margin:0 0 8px;">
      Button not working? Copy and paste this link in your browser:
    </p>
    <p style="color:#A855F7;font-size:12px;word-break:break-all;
              text-align:center;margin:0 0 32px;">
      {verify_url}
    </p>
    <hr style="border:none;border-top:1px solid #2A2A4A;margin:0 0 20px;">
    <p style="color:#8B8BA7;font-size:12px;text-align:center;margin:0;">
      This link expires in 24 hours. If you didn't create a NkapSave account,
      you can safely ignore this email.
    </p>
  </div>
</body>
</html>
"""
    await send_email(
        to=email,
        subject="Verify your NkapSave email address",
        html=html,
    )


# ═══════════════════════════════════════════════════════════════
# Endpoints
# ═══════════════════════════════════════════════════════════════

@router.post("/register", response_model=RegisterResponse, status_code=201)
async def register(body: RegisterRequest, db: AsyncSession = Depends(get_db)):
    email = body.email.lower().strip()
    phone_digits = _digits(body.phone)
    last9 = phone_digits[-PHONE_MIN_DIGITS:]

    res = await db.execute(select(User).where(User.email == email))
    if res.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="An account with this email already exists")

    phone_norm = func.regexp_replace(User.phone, r"[^0-9]", "", "g")
    res = await db.execute(
        select(User).where(func.right(phone_norm, PHONE_MIN_DIGITS) == last9)
    )
    if res.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="An account with this phone already exists")

    token = secrets.token_urlsafe(32)
    user = User(
        full_name=body.full_name.strip(),
        email=email,
        phone=body.phone.strip(),
        password_hash=hash_password(body.password),
        date_of_birth=body.date_of_birth,
        city=body.city,
        email_verified=False,
        email_verify_token=token,
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)

    # Fire verification email without blocking the response. asyncio.create_task
    # schedules it on the running event loop immediately and the HTTP response
    # is returned to the client before the SMTP handshake begins.
    async def _send_quietly() -> None:
        try:
            await _send_verification_email(email, token)
            logger.info("Verification email sent to %s", email)
        except Exception as exc:
            logger.error("Verification email FAILED for %s: %s", email, exc)

    asyncio.create_task(_send_quietly())

    return RegisterResponse(
        message=(
            "Account created! We've sent a verification link to your email. "
            "Please check your inbox (and spam folder) to activate your account."
        ),
        email=email,
    )


@router.get("/verify-email", include_in_schema=True)
async def verify_email(token: str, db: AsyncSession = Depends(get_db)):
    """Clicked from the verification email — marks the account active and
    redirects the browser to the login screen."""
    res = await db.execute(
        select(User).where(User.email_verify_token == token)
    )
    user = res.scalar_one_or_none()

    if not user:
        return RedirectResponse(
            url=f"{settings.APP_BASE_URL}/login?verified=error",
            status_code=302,
        )

    user.email_verified = True
    user.email_verify_token = None
    await db.commit()

    return RedirectResponse(
        url=f"{settings.APP_BASE_URL}/login?verified=true",
        status_code=302,
    )


@router.post("/resend-verification", status_code=200)
async def resend_verification(body: ResendRequest, db: AsyncSession = Depends(get_db)):
    """Re-send the verification email. Always returns 200 to avoid
    leaking whether the address is registered."""
    email = body.email.lower().strip()
    if not email or '@' not in email:
        return {"message": "If that email address is registered and unverified, a new link has been sent."}

    res = await db.execute(select(User).where(User.email == email))
    user = res.scalar_one_or_none()

    if user and not user.email_verified:
        token = secrets.token_urlsafe(32)
        user.email_verify_token = token
        await db.commit()
        try:
            await _send_verification_email(email, token)
        except Exception:
            pass

    return {"message": "If that email address is registered and unverified, a new link has been sent."}


@router.post("/login", response_model=LoginResponseV2)
async def login(body: LoginRequest, db: AsyncSession = Depends(get_db)):
    """Login is email-only. EmailStr in LoginRequest rejects malformed addresses
    at the schema layer (422). Unknown-but-syntactically-valid emails fall
    through to the generic 401 so attackers can't enumerate accounts."""
    email = body.identifier.lower().strip()
    res = await db.execute(select(User).where(User.email == email))
    user = res.scalar_one_or_none()
    if not user or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not user.email_verified:
        raise HTTPException(
            status_code=403,
            detail="email_not_verified",
        )
    return _build_token_response(user)


@router.post("/refresh", response_model=LoginResponseV2)
async def refresh_token(body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    try:
        payload = jwt.decode(
            body.refresh_token, settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
        if payload.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="Invalid refresh token")
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    res = await db.execute(select(User).where(User.id == user_id))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return _build_token_response(user)
