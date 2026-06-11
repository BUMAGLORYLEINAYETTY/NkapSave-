"""APScheduler that triggers reminders and auto-save periodically."""
import asyncio
import logging
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger
from sqlalchemy.ext.asyncio import AsyncSession
from core.database import AsyncSessionLocal
from services.reminder_service import send_reminders
from services.auto_save_service import run_due_plans, settle_pending, send_auto_save_reminders
from services.statement_emailer import send_monthly_statements_for_all
from core.config import settings

logger = logging.getLogger("reminders")
scheduler = AsyncIOScheduler()


async def reminder_job():
    """Run the reminder service."""
    logger.info("[Reminder Job] Starting...")
    async with AsyncSessionLocal() as db:
        try:
            result = await send_reminders(db)
            await db.commit()
            logger.info(
                f"[Reminder Job] Done. Sent: {result['sent']}, Failed: {result['failed']}")
            return result
        except Exception as e:
            await db.rollback()
            logger.error(f"[Reminder Job] Error: {e}")
            raise


async def monthly_statements_job():
    """Send each user the previous month's statement.

    Fires on the 1st of every month at STATEMENT_HOUR_UTC. Idempotent enough
    for one accidental double-fire (we don't track sent state per user —
    if you re-run, users get a second copy).
    """
    logger.info("[Statements Job] Starting…")
    async with AsyncSessionLocal() as db:
        try:
            result = await send_monthly_statements_for_all(db)
            await db.commit()
            logger.info("[Statements Job] %s", result)
        except Exception as e:
            await db.rollback()
            logger.error("[Statements Job] Error: %s", e)


async def auto_save_reminder_job():
    """Push a heads-up for every plan whose next deduction is within 24h."""
    logger.info("[AutoSave Reminder] Starting…")
    async with AsyncSessionLocal() as db:
        try:
            result = await send_auto_save_reminders(db)
            await db.commit()
            if result.get("sent"):
                logger.info("[AutoSave Reminder] %s", result)
        except Exception as e:
            await db.rollback()
            logger.error("[AutoSave Reminder] Error: %s", e)


async def auto_save_job():
    """Initiate due plans, then settle any pending Collection requests."""
    async with AsyncSessionLocal() as db:
        try:
            initiated = await run_due_plans(db)
            settled = await settle_pending(db)
            await db.commit()
            if initiated.get("initiated") or settled.get("settled"):
                logger.info(
                    "[AutoSave Job] initiated=%s settled=%s",
                    initiated.get("initiated", 0), settled.get("settled", 0),
                )
        except Exception as e:
            await db.rollback()
            logger.error("[AutoSave Job] Error: %s", e)


def start_scheduler():
    """Start the background scheduler."""
    # Reminders: every hour at minute 0
    scheduler.add_job(
        reminder_job,
        CronTrigger(minute=0),
        id="reminder_check",
        max_instances=1,
        coalesce=True,
    )
    # Auto-save tick: every 2 minutes. Cheap when there's nothing to do
    # (one query that hits an indexed datetime).
    scheduler.add_job(
        auto_save_job,
        IntervalTrigger(minutes=2),
        id="auto_save_tick",
        max_instances=1,
        coalesce=True,
    )
    # Monthly statement emails: 1st of each month at configurable hour (UTC).
    scheduler.add_job(
        monthly_statements_job,
        CronTrigger(day=1, hour=settings.STATEMENT_HOUR_UTC, minute=0),
        id="monthly_statements",
        max_instances=1,
        coalesce=True,
    )
    # Auto-save pre-deduction reminders: hourly. A plan that's within ~24h of
    # its next_run_at gets one push; subsequent ticks see the
    # last_reminder_for_run_at flag and skip until the plan advances.
    scheduler.add_job(
        auto_save_reminder_job,
        CronTrigger(minute=30),
        id="auto_save_reminders",
        max_instances=1,
        coalesce=True,
    )
    scheduler.start()
    logger.info("Reminder + auto-save + statements scheduler started")


def stop_scheduler():
    """Stop the scheduler gracefully."""
    if scheduler.running:
        scheduler.shutdown()
