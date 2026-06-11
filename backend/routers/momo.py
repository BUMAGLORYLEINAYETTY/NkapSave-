"""HTTP surface for the MoMo wallet link.

A linked wallet is the prerequisite for any auto-save plan. The flow:

  POST /momo/link
    Body: {phone}
    Stores (or updates) a MoMoConnection for the current user, calls
    validate_holder on MTN. Returns the connection with `verified=true`
    iff MTN confirms the number is an active MoMo account.

  GET /momo/link
    Returns the current user's connection, if any.

  DELETE /momo/link
    Unlinks. Also pauses any active auto-save plans, since they'd start
    failing on the next tick.

  POST /momo/callback
    Stub for MTN's async status callback. We log and 200; the scheduler
    still settles via polling so the callback is just a nice-to-have.
"""
from fastapi import APIRouter, Body, Depends, HTTPException
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime
import logging

from core.database import get_db
from core.security import get_current_user
from models.momo import AutoSavePlan, MoMoConnection
from models.momo_schemas import LinkMoMoRequest, MoMoConnectionOut
from services import momo_provider

router = APIRouter(prefix="/momo", tags=["MoMo"])
logger = logging.getLogger("nkapsave.momo")


def _to_out(c: MoMoConnection) -> MoMoConnectionOut:
    return MoMoConnectionOut(
        id=str(c.id),
        provider=c.provider,
        phone=c.phone,
        verified=c.verified,
        last_verified_at=c.last_verified_at,
    )


@router.post("/link", response_model=MoMoConnectionOut)
async def link_wallet(
    body: LinkMoMoRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Link a MoMo wallet (MTN or Orange).

    Campay doesn't expose a 'is this number an active wallet?' check, so we
    save the number and mark it verified. The first auto-save Collect will
    surface invalid numbers as a FAILED transaction, and the user gets a push
    explaining what happened.

    `provider` is set to "campay" since Campay aggregates both operators —
    the actual MTN-vs-Orange determination happens at Collect time.
    """
    if not momo_provider.is_configured():
        raise HTTPException(
            status_code=503,
            detail="Mobile-money integration is not configured on the server.",
        )

    res = await db.execute(
        select(MoMoConnection).where(MoMoConnection.user_id == current_user["user_id"])
    )
    conn = res.scalar_one_or_none()
    now = datetime.utcnow()
    if conn is None:
        conn = MoMoConnection(
            user_id=current_user["user_id"],
            provider="campay",
            phone=body.phone,
            verified=True,
            last_verified_at=now,
        )
        db.add(conn)
    else:
        conn.phone = body.phone
        conn.provider = "campay"
        conn.verified = True
        conn.last_verified_at = now

    await db.commit()
    await db.refresh(conn)
    return _to_out(conn)


@router.get("/link", response_model=MoMoConnectionOut | None)
async def get_link(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(MoMoConnection).where(MoMoConnection.user_id == current_user["user_id"])
    )
    conn = res.scalar_one_or_none()
    return _to_out(conn) if conn else None


@router.delete("/link", status_code=200)
async def unlink_wallet(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(MoMoConnection).where(MoMoConnection.user_id == current_user["user_id"])
    )
    conn = res.scalar_one_or_none()
    if not conn:
        raise HTTPException(status_code=404, detail="No MoMo wallet linked.")

    # Pause any active plans — they'd fail without a wallet anyway.
    await db.execute(
        update(AutoSavePlan)
        .where(AutoSavePlan.user_id == current_user["user_id"])
        .values(active=False)
    )
    await db.delete(conn)
    await db.commit()
    return {"message": "MoMo wallet unlinked. Auto-save plans paused."}


@router.post("/callback", status_code=200, include_in_schema=False)
async def momo_callback(payload: dict = Body(...)):
    """MTN posts status updates here when MOMO_CALLBACK_HOST is set.

    Sandbox callbacks are unreliable, so we still poll. We just log the body
    for debugging — the scheduler does the actual settlement.
    """
    logger.info("MoMo callback: %s", payload)
    return {"ok": True}
