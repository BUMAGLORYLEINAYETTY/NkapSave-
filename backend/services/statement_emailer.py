"""Bulk monthly statement runner used by the APScheduler cron.

Delegates each user to `statement_delivery.generate_and_deliver`, which:
  1. Renders the PDF
  2. Persists it as a Statement row (always — in-app inbox)
  3. Tries email (if SMTP configured AND user has email)
  4. Tries WhatsApp notification (if Twilio configured AND user has phone)

Naming kept as `statement_emailer` only because the scheduler imports it
under that name; the behaviour is broader than email now.

Public:
  send_monthly_statements_for_all(db)        — cron entry point
  send_statement_for_user(db, user, year, month)  — back-compat shim
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.user import User
from services.statement_delivery import generate_and_deliver

logger = logging.getLogger("nkapsave.statement_email")


async def send_statement_for_user(
    db: AsyncSession, user: User, year: int, month: int,
) -> dict:
    """Generate + deliver one user's statement.

    Returns the channel result dict — caller can decide what to log.
    """
    stmt = await generate_and_deliver(db, user, year=year, month=month)
    return stmt.channels or {}


async def send_monthly_statements_for_all(
    db: AsyncSession,
    *,
    year: Optional[int] = None,
    month: Optional[int] = None,
) -> dict:
    """Cron entry point — defaults to the last completed calendar month."""
    if year is None or month is None:
        first_of_this = datetime.utcnow().replace(day=1)
        last_month = first_of_this - timedelta(days=1)
        year, month = last_month.year, last_month.month

    res = await db.execute(select(User).where(User.is_active == True))  # noqa: E712
    users = res.scalars().all()

    totals = {
        "users": 0, "period": f"{year}-{month:02d}",
        "email_sent": 0, "whatsapp_sent": 0,
        "email_failed": 0, "whatsapp_failed": 0,
        "in_app_only": 0, "errors": 0,
    }

    for u in users:
        totals["users"] += 1
        try:
            ch = await send_statement_for_user(db, u, year, month)
        except Exception as e:
            totals["errors"] += 1
            logger.exception("monthly statement failed user=%s: %s", u.id, e)
            continue

        if ch.get("email") == "sent":      totals["email_sent"] += 1
        if ch.get("email") == "failed":    totals["email_failed"] += 1
        if ch.get("whatsapp") == "sent":   totals["whatsapp_sent"] += 1
        if ch.get("whatsapp") == "failed": totals["whatsapp_failed"] += 1
        if ch.get("email") in (None, "skipped") and \
           ch.get("whatsapp") in (None, "skipped"):
            totals["in_app_only"] += 1

    logger.info("monthly statements batch: %s", totals)
    return totals
