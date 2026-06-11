"""Campay-backed mobile-money provider.

We talk to Campay (https://www.campay.net) because it aggregates MTN Mobile
Money and Orange Money behind a single Cameroon-native API:
  * Native XAF (no sandbox-EUR quirk)
  * One integration for both operators
  * The user authenticates with their PIN inside the operator's flow — we
    never see, store, or transmit the PIN.

Public surface:

  get_token()                    Lazy / cached bearer token.
  request_to_pay(...)            Initiate a collection ('Collect').
  get_status(reference)          Poll the final status of a collection.

Campay does not expose a "is this number an active wallet?" probe, so
`/momo/link` stores the number and verifies it lazily — the first auto-save
attempt will reveal an invalid number via a FAILED status.

Configuration (all read from settings):
  CAMPAY_ENV         "sandbox" | "production"
  CAMPAY_USERNAME    Campay application username (app_username)
  CAMPAY_PASSWORD    Campay application password (app_password)
"""
from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass
from typing import Optional

import httpx

from core.config import settings

logger = logging.getLogger("nkapsave.campay")


class MoMoNotConfigured(RuntimeError):
    """Raised when Campay creds are missing — never silently mock."""


class MoMoApiError(RuntimeError):
    """Raised when Campay rejects or fails to process a request."""


_BASE_URLS = {
    "sandbox":    "https://demo.campay.net/api",
    "production": "https://www.campay.net/api",
}


@dataclass
class _CachedToken:
    value: str
    expires_at: float  # unix epoch


_token_cache: Optional[_CachedToken] = None


def _base_url() -> str:
    env = (settings.CAMPAY_ENV or "sandbox").lower()
    return _BASE_URLS.get(env, _BASE_URLS["sandbox"])


def _require_creds() -> None:
    missing = [
        n for n, v in {
            "CAMPAY_USERNAME": settings.CAMPAY_USERNAME,
            "CAMPAY_PASSWORD": settings.CAMPAY_PASSWORD,
        }.items() if not v
    ]
    if missing:
        raise MoMoNotConfigured(
            f"Campay is not configured. Missing env vars: {', '.join(missing)}"
        )


def get_token(force_refresh: bool = False) -> str:
    """Return a cached bearer token, refreshing 60s before expiry.

    Campay tokens are valid for 1 hour. We refresh proactively to avoid
    a token expiring mid-batch when the scheduler runs many transactions.
    """
    global _token_cache
    _require_creds()

    now = time.time()
    if not force_refresh and _token_cache and _token_cache.expires_at - 60 > now:
        return _token_cache.value

    url = f"{_base_url()}/token/"
    try:
        resp = httpx.post(
            url,
            json={
                "username": settings.CAMPAY_USERNAME,
                "password": settings.CAMPAY_PASSWORD,
            },
            timeout=15.0,
        )
    except httpx.HTTPError as e:
        raise MoMoApiError(f"Network error fetching Campay token: {e}") from e

    if resp.status_code >= 400:
        raise MoMoApiError(
            f"Campay token request failed: {resp.status_code} {resp.text[:200]}"
        )

    data = resp.json()
    token = data.get("token")
    if not token:
        raise MoMoApiError(f"Campay token response missing 'token': {data}")
    # Campay doesn't always return an expires_in; default to 55 min.
    expires_in = int(data.get("expires_in", 3300))

    _token_cache = _CachedToken(value=token, expires_at=now + expires_in)
    logger.info("Campay token refreshed; expires in %ss", expires_in)
    return token


def _auth_headers() -> dict:
    return {
        "Authorization": f"Token {get_token()}",
        "Content-Type":  "application/json",
    }


def _msisdn(phone: str) -> str:
    """Strip non-digits (and leading '+'). Campay expects e.g. 237670000000."""
    digits = "".join(c for c in (phone or "") if c.isdigit())
    if not digits:
        raise ValueError("Empty phone number")
    return digits


def request_to_pay(
    *, phone: str, amount: int, currency: str = "XAF",
    external_id: str, payer_message: str, payee_note: str,
) -> str:
    """Initiate a Campay collection. Returns the Campay reference to poll.

    The user receives a USSD/push from MTN or Orange and approves with their PIN.
    `payee_note` isn't used by Campay's API but we accept it so callers don't
    need to know which provider they're talking to.
    """
    _require_creds()
    url = f"{_base_url()}/collect/"
    body = {
        "amount":             str(int(amount)),
        "currency":           currency,
        "from":               _msisdn(phone),
        "description":        payer_message[:160],
        "external_reference": external_id,
    }
    try:
        resp = httpx.post(url, headers=_auth_headers(), json=body, timeout=20.0)
    except httpx.HTTPError as e:
        raise MoMoApiError(f"Network error on collect: {e}") from e

    if resp.status_code >= 400:
        raise MoMoApiError(
            f"Campay collect rejected: {resp.status_code} {resp.text[:200]}"
        )

    data = resp.json()
    reference = data.get("reference")
    if not reference:
        raise MoMoApiError(f"Campay collect response missing 'reference': {data}")
    logger.info(
        "Campay collect accepted ref=%s amount=%s %s phone=%s operator=%s",
        reference, amount, currency, _msisdn(phone), data.get("operator", "?"),
    )
    return reference


def get_status(reference_id: str) -> dict:
    """Return the current state of a collection.

    Campay's transaction object includes:
      status:    SUCCESSFUL | FAILED | PENDING
      reason:    failure detail if any
      operator:  MTN | ORANGE (only set once we know)
    """
    _require_creds()
    url = f"{_base_url()}/transaction/{reference_id}/"
    try:
        resp = httpx.get(url, headers=_auth_headers(), timeout=15.0)
    except httpx.HTTPError as e:
        raise MoMoApiError(f"Network error on get_status: {e}") from e

    if resp.status_code >= 400:
        raise MoMoApiError(
            f"get_status failed: {resp.status_code} {resp.text[:200]}"
        )

    data = resp.json()
    # Normalise to the contract auto_save_service expects: uppercase status.
    if "status" in data and isinstance(data["status"], str):
        data["status"] = data["status"].upper()
    return data


def is_configured() -> bool:
    """Cheap check used by the scheduler to skip work when creds are absent."""
    return bool(settings.CAMPAY_USERNAME and settings.CAMPAY_PASSWORD)
