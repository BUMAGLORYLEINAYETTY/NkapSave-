"""Real Firebase Cloud Messaging provider.

Loads the service-account JSON pointed to by FCM_CREDENTIALS_PATH and exposes
send_to_tokens(...) for delivery. If credentials are missing, the relevant
function raises FCMNotConfigured — we never silently pretend a push went out.
"""
from __future__ import annotations

import logging
import threading
from pathlib import Path
from typing import Iterable, List, Optional

import firebase_admin
from firebase_admin import credentials, messaging

from core.config import settings

logger = logging.getLogger("nkapsave.fcm")


class FCMNotConfigured(RuntimeError):
    """Raised when Firebase credentials are missing."""


class FCMSendError(RuntimeError):
    """Raised when FCM rejects a send."""


_init_lock = threading.Lock()
_app: Optional[firebase_admin.App] = None


def _ensure_app() -> firebase_admin.App:
    global _app
    if _app is not None:
        return _app
    with _init_lock:
        if _app is not None:
            return _app
        if not settings.FCM_CREDENTIALS_PATH:
            raise FCMNotConfigured("FCM_CREDENTIALS_PATH is not set in .env")
        cred_path = Path(settings.FCM_CREDENTIALS_PATH)
        if not cred_path.exists():
            raise FCMNotConfigured(f"FCM credentials file not found: {cred_path}")
        cred = credentials.Certificate(str(cred_path))
        opts = {"projectId": settings.FCM_PROJECT_ID} if settings.FCM_PROJECT_ID else None
        _app = firebase_admin.initialize_app(cred, opts, name="nkapsave-fcm")
        logger.info("Firebase Admin initialised")
        return _app


def send_to_tokens(
    tokens: Iterable[str],
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> dict:
    """Send a push to one or more device tokens.

    Returns: {"success": int, "failure": int, "invalid_tokens": [..]}
    Caller should disable invalid tokens in DB.
    """
    token_list: List[str] = [t for t in tokens if t]
    if not token_list:
        return {"success": 0, "failure": 0, "invalid_tokens": []}

    app = _ensure_app()
    notification = messaging.Notification(title=title, body=body)
    message = messaging.MulticastMessage(
        tokens=token_list,
        notification=notification,
        data={k: str(v) for k, v in (data or {}).items()},
    )

    try:
        resp = messaging.send_each_for_multicast(message, app=app)
    except messaging.FirebaseError as e:
        logger.warning("FCM multicast failed: %s", e)
        raise FCMSendError(str(e)) from e

    invalid: List[str] = []
    for tok, r in zip(token_list, resp.responses):
        if not r.success and r.exception is not None:
            code = getattr(r.exception, "code", "")
            if code in {"registration-token-not-registered", "invalid-argument"}:
                invalid.append(tok)
    logger.info(
        "FCM multicast: success=%d failure=%d invalid=%d",
        resp.success_count, resp.failure_count, len(invalid),
    )
    return {
        "success": resp.success_count,
        "failure": resp.failure_count,
        "invalid_tokens": invalid,
    }
