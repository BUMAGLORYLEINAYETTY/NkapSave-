"""Email sending — Resend (HTTP API) with SMTP fallback.

Provider selection (checked in order):
  1. RESEND_API_KEY set → use Resend (recommended; not blocked by Railway).
  2. SMTP_HOST set      → use stdlib smtplib (may be blocked on Railway port 587).
  3. Neither set        → no-op with a warning log.

If SMTP_HOST is unset and RESEND_API_KEY is unset, every send becomes a no-op
so the rest of the app runs without email creds.
"""
from __future__ import annotations

import asyncio
import logging
import smtplib
from dataclasses import dataclass
from email.message import EmailMessage
from typing import Iterable, Optional

import httpx

from core.config import settings

logger = logging.getLogger("nkapsave.email")


class EmailNotConfigured(RuntimeError):
    """Raised when explicit code path requires email but it's not set up."""


@dataclass
class EmailAttachment:
    filename:  str
    mime_type: str
    data:      bytes


def is_configured() -> bool:
    return bool(
        (settings.RESEND_API_KEY) or
        (settings.SMTP_HOST and settings.SMTP_FROM)
    )


# ── Resend (HTTP API) ─────────────────────────────────────────────────────────

async def _send_via_resend(
    *, to: str, subject: str, html: str,
    attachments: Iterable[EmailAttachment] = (),
) -> None:
    resend_from = settings.RESEND_FROM or "NkapSave <onboarding@resend.dev>"
    payload: dict = {
        "from": resend_from,
        "to":   [to],
        "subject": subject,
        "html": html,
    }
    if list(attachments):
        import base64
        payload["attachments"] = [
            {
                "filename": a.filename,
                "content":  base64.b64encode(a.data).decode(),
            }
            for a in attachments
        ]
    async with httpx.AsyncClient(timeout=20) as client:
        resp = await client.post(
            "https://api.resend.com/emails",
            headers={
                "Authorization": f"Bearer {settings.RESEND_API_KEY}",
                "Content-Type":  "application/json",
            },
            json=payload,
        )
    if resp.status_code not in (200, 201):
        raise RuntimeError(f"Resend API error {resp.status_code}: {resp.text}")


# ── SMTP (stdlib fallback) ────────────────────────────────────────────────────

def _build_message(
    to: str, subject: str, html: str, text: Optional[str],
    attachments: Iterable[EmailAttachment],
) -> EmailMessage:
    msg = EmailMessage()
    msg["From"]    = settings.SMTP_FROM
    msg["To"]      = to
    msg["Subject"] = subject
    msg.set_content(text or _strip_tags(html))
    msg.add_alternative(html, subtype="html")
    for a in attachments:
        maintype, _, subtype = a.mime_type.partition("/")
        msg.add_attachment(
            a.data, maintype=maintype, subtype=subtype or "octet-stream",
            filename=a.filename,
        )
    return msg


def _strip_tags(html: str) -> str:
    import re
    text = re.sub(r"<[^>]+>", "", html)
    return re.sub(r"\n\s*\n+", "\n\n", text).strip()


def _send_sync(msg: EmailMessage) -> None:
    host = settings.SMTP_HOST
    port = settings.SMTP_PORT
    timeout = 20
    if settings.SMTP_STARTTLS:
        with smtplib.SMTP(host, port, timeout=timeout) as s:
            s.ehlo()
            s.starttls()
            s.ehlo()
            if settings.SMTP_USER and settings.SMTP_PASSWORD:
                s.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            s.send_message(msg)
    else:
        cls = smtplib.SMTP_SSL if port == 465 else smtplib.SMTP
        with cls(host, port, timeout=timeout) as s:
            if settings.SMTP_USER and settings.SMTP_PASSWORD:
                s.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            s.send_message(msg)


# ── Public API ────────────────────────────────────────────────────────────────

async def send_email(
    *, to: str, subject: str, html: str,
    text: Optional[str] = None,
    attachments: Iterable[EmailAttachment] = (),
) -> bool:
    """Send an email. Returns True on success, False if not configured."""
    if settings.RESEND_API_KEY:
        try:
            await _send_via_resend(to=to, subject=subject, html=html, attachments=attachments)
            logger.info("Email sent via Resend to=%s subject=%s", to, subject)
            return True
        except Exception as e:
            logger.error("Resend send failed (to=%s): %s", to, e)
            raise

    if settings.SMTP_HOST and settings.SMTP_FROM:
        msg = _build_message(to, subject, html, text, attachments)
        try:
            await asyncio.to_thread(_send_sync, msg)
            logger.info("Email sent via SMTP to=%s subject=%s", to, subject)
            return True
        except (smtplib.SMTPException, OSError) as e:
            logger.error("SMTP send failed (to=%s): %s", to, e)
            raise

    logger.warning("Email send skipped — no provider configured (to=%s)", to)
    return False
