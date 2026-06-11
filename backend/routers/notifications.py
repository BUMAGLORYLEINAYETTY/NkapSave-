from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, update, delete
from sqlalchemy.ext.asyncio import AsyncSession

from core.database import get_db
from core.security import get_current_user
from models.notification import Notification, PushToken

router = APIRouter(prefix="/notifications", tags=["Notifications"])

VALID_PLATFORMS = {"ios", "android", "web"}


class RegisterTokenRequest(BaseModel):
    token: str = Field(..., min_length=10, max_length=512)
    platform: str = Field(..., min_length=2, max_length=20)
    device_id: Optional[str] = Field(default=None, max_length=120)


class NotificationOut(BaseModel):
    id: str
    title: str
    body: str
    category: str
    deep_link: Optional[str]
    read: bool
    created_at: datetime


@router.post("/tokens", status_code=200)
async def register_token(
    body: RegisterTokenRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    platform = body.platform.lower()
    if platform not in VALID_PLATFORMS:
        raise HTTPException(status_code=400, detail=f"platform must be one of {sorted(VALID_PLATFORMS)}")

    user_id = current_user["user_id"]

    # If the same token already exists, just (re)bind it to this user and reactivate.
    res = await db.execute(select(PushToken).where(PushToken.token == body.token))
    existing = res.scalar_one_or_none()
    if existing:
        existing.user_id = user_id
        existing.platform = platform
        existing.device_id = body.device_id
        existing.is_active = True
        await db.flush()
        return {"message": "Token updated", "id": str(existing.id)}

    token = PushToken(
        user_id=user_id,
        token=body.token,
        platform=platform,
        device_id=body.device_id,
        is_active=True,
    )
    db.add(token)
    await db.flush()
    return {"message": "Token registered", "id": str(token.id)}


@router.delete("/tokens", status_code=200)
async def unregister_token(
    token: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Used at logout to disable the device's token."""
    await db.execute(
        update(PushToken)
        .where(PushToken.token == token, PushToken.user_id == current_user["user_id"])
        .values(is_active=False)
    )
    await db.flush()
    return {"message": "Token disabled"}


@router.get("", response_model=List[NotificationOut])
async def list_notifications(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    limit: int = 50,
):
    limit = max(1, min(limit, 200))
    res = await db.execute(
        select(Notification)
        .where(Notification.user_id == current_user["user_id"])
        .order_by(Notification.created_at.desc())
        .limit(limit)
    )
    rows = res.scalars().all()
    return [
        NotificationOut(
            id=str(n.id),
            title=n.title,
            body=n.body,
            category=n.category,
            deep_link=n.deep_link,
            read=n.read,
            created_at=n.created_at,
        )
        for n in rows
    ]


@router.post("/{notification_id}/read", status_code=200)
async def mark_read(
    notification_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(Notification).where(
            Notification.id == notification_id,
            Notification.user_id == current_user["user_id"],
        )
    )
    n = res.scalar_one_or_none()
    if not n:
        raise HTTPException(status_code=404, detail="Notification not found")
    n.read = True
    await db.flush()
    return {"message": "Marked read"}


@router.post("/read-all", status_code=200)
async def mark_all_read(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await db.execute(
        update(Notification)
        .where(
            Notification.user_id == current_user["user_id"],
            Notification.read == False,  # noqa: E712
        )
        .values(read=True)
    )
    await db.flush()
    return {"message": "All marked read"}


@router.delete("/{notification_id}", status_code=200)
async def delete_notification(
    notification_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        delete(Notification).where(
            Notification.id == notification_id,
            Notification.user_id == current_user["user_id"],
        )
    )
    if res.rowcount == 0:
        raise HTTPException(status_code=404, detail="Notification not found")
    await db.flush()
    return {"message": "Deleted"}
