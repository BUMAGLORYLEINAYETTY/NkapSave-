"""Group chat for njangi groups.

Two surfaces:
  * `GET  /njangi/groups/{group_id}/messages` — paginated history
  * `WS   /njangi/groups/{group_id}/chat?token=<jwt>` — real-time
    bidirectional channel. Membership is checked on connect and on every
    inbound message (the latter so a mid-session removal stops broadcasts).

A single in-process `ConnectionManager` keeps the active sockets per
group. This is deliberately simple — one Uvicorn worker fans out
in-memory; if you scale horizontally you'd swap this for a Redis pub/sub
broker.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Dict, Set, Optional

from fastapi import (
    APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect,
    status,
)
from jose import JWTError, jwt
from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession

from core.config import settings
from core.database import AsyncSessionLocal, get_db
from core.security import get_current_user
from models.njangi import NjangiGroup, NjangiMember, NjangiMessage
from models.njangi_schemas import (
    MessageOut, MessagesResponse, SendMessageRequest,
)
from models.user import User

logger = logging.getLogger("nkapsave.njangi_chat")

router = APIRouter(prefix="/njangi", tags=["Njangi Chat"])


# ─── Connection manager ──────────────────────────────────────
class ConnectionManager:
    """Per-group set of live WebSocket connections."""

    def __init__(self) -> None:
        self._groups: Dict[str, Set[WebSocket]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, group_id: str, ws: WebSocket) -> None:
        async with self._lock:
            self._groups.setdefault(group_id, set()).add(ws)

    async def disconnect(self, group_id: str, ws: WebSocket) -> None:
        async with self._lock:
            sockets = self._groups.get(group_id)
            if not sockets:
                return
            sockets.discard(ws)
            if not sockets:
                self._groups.pop(group_id, None)

    async def broadcast(self, group_id: str, payload: dict) -> None:
        """Send `payload` (JSON-encoded) to every socket in the group.
        Drops sockets that error out mid-send so one dead client can't
        block the rest."""
        async with self._lock:
            sockets = list(self._groups.get(group_id, ()))
        dead: list[WebSocket] = []
        for ws in sockets:
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)
        if dead:
            async with self._lock:
                live = self._groups.get(group_id)
                if live is not None:
                    for ws in dead:
                        live.discard(ws)


manager = ConnectionManager()


# ─── Helpers ──────────────────────────────────────────────────
async def _is_member(db: AsyncSession, group_id: str, user_id: str) -> bool:
    res = await db.execute(
        select(NjangiMember).where(
            NjangiMember.group_id == group_id,
            NjangiMember.user_id == user_id,
        )
    )
    return res.scalar_one_or_none() is not None


async def _row_to_out(
    db: AsyncSession, msg: NjangiMessage, current_user_id: str,
    user_cache: Optional[Dict[str, User]] = None,
) -> MessageOut:
    """Build a `MessageOut` for an API/WS response. `user_cache` avoids
    re-fetching the same sender across a page of history."""
    sender = None
    if user_cache is not None:
        sender = user_cache.get(str(msg.sender_id))
    if sender is None:
        u_res = await db.execute(select(User).where(User.id == msg.sender_id))
        sender = u_res.scalar_one_or_none()
        if user_cache is not None and sender is not None:
            user_cache[str(msg.sender_id)] = sender
    return MessageOut(
        id=str(msg.id),
        group_id=str(msg.group_id),
        sender_id=str(msg.sender_id),
        sender_name=sender.full_name if sender else "Unknown",
        sender_picture=sender.profile_picture if sender else None,
        content=msg.content,
        created_at=msg.created_at.isoformat() if msg.created_at else "",
        is_me=str(msg.sender_id) == current_user_id,
    )


def _decode_ws_token(token: str) -> Optional[str]:
    """Validate a JWT supplied as a WS query param. Returns the user_id
    on success, or None on any failure. We don't raise here because the
    WebSocket handshake closes have their own machinery."""
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        if payload.get("type") != "access":
            return None
        return payload.get("sub")
    except JWTError:
        return None


# ─── REST: message history ───────────────────────────────────
@router.get(
    "/groups/{group_id}/messages",
    response_model=MessagesResponse,
)
async def get_messages(
    group_id: str,
    before: Optional[str] = Query(None, description="ISO timestamp; return messages strictly older than this"),
    limit: int = Query(50, ge=1, le=200),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user["user_id"]
    if not await _is_member(db, group_id, user_id):
        raise HTTPException(status_code=403, detail="Not a group member")

    stmt = select(NjangiMessage).where(NjangiMessage.group_id == group_id)
    if before:
        from datetime import datetime
        try:
            cutoff = datetime.fromisoformat(before.replace("Z", "+00:00"))
            stmt = stmt.where(NjangiMessage.created_at < cutoff)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid 'before' timestamp")
    stmt = stmt.order_by(desc(NjangiMessage.created_at)).limit(limit)

    res = await db.execute(stmt)
    rows = list(res.scalars().all())
    rows.reverse()  # oldest → newest for client convenience

    cache: Dict[str, User] = {}
    out = [await _row_to_out(db, m, user_id, cache) for m in rows]
    return MessagesResponse(messages=out)


# ─── REST: send (fallback when WS isn't connected) ───────────
@router.post(
    "/groups/{group_id}/messages",
    response_model=MessageOut,
    status_code=201,
)
async def send_message(
    group_id: str,
    body: SendMessageRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user["user_id"]
    if not await _is_member(db, group_id, user_id):
        raise HTTPException(status_code=403, detail="Not a group member")

    content = body.content.strip()
    if not content:
        raise HTTPException(status_code=400, detail="Empty message")

    msg = NjangiMessage(
        group_id=group_id, sender_id=user_id, content=content,
    )
    db.add(msg)
    await db.flush()
    await db.refresh(msg)

    out = await _row_to_out(db, msg, user_id)
    # Live broadcast — recipients listening on the WS get it instantly;
    # the sender's `is_me` flag is per-recipient so we re-serialise.
    await _broadcast_to_group(group_id, msg)
    return out


async def _broadcast_to_group(group_id: str, msg: NjangiMessage) -> None:
    """Fan a freshly-persisted message out to all WS listeners. We open
    a short-lived DB session to look up the sender's display fields so
    every recipient gets a fully-hydrated payload (with `is_me` set
    relative to themselves)."""
    async with AsyncSessionLocal() as db:
        u_res = await db.execute(select(User).where(User.id == msg.sender_id))
        sender = u_res.scalar_one_or_none()
    base = {
        "id": str(msg.id),
        "group_id": str(msg.group_id),
        "sender_id": str(msg.sender_id),
        "sender_name": sender.full_name if sender else "Unknown",
        "sender_picture": sender.profile_picture if sender else None,
        "content": msg.content,
        "created_at": msg.created_at.isoformat() if msg.created_at else "",
    }
    # Snapshot sockets, then send a per-recipient payload so each gets
    # the right is_me. We piggy-back on manager._groups but build our
    # own loop because is_me depends on the listener, not the sender.
    async with manager._lock:
        sockets = [
            (uid, ws) for ws in manager._groups.get(group_id, ())
            for uid in (getattr(ws, "_njangi_user_id", None),)
            if uid is not None
        ]
    dead: list[WebSocket] = []
    for uid, ws in sockets:
        try:
            await ws.send_json({
                "type": "message",
                **base, "is_me": uid == str(msg.sender_id),
            })
        except Exception:
            dead.append(ws)
    if dead:
        async with manager._lock:
            live = manager._groups.get(group_id)
            if live is not None:
                for ws in dead:
                    live.discard(ws)


# ─── WebSocket: live chat ─────────────────────────────────────
@router.websocket("/groups/{group_id}/chat")
async def chat_socket(
    websocket: WebSocket,
    group_id: str,
    token: str = Query(...),
):
    user_id = _decode_ws_token(token)
    if not user_id:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    # Membership check happens against a fresh session — the WS lifetime
    # is too long for a per-request `get_db` dependency.
    async with AsyncSessionLocal() as db:
        if not await _is_member(db, group_id, user_id):
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return
        g_res = await db.execute(
            select(NjangiGroup).where(NjangiGroup.id == group_id))
        if not g_res.scalar_one_or_none():
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

    await websocket.accept()
    # Stash the user_id on the socket so the broadcaster can compute
    # `is_me` per-recipient without keeping a separate map.
    websocket._njangi_user_id = user_id  # type: ignore[attr-defined]
    await manager.connect(group_id, websocket)
    logger.info("WS chat connect: group=%s user=%s", group_id, user_id)

    try:
        while True:
            data = await websocket.receive_json()
            content = (data.get("content") or "").strip()
            if not content:
                continue
            if len(content) > 2000:
                content = content[:2000]

            # Re-check membership on every inbound — cheap and prevents a
            # removed user from posting after their card got revoked.
            async with AsyncSessionLocal() as db:
                if not await _is_member(db, group_id, user_id):
                    await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
                    return
                msg = NjangiMessage(
                    group_id=group_id, sender_id=user_id, content=content,
                )
                db.add(msg)
                await db.flush()
                await db.refresh(msg)
                await db.commit()

            await _broadcast_to_group(group_id, msg)
    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("WS chat error: group=%s user=%s", group_id, user_id)
    finally:
        await manager.disconnect(group_id, websocket)
        logger.info("WS chat disconnect: group=%s user=%s", group_id, user_id)
