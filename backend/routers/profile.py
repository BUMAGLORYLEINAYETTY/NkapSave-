from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional
import os, uuid as uuidlib
from core.database import get_db
from core.security import get_current_user
from models.user import User

router = APIRouter(prefix="/profile", tags=["Profile"])

UPLOAD_DIR = "uploads/profiles"
os.makedirs(UPLOAD_DIR, exist_ok=True)

class UpdateProfileRequest(BaseModel):
    full_name:           Optional[str] = None
    phone:               Optional[str] = None
    bio:                 Optional[str] = None
    location:            Optional[str] = None
    occupation:          Optional[str] = None
    income_bracket:      Optional[str] = None
    preferred_language:  Optional[str] = None

class ProfileOut(BaseModel):
    id:                  str
    full_name:           str
    email:               str
    phone:               str
    profile_picture:     Optional[str] = None
    bio:                 Optional[str] = None
    location:            Optional[str] = None
    occupation:          Optional[str] = None
    income_bracket:      Optional[str] = None
    preferred_language:  Optional[str] = None
    trust_score:         float
    total_balance:       float
    is_verified:         bool = False

@router.get("/me", response_model=ProfileOut)
async def get_my_profile(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(select(User).where(User.id == current_user["user_id"]))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return ProfileOut(
        id=str(user.id), full_name=user.full_name, email=user.email,
        phone=user.phone or "", profile_picture=user.profile_picture,
        bio=user.bio, location=user.location, occupation=user.occupation,
        income_bracket=user.income_bracket,
        preferred_language=user.preferred_language,
        trust_score=user.trust_score, total_balance=user.total_balance,
        is_verified=user.is_verified,
    )

@router.get("/{user_id}", response_model=ProfileOut)
async def get_user_profile(
    user_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(select(User).where(User.id == user_id))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return ProfileOut(
        id=str(user.id), full_name=user.full_name, email=user.email,
        phone=user.phone or "", profile_picture=user.profile_picture,
        bio=user.bio, location=user.location, occupation=user.occupation,
        income_bracket=None,           # keep private
        preferred_language=None,       # keep private
        trust_score=user.trust_score, total_balance=0.0,  # hide balance from others
        is_verified=user.is_verified,  # public — peers should see this badge
    )

@router.patch("/me", response_model=ProfileOut)
async def update_profile(
    body: UpdateProfileRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(select(User).where(User.id == current_user["user_id"]))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if body.full_name is not None: user.full_name = body.full_name
    if body.phone is not None:     user.phone = body.phone
    if body.bio is not None:       user.bio = body.bio
    if body.location is not None:  user.location = body.location
    if body.occupation is not None: user.occupation = body.occupation
    if body.income_bracket is not None:
        # Light validation — keep in sync with INCOME_BRACKET_MIDPOINTS.
        if body.income_bracket not in {
            "under_50k", "50k_100k", "100k_300k",
            "300k_500k", "500k_1m", "over_1m",
        }:
            raise HTTPException(status_code=422, detail="Unknown income bracket.")
        user.income_bracket = body.income_bracket
    if body.preferred_language is not None:
        if body.preferred_language not in {"en", "fr", "pidgin"}:
            raise HTTPException(status_code=422, detail="Unknown language.")
        user.preferred_language = body.preferred_language
    await db.flush()
    return ProfileOut(
        id=str(user.id), full_name=user.full_name, email=user.email,
        phone=user.phone or "", profile_picture=user.profile_picture,
        bio=user.bio, location=user.location, occupation=user.occupation,
        income_bracket=user.income_bracket,
        preferred_language=user.preferred_language,
        trust_score=user.trust_score, total_balance=user.total_balance,
        is_verified=user.is_verified,
    )

@router.post("/me/picture")
async def upload_picture(
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Validate file type
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image")

    # Save with unique name
    ext = os.path.splitext(file.filename or "img.jpg")[1] or ".jpg"
    filename = str(uuidlib.uuid4()) + ext
    filepath = os.path.join(UPLOAD_DIR, filename)

    contents = await file.read()
    if len(contents) > 5 * 1024 * 1024:  # 5MB limit
        raise HTTPException(status_code=400, detail="File too large (max 5MB)")

    with open(filepath, "wb") as f:
        f.write(contents)

    # Update user record with URL
    res = await db.execute(select(User).where(User.id == current_user["user_id"]))
    user = res.scalar_one()
    public_url = "/api/v1/profile/picture/" + filename
    user.profile_picture = public_url
    await db.flush()

    return {"message": "Picture uploaded", "url": public_url}

@router.get("/picture/{filename}")
async def get_picture(filename: str):
    filepath = os.path.join(UPLOAD_DIR, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="Picture not found")
    return FileResponse(filepath)
