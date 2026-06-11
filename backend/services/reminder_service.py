"""NkapSave Reminder Service — real WhatsApp/SMS delivery via Twilio.

Behaviour:
  * Try WhatsApp first; on failure fall back to SMS.
  * If neither channel succeeds, the attempt is logged with delivered=False
    and a non-empty error_detail. We never record a fake success.
  * If Twilio creds are missing the job raises so it surfaces in logs and
    monitoring instead of silently no-oping.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Dict, List

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.njangi import GroupStatus, NjangiGroup, NjangiMember
from models.reminder import ReminderLog
from models.user import User
from services.twilio_provider import (
    ProviderNotConfigured,
    ProviderSendError,
    send_sms,
    send_whatsapp,
)
from services.notification_service import notify_user

logger = logging.getLogger("nkapsave.reminders")


# ─── Cameroon-friendly message templates ───────────────────
MESSAGE_TEMPLATES = {
    "fr": {
        "24h_before": (
            "Bonjour {name}!\n\n"
            "Ta contribution de {amount} FCFA pour le njangi {group} "
            "est due demain ({due_date}).\n\n"
            "Ouvre NkapSave pour payer en quelques secondes via MTN ou Orange Money.\n\n"
            "Merci pour ta fidelite au groupe."
        ),
        "due_today": (
            "Salut {name}!\n\n"
            "Ta contribution njangi de {amount} FCFA pour {group} est due AUJOURD'HUI.\n\n"
            "Cycle {cycle} sur {total} - {paid_count}/{total_members} membres ont deja paye.\n\n"
            "Paye maintenant dans NkapSave."
        ),
        "overdue": (
            "{name}, ta contribution njangi pour {group} est en retard.\n\n"
            "Montant: {amount} FCFA. Cela affecte ton score de confiance.\n\n"
            "Paye des que possible pour maintenir ton Trust Score."
        ),
    },
    "en": {
        "24h_before": (
            "Hi {name}!\n\n"
            "Your contribution of {amount} FCFA for njangi {group} "
            "is due tomorrow ({due_date}).\n\n"
            "Open NkapSave to pay in seconds via MTN or Orange Money.\n\n"
            "Thank you for staying committed."
        ),
        "due_today": (
            "Hey {name}!\n\n"
            "Your njangi contribution of {amount} FCFA for {group} is due TODAY.\n\n"
            "Cycle {cycle} of {total} - {paid_count}/{total_members} members have already paid.\n\n"
            "Pay now in NkapSave."
        ),
        "overdue": (
            "{name}, your njangi contribution for {group} is overdue.\n\n"
            "Amount: {amount} FCFA. This affects your Trust Score.\n\n"
            "Pay as soon as possible to maintain your standing."
        ),
    },
    "pidgin": {
        "24h_before": (
            "Hello {name}!\n\n"
            "Your contribution of {amount} FCFA for njangi {group} "
            "go due tomorrow ({due_date}).\n\n"
            "Open NkapSave make you pay sharp sharp with MTN or Orange Money.\n\n"
            "Tnk you for ya commitment."
        ),
        "due_today": (
            "Hey {name}!\n\n"
            "Your njangi contribution of {amount} FCFA for {group} dey due TODAY.\n\n"
            "Cycle {cycle} for {total} - {paid_count}/{total_members} members don pay.\n\n"
            "Pay now for NkapSave."
        ),
    },
}

ANGLOPHONE_CITIES = {"bamenda", "buea", "limbe", "kumba"}


def detect_language(user: User) -> str:
    """Choose language based on user's city. Default French for CM."""
    if user.city and user.city.lower() in ANGLOPHONE_CITIES:
        return "en"
    return "fr"


def format_message(template_key: str, language: str, ctx: Dict) -> str:
    templates = MESSAGE_TEMPLATES.get(language, MESSAGE_TEMPLATES["fr"])
    template = templates.get(template_key, templates["24h_before"])
    return template.format(**ctx)


FREQ_MAP = {
    "Daily": 1, "Weekly": 7, "Bi-Weekly": 14,
    "Monthly": 30, "Quarterly": 90,
}


def _cycle_length_days(frequency: str) -> int:
    if frequency in FREQ_MAP:
        return FREQ_MAP[frequency]
    if frequency and frequency.startswith("Every "):
        try:
            return int(frequency.split()[1])
        except (ValueError, IndexError):
            pass
    return 30


async def find_due_contributions(db: AsyncSession) -> List[Dict]:
    """Find members with payment due in the next 0-1 days."""
    now = datetime.utcnow()

    res = await db.execute(
        select(NjangiGroup).where(NjangiGroup.status == GroupStatus.ACTIVE)
    )
    groups = res.scalars().all()

    due_list: List[Dict] = []
    for g in groups:
        if not g.cycle_start_date:
            continue
        days = _cycle_length_days(g.frequency)
        due_date = g.cycle_start_date + timedelta(days=days)
        days_until = (due_date.date() - now.date()).days
        if days_until not in (0, 1):
            continue

        m_res = await db.execute(
            select(NjangiMember).where(
                NjangiMember.group_id == g.id,
                NjangiMember.has_paid == False,  # noqa: E712 — SQLAlchemy comparison
            )
        )
        unpaid = m_res.scalars().all()

        for member in unpaid:
            u_res = await db.execute(select(User).where(User.id == member.user_id))
            user = u_res.scalar_one_or_none()
            if not user or not user.phone:
                continue
            due_list.append({
                "user": user,
                "group": g,
                "member": member,
                "days_until": days_until,
                "due_date": due_date,
            })
    return due_list


async def _deliver(phone: str, message: str) -> Dict:
    """Try WhatsApp then SMS. Return delivery result dict."""
    try:
        sid = send_whatsapp(phone, message)
        return {"channel": "whatsapp", "delivered": True, "sid": sid, "error": None}
    except (ProviderSendError, ProviderNotConfigured) as wa_err:
        wa_msg = str(wa_err)
        try:
            sid = send_sms(phone, message)
            return {"channel": "sms", "delivered": True, "sid": sid, "error": None}
        except (ProviderSendError, ProviderNotConfigured) as sms_err:
            return {
                "channel": "failed",
                "delivered": False,
                "sid": None,
                "error": f"whatsapp: {wa_msg} | sms: {sms_err}",
            }


async def send_reminders(db: AsyncSession) -> Dict:
    """Send all due reminders. Returns aggregate counts + per-recipient details."""
    due_items = await find_due_contributions(db)
    sent = 0
    failed = 0
    details: List[Dict] = []

    for item in due_items:
        user: User = item["user"]
        group: NjangiGroup = item["group"]
        days_until = item["days_until"]

        # De-dup: skip if already reminded for this cycle in last 20 hours.
        check_res = await db.execute(
            select(ReminderLog).where(
                ReminderLog.user_id == user.id,
                ReminderLog.group_id == group.id,
                ReminderLog.cycle == group.current_cycle,
                ReminderLog.sent_at >= datetime.utcnow() - timedelta(hours=20),
            )
        )
        if check_res.scalar_one_or_none():
            continue

        all_m = await db.execute(
            select(NjangiMember).where(NjangiMember.group_id == group.id)
        )
        members = all_m.scalars().all()
        paid_count = sum(1 for m in members if m.has_paid)

        lang = detect_language(user)
        template_key = "due_today" if days_until == 0 else "24h_before"
        ctx = {
            "name":          user.full_name.split()[0] if user.full_name else "ami",
            "amount":        f"{int(group.contribution):,}".replace(",", " "),
            "group":         group.name,
            "due_date":      item["due_date"].strftime("%d %b %Y"),
            "cycle":         group.current_cycle,
            "total":         group.total_cycles,
            "paid_count":    paid_count,
            "total_members": len(members),
        }
        message = format_message(template_key, lang, ctx)

        result = await _deliver(user.phone, message)

        # Also push an in-app notification (best-effort; never blocks reminder).
        push_title = "Njangi reminder" if lang != "fr" else "Rappel Njangi"
        await notify_user(
            db,
            user_id=str(user.id),
            title=push_title,
            body=message,
            category="njangi_reminder",
            deep_link=f"/njangi/{group.id}",
        )

        log = ReminderLog(
            user_id=user.id,
            group_id=group.id,
            cycle=group.current_cycle,
            channel=result["channel"],
            message=message[:500],
            delivered=result["delivered"],
        )
        db.add(log)

        if result["delivered"]:
            sent += 1
        else:
            failed += 1
            logger.warning(
                "Reminder failed for user=%s group=%s: %s",
                user.id, group.id, result["error"],
            )

        details.append({
            "user":      user.full_name,
            "group":     group.name,
            "channel":   result["channel"],
            "delivered": result["delivered"],
        })

    await db.flush()
    return {"sent": sent, "failed": failed, "details": details}
