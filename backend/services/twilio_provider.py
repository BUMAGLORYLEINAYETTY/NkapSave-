"""Real Twilio provider for WhatsApp + SMS delivery.

Credentials are loaded from environment via core.config.settings. If they are
missing, the relevant send function raises ProviderNotConfigured — we never
silently pretend a message was delivered.
"""
from __future__ import annotations

import logging
from functools import lru_cache
from typing import Optional

from twilio.base.exceptions import TwilioRestException
from twilio.rest import Client

from core.config import settings

logger = logging.getLogger("nkapsave.twilio")


class ProviderNotConfigured(RuntimeError):
    """Raised when Twilio credentials are missing — never silently mock."""


class ProviderSendError(RuntimeError):
    """Raised when Twilio rejects or fails to deliver a message."""


@lru_cache(maxsize=1)
def _client() -> Client:
    if not settings.TWILIO_ACCOUNT_SID or not settings.TWILIO_AUTH_TOKEN:
        raise ProviderNotConfigured(
            "TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN must be set in .env"
        )
    return Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)


def to_e164(phone: str, default_cc: Optional[str] = None) -> str:
    """Normalize a phone string to E.164 (e.g. +237690123456).

    Strips spaces, dashes, parens. If no leading '+', prepends DEFAULT_COUNTRY_CODE.
    """
    cc = default_cc or settings.DEFAULT_COUNTRY_CODE
    digits_only = "".join(c for c in (phone or "") if c.isdigit() or c == "+")
    if not digits_only:
        raise ValueError("Empty phone number")
    if digits_only.startswith("+"):
        return digits_only
    digits = digits_only.lstrip("0")
    # If it already starts with the country code, don't double it.
    if digits.startswith(cc):
        return "+" + digits
    return "+" + cc + digits


def send_whatsapp(phone: str, message: str) -> str:
    """Send a WhatsApp message via Twilio. Returns the Twilio message SID."""
    if not settings.TWILIO_WHATSAPP_FROM:
        raise ProviderNotConfigured("TWILIO_WHATSAPP_FROM is not set")
    to = to_e164(phone)
    try:
        msg = _client().messages.create(
            from_=settings.TWILIO_WHATSAPP_FROM,
            to=f"whatsapp:{to}",
            body=message,
        )
        logger.info("WhatsApp sent to %s sid=%s", to, msg.sid)
        return msg.sid
    except TwilioRestException as e:
        logger.warning("WhatsApp failed to %s: %s", to, e)
        raise ProviderSendError(str(e)) from e


def send_sms(phone: str, message: str) -> str:
    """Send an SMS via Twilio. Returns the Twilio message SID."""
    if not settings.TWILIO_FROM_NUMBER:
        raise ProviderNotConfigured("TWILIO_FROM_NUMBER is not set")
    to = to_e164(phone)
    try:
        msg = _client().messages.create(
            from_=settings.TWILIO_FROM_NUMBER,
            to=to,
            body=message,
        )
        logger.info("SMS sent to %s sid=%s", to, msg.sid)
        return msg.sid
    except TwilioRestException as e:
        logger.warning("SMS failed to %s: %s", to, e)
        raise ProviderSendError(str(e)) from e
