"""Application-level notification service.

Persists a Notification record per user, then dispatches an FCM push to all
of that user's active devices. Invalid tokens returned by FCM are deactivated
so the next send doesn't waste calls on dead devices.
"""
from __future__ import annotations

import logging
from typing import Iterable, Optional

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from models.notification import Notification, PushToken
from services.fcm_provider import (
    FCMNotConfigured,
    FCMSendError,
    send_to_tokens,
)

logger = logging.getLogger("nkapsave.notify")


async def notify_user(
    db: AsyncSession,
    user_id: str,
    title: str,
    body: str,
    category: str = "general",
    deep_link: Optional[str] = None,
    data: Optional[dict] = None,
) -> Notification:
    """Create a notification row and attempt to push to all the user's devices."""
    record = Notification(
        user_id=user_id,
        title=title[:150],
        body=body[:500],
        category=category,
        deep_link=deep_link,
    )
    db.add(record)
    await db.flush()

    res = await db.execute(
        select(PushToken).where(
            PushToken.user_id == user_id,
            PushToken.is_active == True,  # noqa: E712
        )
    )
    tokens = [t.token for t in res.scalars().all()]

    if not tokens:
        record.push_sent = False
        record.push_error = "no_active_tokens"
        return record

    try:
        result = send_to_tokens(
            tokens=tokens,
            title=title,
            body=body,
            data={
                "notification_id": str(record.id),
                "category": category,
                **(data or {}),
            },
        )
    except FCMNotConfigured as e:
        record.push_sent = False
        record.push_error = f"not_configured: {e}"
        logger.warning("FCM not configured: %s", e)
        return record
    except FCMSendError as e:
        record.push_sent = False
        record.push_error = f"send_error: {e}"[:300]
        return record

    if result["invalid_tokens"]:
        await db.execute(
            update(PushToken)
            .where(PushToken.token.in_(result["invalid_tokens"]))
            .values(is_active=False)
        )

    record.push_sent = result["success"] > 0
    if not record.push_sent:
        record.push_error = "all_devices_failed"
    return record


async def notify_users(
    db: AsyncSession,
    user_ids: Iterable[str],
    title: str,
    body: str,
    **kwargs,
) -> None:
    for uid in user_ids:
        await notify_user(db, uid, title, body, **kwargs)
