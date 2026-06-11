from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from core.database import get_db
from core.security import get_current_user
from models.reminder import ReminderLog
from models.njangi import NjangiGroup, NjangiMember
from services.reminder_service import send_reminders

router = APIRouter(prefix="/reminders", tags=["Reminders"])


@router.post("/trigger", status_code=200)
async def trigger_reminders(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Manually trigger reminder sending (for admin testing)."""
    result = await send_reminders(db)
    await db.commit()
    return {
        "message":   "Reminders sent",
        "sent":      result["sent"],
        "failed":    result["failed"],
        "details":   result["details"],
    }


@router.get("/group/{group_id}", status_code=200)
async def get_group_reminders(
    group_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """View all reminders sent for a group (admin only)."""
    g_res = await db.execute(
        select(NjangiGroup).where(NjangiGroup.id == group_id))
    group = g_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    if str(group.creator_id) != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="Only admin can view")

    res = await db.execute(
        select(ReminderLog)
        .where(ReminderLog.group_id == group_id)
        .order_by(ReminderLog.sent_at.desc()))
    logs = res.scalars().all()

    return [
        {
            "id":        str(l.id),
            "user_id":   str(l.user_id),
            "cycle":     l.cycle,
            "channel":   l.channel,
            "message":   l.message,
            "delivered": l.delivered,
            "sent_at":   l.sent_at.strftime("%b %d, %H:%M"),
        }
        for l in logs
    ]


@router.get("/me", status_code=200)
async def get_my_reminders(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """User views their own reminder history."""
    res = await db.execute(
        select(ReminderLog)
        .where(ReminderLog.user_id == current_user["user_id"])
        .order_by(ReminderLog.sent_at.desc())
        .limit(50))
    logs = res.scalars().all()
    return [
        {
            "id":        str(l.id),
            "cycle":     l.cycle,
            "channel":   l.channel,
            "message":   l.message,
            "delivered": l.delivered,
            "sent_at":   l.sent_at.strftime("%b %d, %H:%M"),
        }
        for l in logs
    ]
