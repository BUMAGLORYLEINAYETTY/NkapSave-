"""Generate, persist, and deliver monthly statements.

The flow for one user, one period:

  1. Build the StatementData (transactions + summaries) — `build_statement_data`
  2. Render the PDF                                      — `render_pdf`
  3. UPSERT a `Statement` row holding the bytes           — always succeeds
  4. Try every delivery channel the user is reachable on:
       - email     (if SMTP configured AND user.email set)
       - whatsapp  (if Twilio configured AND user.phone set)  ← notification only
       - in_app    (always; the Statement row IS the in-app delivery)
     Each channel result is recorded in `Statement.channels` so we can show
     status in the UI ("📧 sent to you@example.com, 💬 sent to 237…").

The WhatsApp message is just a notification — we don't attach the PDF over
WhatsApp (Twilio media requires a public URL we'd need to host). Instead the
message points the user back to the in-app statements inbox.
"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Optional
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.config import settings
from models.statement import Statement
from models.user import User
from services import email_service
from services.email_service import EmailAttachment
from services.statement_service import (
    build_statement_data, render_pdf, _month_window,
)
from services.notification_service import notify_user

logger = logging.getLogger("nkapsave.statements")


def _make_filename(label: str) -> str:
    return f"NkapSave_{label.replace(' ', '_')}.pdf"


async def _maybe_send_email(
    user: User, label: str, pdf: bytes, summary_text: str,
) -> str:
    """Returns one of: 'sent' | 'failed' | 'skipped'."""
    if not email_service.is_configured() or not user.email:
        return "skipped"
    try:
        sent = await email_service.send_email(
            to=user.email,
            subject=f"Your NkapSave statement — {label}",
            html=_html_body(user.full_name or "there", label, summary_text),
            text=_text_body(user.full_name or "there", label, summary_text),
            attachments=[EmailAttachment(
                filename=_make_filename(label),
                mime_type="application/pdf",
                data=pdf,
            )],
        )
        return "sent" if sent else "skipped"
    except Exception as e:
        logger.warning("statement email failed user=%s: %s", user.id, e)
        return "failed"


async def _maybe_send_whatsapp(user: User, label: str) -> str:
    """Returns one of: 'sent' | 'failed' | 'skipped'.

    We never attach the PDF over WhatsApp — just notify. The user opens the
    app and downloads from the inbox.
    """
    if not user.phone:
        return "skipped"
    # Lazy import so missing twilio creds don't crash startup.
    try:
        from services.twilio_provider import (
            send_whatsapp, ProviderNotConfigured, ProviderSendError,
        )
    except ImportError:
        return "skipped"

    first_name = (user.full_name or "").split()[0] or "ami"
    msg = (
        f"Hi {first_name} 👋\n\n"
        f"Your NkapSave statement for {label} is ready.\n"
        f"Open the NkapSave app → Transactions → Statements to view or download it.\n\n"
        f"Stay savvy! 💰"
    )
    try:
        send_whatsapp(user.phone, msg)
        return "sent"
    except ProviderNotConfigured:
        return "skipped"
    except ProviderSendError as e:
        logger.warning("statement WhatsApp failed user=%s: %s", user.id, e)
        return "failed"
    except Exception as e:  # defensive — Twilio sometimes raises generic errors
        logger.warning("statement WhatsApp errored user=%s: %s", user.id, e)
        return "failed"


def _summary_line(data) -> str:
    inc, exp = data.total_income, data.total_expense
    net = data.net
    sign = "+" if net >= 0 else "−"
    return (
        f"Income: {inc:,.0f} XAF · "
        f"Expense: {exp:,.0f} XAF · "
        f"Net: {sign}{abs(net):,.0f} XAF"
    )


def _html_body(name: str, label: str, summary: str) -> str:
    return f"""\
<!doctype html>
<html><body style="font-family: -apple-system, Helvetica, Arial, sans-serif;
                   background: #f5f7fa; padding: 24px; color: #1a1a1a;">
  <div style="max-width: 560px; margin: 0 auto; background: #ffffff;
              border-radius: 14px; padding: 28px; border: 1px solid #e6e8ec;">
    <h1 style="margin:0 0 4px 0; font-size: 22px; color: #0E2A2A;">
      NkapSave statement
    </h1>
    <p style="margin: 0 0 18px 0; color: #6b7280; font-size: 13px;">
      For {label}
    </p>
    <p>Hi <b>{name}</b>,</p>
    <p>Your monthly statement is attached as a PDF.</p>
    <div style="background:#f0fdf4; border:1px solid #bbf7d0;
                border-radius:10px; padding:14px 16px; margin: 18px 0;
                font-size: 13.5px; color: #064e3b;">
      <b>{summary}</b>
    </div>
    <p style="font-size: 13px; color:#555;">
      You can also find every past statement inside the app under
      <b>Transactions → Statements</b>.
    </p>
    <p style="font-size: 11px; color:#9ca3af; margin-top: 28px;">
      — The NkapSave team
    </p>
  </div>
</body></html>"""


def _text_body(name: str, label: str, summary: str) -> str:
    return (
        f"Hi {name},\n\n"
        f"Your NkapSave statement for {label} is attached.\n\n"
        f"{summary}\n\n"
        f"You can also view every past statement in the app under "
        f"Transactions → Statements.\n\n"
        f"— The NkapSave team"
    )


async def generate_and_deliver(
    db: AsyncSession, user: User, *, year: int, month: int,
) -> Statement:
    """Produce a Statement row for (user, year, month) and dispatch notifications.

    Idempotent: if a row already exists for this period, the PDF + channels
    are refreshed (re-generated with current data, re-sent).
    """
    start, end, label = _month_window(year, month)
    data = await build_statement_data(
        db, user, start=start, end=end, period_label=label,
    )
    pdf = render_pdf(data)
    summary = _summary_line(data)

    # UPSERT
    existing = await db.execute(
        select(Statement).where(
            Statement.user_id == user.id,
            Statement.period_year == year,
            Statement.period_month == month,
        )
    )
    row: Optional[Statement] = existing.scalar_one_or_none()
    if row is None:
        row = Statement(
            user_id=user.id,
            period_year=year, period_month=month,
            period_label=label,
            pdf_bytes=pdf, size_bytes=len(pdf),
            channels={},
        )
        db.add(row)
    else:
        row.period_label = label
        row.pdf_bytes = pdf
        row.size_bytes = len(pdf)
    await db.flush()

    channels: dict[str, str] = {"in_app": "sent"}
    channels["email"]    = await _maybe_send_email(user, label, pdf, summary)
    channels["whatsapp"] = await _maybe_send_whatsapp(user, label)
    row.channels = channels

    # In-app push so the user sees the inbox light up immediately.
    await notify_user(
        db, user_id=str(user.id),
        title=f"📄 Statement ready — {label}",
        body=f"Your statement is in the inbox. {summary}",
        category="statement",
        deep_link="/expenses",
    )

    await db.flush()
    logger.info(
        "statement delivered user=%s period=%s channels=%s",
        user.id, label, channels,
    )
    return row
