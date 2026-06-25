"""Fapshi-backed mobile-money provider.

Fapshi (https://fapshi.com) aggregates MTN Mobile Money and Orange Money for
Cameroon behind a simple REST API:
  * Native XAF
  * One integration for both operators
  * Users approve USSD prompts from their operator — we never see the PIN.

Public surface (same contract as the previous Campay implementation):

  request_to_pay(...)   Initiate a collection. Returns a transId to poll.
  get_status(transId)   Poll the status of a collection.
  transfer(...)         Outbound payout to a subscriber.
  is_configured()       Returns True when credentials are present.

Configuration (all read from settings):
  FAPSHI_ENV               "sandbox" | "production"
  FAPSHI_COLLECTION_USER   apiuser for pay-in (users pay NkapSave)
  FAPSHI_COLLECTION_KEY    apikey  for pay-in
  FAPSHI_PAYOUT_USER       apiuser for pay-out (NkapSave pays users)
  FAPSHI_PAYOUT_KEY        apikey  for pay-out
"""
from __future__ import annotations

import logging
import uuid
from typing import Optional

import httpx

from core.config import settings

logger = logging.getLogger("nkapsave.fapshi")


class MoMoNotConfigured(RuntimeError):
    """Raised when Fapshi credentials are missing."""


class MoMoApiError(RuntimeError):
    """Raised when Fapshi rejects or fails to process a request."""


_BASE_URLS = {
    "sandbox":    "https://sandbox.fapshi.com",
    "production": "https://live.fapshi.com",
}


def _base_url() -> str:
    env = (settings.FAPSHI_ENV or "sandbox").lower()
    return _BASE_URLS.get(env, _BASE_URLS["sandbox"])


def _require_collection_creds() -> None:
    missing = [n for n, v in {
        "FAPSHI_COLLECTION_USER": settings.FAPSHI_COLLECTION_USER,
        "FAPSHI_COLLECTION_KEY":  settings.FAPSHI_COLLECTION_KEY,
    }.items() if not v]
    if missing:
        raise MoMoNotConfigured(
            f"Fapshi collection not configured. Missing: {', '.join(missing)}"
        )


def _require_payout_creds() -> None:
    missing = [n for n, v in {
        "FAPSHI_PAYOUT_USER": settings.FAPSHI_PAYOUT_USER,
        "FAPSHI_PAYOUT_KEY":  settings.FAPSHI_PAYOUT_KEY,
    }.items() if not v]
    if missing:
        raise MoMoNotConfigured(
            f"Fapshi payouts not configured. Missing: {', '.join(missing)}"
        )


def _collection_headers() -> dict:
    return {
        "apiuser":      settings.FAPSHI_COLLECTION_USER or "",
        "apikey":       settings.FAPSHI_COLLECTION_KEY or "",
        "Content-Type": "application/json",
    }


def _payout_headers() -> dict:
    return {
        "apiuser":      settings.FAPSHI_PAYOUT_USER or "",
        "apikey":       settings.FAPSHI_PAYOUT_KEY or "",
        "Content-Type": "application/json",
    }


def _msisdn(phone: str) -> str:
    """Normalise to the full MSISDN (237XXXXXXXXX) for payout / status endpoints."""
    digits = "".join(c for c in (phone or "") if c.isdigit())
    if not digits:
        raise ValueError("Empty phone number")
    cc = settings.DEFAULT_COUNTRY_CODE  # "237"
    if digits.startswith(cc):
        return digits
    if digits.startswith("0"):
        digits = digits[1:]
    return cc + digits


def _local_phone(phone: str) -> str:
    """Strip country code for direct-pay, which expects local format (67XXXXXXX)."""
    full = _msisdn(phone)
    cc = settings.DEFAULT_COUNTRY_CODE
    return full[len(cc):] if full.startswith(cc) else full


# Fapshi does not need a token endpoint — auth is per-request API key headers.
# This stub is kept so callers that import get_token() don't break.
def get_token(force_refresh: bool = False) -> str:  # noqa: ARG001
    _require_collection_creds()
    return settings.FAPSHI_COLLECTION_KEY or ""


def request_to_pay(
    *, phone: str, amount: int, currency: str = "XAF",
    external_id: str, payer_message: str, payee_note: str,
) -> str:
    """Initiate a Fapshi collection. Returns the transId to poll.

    The user receives a USSD/push from MTN or Orange and approves with their PIN.
    `currency` is accepted for interface compatibility — Fapshi always uses XAF.
    `payee_note` is not sent to Fapshi but accepted so callers don't need to
    know which provider they're talking to.
    """
    _require_collection_creds()
    # /direct-pay sends a USSD push to the user's phone (unlike /initiate-pay
    # which only creates a checkout link with no USSD prompt).
    url = f"{_base_url()}/direct-pay"
    body = {
        "amount":     int(amount),
        "phone":      _local_phone(phone),   # direct-pay expects 67XXXXXXX (no CC)
        "externalId": external_id,
        "message":    payer_message[:160],
    }
    try:
        resp = httpx.post(url, headers=_collection_headers(), json=body, timeout=20.0)
    except httpx.HTTPError as e:
        raise MoMoApiError(f"Network error on direct-pay: {e}") from e

    if resp.status_code >= 400:
        raise MoMoApiError(
            f"Fapshi direct-pay rejected: {resp.status_code} {resp.text[:200]}"
        )

    data = resp.json()
    # direct-pay returns transId at root (no "data" wrapper).
    trans_id = data.get("transId") or (data.get("data") or {}).get("transId")
    if not trans_id:
        raise MoMoApiError(f"Fapshi direct-pay response missing transId: {data}")
    logger.info(
        "Fapshi direct-pay accepted transId=%s amount=%s phone=%s",
        trans_id, amount, _local_phone(phone),
    )
    return trans_id


def transfer(
    *, phone: str, amount: int, external_id: str, description: str,
) -> str:
    """Initiate a Fapshi outbound payout to a subscriber.

    Sends `amount` XAF from the merchant wallet to `phone`. Returns the
    transId. Raises MoMoApiError on rejection.
    `external_id` is accepted for interface compatibility — Fapshi payouts
    don't have a client-supplied external ID but we log it for traceability.
    """
    _require_payout_creds()
    url = f"{_base_url()}/payout"
    body = {
        "amount":  int(amount),
        "phone":   _msisdn(phone),
        "message": description[:160],
    }
    try:
        resp = httpx.post(url, headers=_payout_headers(), json=body, timeout=30.0)
    except httpx.HTTPError as e:
        raise MoMoApiError(f"Network error on payout: {e}") from e

    if resp.status_code >= 400:
        content_type = resp.headers.get("content-type", "")
        if "html" in content_type or resp.text.lstrip().startswith("<"):
            raise MoMoApiError(
                f"Fapshi payout endpoint unavailable (HTTP {resp.status_code}). "
                "Outbound payouts may not be enabled on this account yet."
            )
        raise MoMoApiError(
            f"Fapshi payout rejected ({resp.status_code}): {resp.text[:200]}"
        )

    data = resp.json()
    # Production returns transId at root; sandbox wraps it under "data".
    trans_id = data.get("transId") or (data.get("data") or {}).get("transId")
    if not trans_id:
        raise MoMoApiError(f"Fapshi payout response missing transId: {data}")
    logger.info(
        "Fapshi payout accepted transId=%s amount=%s phone=%s (external_id=%s)",
        trans_id, amount, _msisdn(phone), external_id,
    )
    return trans_id


def get_status(reference_id: str) -> dict:
    """Return the current state of a collection.

    Returns a dict with at least:
      status:  SUCCESSFUL | FAILED | PENDING
      reason:  failure detail if any (EXPIRED maps to FAILED + reason=EXPIRED)

    Fapshi also returns EXPIRED for prompts the user ignored; we normalise
    that to FAILED so the settlement loop handles it uniformly.
    """
    _require_collection_creds()
    url = f"{_base_url()}/payment-status/{reference_id}"
    try:
        resp = httpx.get(url, headers=_collection_headers(), timeout=15.0)
    except httpx.HTTPError as e:
        raise MoMoApiError(f"Network error on payment-status: {e}") from e

    if resp.status_code >= 400:
        raise MoMoApiError(
            f"payment-status failed: {resp.status_code} {resp.text[:200]}"
        )

    data = resp.json()
    # Production returns fields at root; sandbox wraps them under "data".
    tx = data.get("data") or data
    status = (tx.get("status") or "PENDING").upper()

    # EXPIRED = user ignored the USSD prompt; treat as FAILED so the
    # settlement loop picks it up and fires the "not_approved" notification.
    if status == "EXPIRED":
        return {"status": "FAILED", "reason": "EXPIRED"}

    return {
        "status": status,
        "reason": tx.get("reason") or tx.get("message"),
    }


def initiate_pay(
    *, amount: int, email: str, external_id: str,
    redirect_url: str = "", message: str = "",
) -> tuple[str, str]:
    """Create a Fapshi payment link (no USSD push — user clicks to pay).

    Returns (link, transId). Use this as a fallback when direct-pay is not
    activated on the account, or for web/email payment flows.
    """
    _require_collection_creds()
    url = f"{_base_url()}/initiate-pay"
    body = {
        "amount":      int(amount),
        "email":       email,
        "externalId":  external_id,
        "message":     message[:160],
        "redirectUrl": redirect_url,
    }
    try:
        resp = httpx.post(url, headers=_collection_headers(), json=body, timeout=20.0)
    except httpx.HTTPError as e:
        raise MoMoApiError(f"Network error on initiate-pay: {e}") from e

    if resp.status_code >= 400:
        raise MoMoApiError(
            f"Fapshi initiate-pay rejected: {resp.status_code} {resp.text[:200]}"
        )

    data = resp.json()
    link = data.get("link") or ""
    trans_id = data.get("transId") or ""
    if not trans_id:
        raise MoMoApiError(f"Fapshi initiate-pay response missing transId: {data}")
    logger.info("Fapshi initiate-pay transId=%s link=%s", trans_id, link)
    return link, trans_id


def get_balance() -> dict:
    """Return the merchant wallet balance.

    Returns a dict with 'service', 'balance' (int XAF), and 'currency'.
    Useful for checking whether payouts are funded before initiating them.
    """
    _require_collection_creds()
    url = f"{_base_url()}/balance"
    try:
        resp = httpx.get(url, headers=_collection_headers(), timeout=15.0)
    except httpx.HTTPError as e:
        raise MoMoApiError(f"Network error on balance: {e}") from e

    if resp.status_code >= 400:
        raise MoMoApiError(
            f"Fapshi balance check failed: {resp.status_code} {resp.text[:200]}"
        )

    return resp.json()


def expire_transaction(trans_id: str) -> None:
    """Cancel/expire a pending payment transaction."""
    _require_collection_creds()
    url = f"{_base_url()}/expire-pay"
    try:
        resp = httpx.post(
            url, headers=_collection_headers(), json={"transId": trans_id}, timeout=15.0
        )
    except httpx.HTTPError as e:
        raise MoMoApiError(f"Network error on expire-pay: {e}") from e

    if resp.status_code >= 400:
        raise MoMoApiError(
            f"Fapshi expire-pay failed: {resp.status_code} {resp.text[:200]}"
        )
    logger.info("Fapshi expired transId=%s", trans_id)


def get_transactions_by_user(user_id: str) -> list:
    """Fetch all transactions for a given userId from Fapshi."""
    _require_collection_creds()
    url = f"{_base_url()}/transaction/{user_id}"
    try:
        resp = httpx.get(url, headers=_collection_headers(), timeout=15.0)
    except httpx.HTTPError as e:
        raise MoMoApiError(f"Network error on transaction lookup: {e}") from e

    if resp.status_code >= 400:
        raise MoMoApiError(
            f"Fapshi transaction lookup failed: {resp.status_code} {resp.text[:200]}"
        )

    return resp.json()


def is_configured() -> bool:
    """Cheap check used by the scheduler to skip work when creds are absent."""
    return bool(settings.FAPSHI_COLLECTION_USER and settings.FAPSHI_COLLECTION_KEY)
