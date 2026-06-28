"""Real Firebase Cloud Messaging provider.

Loads the service-account JSON pointed to by FCM_CREDENTIALS_PATH and exposes
send_to_tokens(...) for delivery. If credentials are missing, the relevant
function raises FCMNotConfigured — we never silently pretend a push went out.
"""
from __future__ import annotations

import base64
import json
import logging
import tempfile
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


_tmp_cred_file: Optional[str] = None  # holds temp file path for Railway env-var path


def _resolve_cred_path() -> str:
    """Return a filesystem path to the service-account JSON.

    Priority:
      1. FCM_CREDENTIALS_JSON (base64) — written to a temp file once.
      2. FCM_CREDENTIALS_PATH          — used directly if the file exists.
    """
    global _tmp_cred_file

    if settings.FCM_CREDENTIALS_JSON:
        if _tmp_cred_file and Path(_tmp_cred_file).exists():
            return _tmp_cred_file
        try:
            raw = base64.b64decode(settings.FCM_CREDENTIALS_JSON)
            json.loads(raw)  # validate it's real JSON before writing
        except Exception as e:
            raise FCMNotConfigured(f"FCM_CREDENTIALS_JSON is not valid base64 JSON: {e}")
        tmp = tempfile.NamedTemporaryFile(
            mode="wb", suffix=".json", delete=False, prefix="fcm_cred_"
        )
        tmp.write(raw)
        tmp.close()
        _tmp_cred_file = tmp.name
        logger.info("FCM credentials written to temp file %s", _tmp_cred_file)
        return _tmp_cred_file

    if not settings.FCM_CREDENTIALS_PATH:
        raise FCMNotConfigured(
            "Set FCM_CREDENTIALS_JSON (base64) or FCM_CREDENTIALS_PATH in env"
        )
    cred_path = Path(settings.FCM_CREDENTIALS_PATH)
    if not cred_path.exists():
        raise FCMNotConfigured(f"FCM credentials file not found: {cred_path}")
    return str(cred_path)


def _ensure_app() -> firebase_admin.App:
    global _app
    if _app is not None:
        return _app
    with _init_lock:
        if _app is not None:
            return _app
        cred_path = _resolve_cred_path()
        cred = credentials.Certificate(cred_path)
        opts = {"projectId": settings.FCM_PROJECT_ID} if settings.FCM_PROJECT_ID else None
        _app = firebase_admin.initialize_app(cred, opts, name="nkapsave-fcm")
        logger.info("Firebase Admin initialised from %s", cred_path)
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
