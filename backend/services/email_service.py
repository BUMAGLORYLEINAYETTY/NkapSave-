"""SMTP-backed email sending with optional attachments.

A thin wrapper around stdlib `smtplib` + `email.message.EmailMessage`. The
public `send_email` is async — it runs the blocking SMTP exchange in a thread
so it doesn't block the FastAPI event loop.

If `SMTP_HOST` is unset, every send becomes a no-op that logs a warning.
That lets the rest of the app run end-to-end without email creds; the
monthly-statement cron simply logs "skipped, no SMTP" instead of crashing.
"""
from __future__ import annotations

import asyncio
import logging
import smtplib
from dataclasses import dataclass
from email.message import EmailMessage
from typing import Iterable, Optional

from core.config import settings

logger = logging.getLogger("nkapsave.email")


class EmailNotConfigured(RuntimeError):
    """Raised when explicit code path requires email but it's not set up."""


@dataclass
class EmailAttachment:
    filename:  str
    mime_type: str       # "application/pdf"
    data:      bytes


def is_configured() -> bool:
    return bool(settings.SMTP_HOST and settings.SMTP_FROM)


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
    """Quick plaintext fallback. Not bulletproof — fine for our templates."""
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
        # Plain or implicit SSL (port 465).
        cls = smtplib.SMTP_SSL if port == 465 else smtplib.SMTP
        with cls(host, port, timeout=timeout) as s:
            if settings.SMTP_USER and settings.SMTP_PASSWORD:
                s.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            s.send_message(msg)


async def send_email(
    *, to: str, subject: str, html: str,
    text: Optional[str] = None,
    attachments: Iterable[EmailAttachment] = (),
) -> bool:
    """Send an email. Returns True on success, False if not configured.

    Raises on SMTP errors so callers can decide whether to log or retry.
    """
    if not is_configured():
        logger.warning("Email send skipped — SMTP not configured (to=%s)", to)
        return False
    msg = _build_message(to, subject, html, text, attachments)
    try:
        await asyncio.to_thread(_send_sync, msg)
    except (smtplib.SMTPException, OSError) as e:
        logger.error("SMTP send failed (to=%s): %s", to, e)
        raise
    logger.info("Email sent to %s subject=%s", to, subject)
    return True
