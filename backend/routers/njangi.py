from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import random, string
from datetime import datetime, timedelta, timezone
from core.database import get_db
from core.security import get_current_user
from models.user import User
from models.njangi import (
    NjangiGroup, NjangiMember, NjangiContribution, NjangiPayout, GroupStatus,
)
from models.njangi_schemas import (
    CreateGroupRequest, JoinGroupRequest,
    GroupOut, MemberOut, NjangiResponse,
)

router = APIRouter(prefix="/njangi", tags=["Njangi"])

def _make_code():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))

async def _build_group_out(g, members, user_id, db) -> GroupOut:
    me = next((m for m in members if str(m.user_id) == user_id), None)
    my_pos = me.position if me else 0

    # Single query for every member's User row so we don't hit the DB once
    # per member to render the group card.
    users: dict[str, User] = {}
    if members:
        u_res = await db.execute(
            select(User).where(User.id.in_([m.user_id for m in members])))
        users = {str(u.id): u for u in u_res.scalars().all()}

    member_outs = []
    for m in members:
        u = users.get(str(m.user_id))
        name = u.full_name if u else "Unknown"
        member_outs.append(MemberOut(
            user_id=str(m.user_id),
            profile_picture=u.profile_picture if u else None,
            bio=u.bio if u else None,
            id=str(m.id), position=m.position,
            name="Me (" + name + ")" if str(m.user_id) == user_id else name,
            trust_score=m.trust_score, has_paid=m.has_paid,
            payout_received=m.payout_received, is_me=str(m.user_id) == user_id,
            is_admin=m.is_admin or False,
            is_verified=bool(u.is_verified) if u else False,
        ))

    member_outs.sort(key=lambda x: x.position)
    paid_count = sum(1 for m in members if m.has_paid)
    is_my_turn = my_pos == g.current_cycle

    next_m = next((m for m in members if m.position == g.current_cycle), None)
    next_name = "TBD"
    if next_m:
        u = users.get(str(next_m.user_id))
        if u:
            next_name = "You" if str(next_m.user_id) == user_id else u.full_name

    return GroupOut(
        id=str(g.id), name=g.name, description=g.description, invite_code=g.invite_code,
        contribution=g.contribution, frequency=g.frequency,
        max_members=g.max_members, member_count=len(members),
        current_cycle=g.current_cycle, total_cycles=g.total_cycles,
        status=g.status.value, my_position=my_pos,
        is_admin=str(g.creator_id) == user_id,
        my_trust_score=me.trust_score if me else 100.0,
        pool_amount=g.contribution * len(members),
        is_my_turn=is_my_turn, next_recipient=next_name,
        members=member_outs,
        progress_pct=round((g.current_cycle / g.total_cycles) * 100, 1),
    )

@router.get("", response_model=NjangiResponse)
async def get_njangi(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user["user_id"]
    mem_res = await db.execute(
        select(NjangiMember).where(NjangiMember.user_id == user_id))
    memberships = list(mem_res.scalars().all())

    group_ids = [m.group_id for m in memberships]
    groups_by_id: dict[str, NjangiGroup] = {}
    members_by_group: dict[str, list[NjangiMember]] = {}
    if group_ids:
        g_res = await db.execute(
            select(NjangiGroup).where(NjangiGroup.id.in_(group_ids)))
        groups_by_id = {str(g.id): g for g in g_res.scalars().all()}

        all_m_res = await db.execute(
            select(NjangiMember).where(NjangiMember.group_id.in_(group_ids)))
        for m in all_m_res.scalars().all():
            members_by_group.setdefault(str(m.group_id), []).append(m)

    groups = []
    trust_scores = []
    for membership in memberships:
        g = groups_by_id.get(str(membership.group_id))
        if not g:
            continue
        members = members_by_group.get(str(g.id), [])
        groups.append(await _build_group_out(g, members, user_id, db))
        trust_scores.append(membership.trust_score)

    avg_trust = sum(trust_scores) / len(trust_scores) if trust_scores else 100.0
    return NjangiResponse(groups=groups, trust_score=round(avg_trust, 1))

async def _require_verified(db: AsyncSession, user_id: str) -> User:
    """Block njangi-money actions until the caller has cleared KYC.
    Unverified users can still browse and chat, but they can't move
    real money or anchor a group.

    Short-circuits when `settings.KYC_ENABLED` is false — the KYC
    submission flow is disabled, so blocking on `is_verified` would
    trap users behind a feature they can't access."""
    from core.config import settings
    u_res = await db.execute(select(User).where(User.id == user_id))
    user = u_res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if settings.KYC_ENABLED and not user.is_verified:
        raise HTTPException(
            status_code=403,
            detail="Identity verification required. "
                   "Submit your ID under Profile → Verify Identity to continue.",
        )
    return user


@router.post("/groups", status_code=201)
async def create_group(
    body: CreateGroupRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await _require_verified(db, current_user["user_id"])
    code = _make_code()
    group = NjangiGroup(
        name=body.name, description=body.description, invite_code=code,
        creator_id=current_user["user_id"],
        contribution=body.contribution,
        frequency=body.frequency,
        max_members=body.max_members,
        total_cycles=body.max_members,
    )
    db.add(group)
    await db.flush()

    member = NjangiMember(
        group_id=group.id, user_id=current_user["user_id"], position=1)
    db.add(member)
    await db.flush()
    return {"message": "Group created", "id": str(group.id), "invite_code": code}

@router.post("/groups/join", status_code=200)
async def join_group(
    body: JoinGroupRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await _require_verified(db, current_user["user_id"])
    # Row-lock the group so two simultaneous joins can't both read the same
    # member count and assign the same `position` to different rows.
    g_res = await db.execute(
        select(NjangiGroup)
        .where(NjangiGroup.invite_code == body.invite_code.upper())
        .with_for_update())
    group = g_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    existing = await db.execute(
        select(NjangiMember).where(
            NjangiMember.group_id == group.id,
            NjangiMember.user_id  == current_user["user_id"]))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Already a member")

    count_res = await db.execute(
        select(NjangiMember).where(NjangiMember.group_id == group.id))
    count = len(count_res.scalars().all())
    if count >= group.max_members:
        raise HTTPException(status_code=400, detail="Group is full")

    member = NjangiMember(
        group_id=group.id, user_id=current_user["user_id"],
        position=count + 1)
    db.add(member)

    if count + 1 == group.max_members:
        group.status = GroupStatus.ACTIVE

    await db.flush()
    return {"message": "Joined successfully", "group_name": group.name}

@router.post("/groups/{group_id}/contribute", status_code=200)
async def contribute(
    group_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await _require_verified(db, current_user["user_id"])
    # Row-lock the group so concurrent /contribute calls serialise — otherwise
    # the "all paid → payout" check at the bottom can fire twice and credit
    # the recipient (and insert NjangiPayout) twice for one cycle.
    g_res = await db.execute(
        select(NjangiGroup).where(NjangiGroup.id == group_id).with_for_update())
    group = g_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")
    if group.status != GroupStatus.ACTIVE:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot contribute to a {group.status.value} group",
        )

    m_res = await db.execute(
        select(NjangiMember).where(
            NjangiMember.group_id == group.id,
            NjangiMember.user_id  == current_user["user_id"]))
    member = m_res.scalar_one_or_none()
    if not member:
        raise HTTPException(status_code=403, detail="Not a member")
    if member.has_paid:
        raise HTTPException(status_code=400, detail="Already contributed this cycle")

    u_res = await db.execute(
        select(User).where(User.id == current_user["user_id"]))
    user = u_res.scalar_one()
    if user.total_balance < group.contribution:
        raise HTTPException(
            status_code=400,
            detail="Insufficient balance to contribute",
        )

    contrib = NjangiContribution(
        group_id=group.id, member_id=member.id,
        amount=group.contribution, cycle=group.current_cycle)
    db.add(contrib)
    member.has_paid    = True
    member.trust_score = min(member.trust_score + 2, 100)
    user.total_balance -= group.contribution

    # Check if all paid → process payout
    all_members_res = await db.execute(
        select(NjangiMember).where(NjangiMember.group_id == group.id))
    all_members = all_members_res.scalars().all()
    all_paid = all(m.has_paid for m in all_members)

    payout_msg = None
    if all_paid:
        recipient = next(
            (m for m in all_members if m.position == group.current_cycle), None)
        if recipient:
            pool   = group.contribution * len(all_members)
            net    = (recipient.trust_score / 100) * pool
            escrow = pool - net
            r_res  = await db.execute(
                select(User).where(User.id == recipient.user_id))
            r_user = r_res.scalar_one()
            r_user.total_balance    += net
            recipient.payout_received = True
            # Record this payout for the history view. Persisting trust
            # at payout time means the historical row remains accurate
            # even when the member's score later changes.
            db.add(NjangiPayout(
                group_id=group.id,
                recipient_id=recipient.id,
                cycle=group.current_cycle,
                gross_amount=pool,
                net_amount=net,
                escrow_amount=escrow,
                trust_score=recipient.trust_score,
            ))
            payout_msg = f"Payout of {net:,.0f} FCFA sent!"

        for m in all_members:
            m.has_paid = False
        group.current_cycle += 1
        group.cycle_start_date = datetime.now(timezone.utc)
        if group.current_cycle > group.total_cycles:
            group.status = GroupStatus.COMPLETED

    await db.flush()
    return {
        "message":    "Contribution successful",
        "amount":     group.contribution,
        "all_paid":   all_paid,
        "payout_msg": payout_msg,
    }


class _UpdateMaxRequest(BaseModel):
    max_members: int

@router.patch("/groups/{group_id}/max-members", status_code=200)
async def update_max_members(
    group_id: str,
    body: _UpdateMaxRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    g_res = await db.execute(
        select(NjangiGroup).where(NjangiGroup.id == group_id))
    group = g_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    if str(group.creator_id) != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="Only the admin can change this")

    count_res = await db.execute(
        select(NjangiMember).where(NjangiMember.group_id == group.id))
    current_count = len(count_res.scalars().all())

    if body.max_members < current_count:
        raise HTTPException(status_code=400,
            detail=f"Cannot set max below {current_count} (current member count)")
    if body.max_members < 2:
        raise HTTPException(status_code=400, detail="Minimum 2 members")

    group.max_members  = body.max_members
    group.total_cycles = body.max_members
    await db.flush()
    return {"message": "Max members updated", "max_members": body.max_members}


@router.post("/groups/{group_id}/activate", status_code=200)
async def activate_group(
    group_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    g_res = await db.execute(
        select(NjangiGroup).where(NjangiGroup.id == group_id))
    group = g_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    if str(group.creator_id) != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="Only the admin can activate")

    if group.status == GroupStatus.ACTIVE:
        raise HTTPException(status_code=400, detail="Already active")

    count_res = await db.execute(
        select(NjangiMember).where(NjangiMember.group_id == group.id))
    count = len(count_res.scalars().all())
    if count < 2:
        raise HTTPException(status_code=400,
            detail="Need at least 2 members to activate")

    group.status = GroupStatus.ACTIVE
    group.total_cycles = count
    if hasattr(group, 'cycle_start_date'):
        group.cycle_start_date = datetime.now(timezone.utc)
    await db.flush()
    return {"message": "Group activated", "status": "active"}


@router.get("/groups/preview/{invite_code}", status_code=200)
async def preview_group(
    invite_code: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get group info by invite code BEFORE joining."""
    g_res = await db.execute(
        select(NjangiGroup).where(NjangiGroup.invite_code == invite_code.upper()))
    group = g_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")
    
    members_res = await db.execute(
        select(NjangiMember).where(NjangiMember.group_id == group.id))
    members = members_res.scalars().all()
    
    # Get creator info
    creator_res = await db.execute(
        select(User).where(User.id == group.creator_id))
    creator = creator_res.scalar_one_or_none()
    
    return {
        "id":            str(group.id),
        "name":          group.name,
        "description":   group.description,
        "contribution":  group.contribution,
        "frequency":     group.frequency,
        "max_members":   group.max_members,
        "member_count":  len(members),
        "status":        group.status.value,
        "creator_name":  creator.full_name if creator else "Unknown",
        "creator_picture": creator.profile_picture if creator else None,
    }


# ── Helpers shared by the admin-action endpoints below ─────────────
async def _load_admin_group(group_id: str, current_user: dict, db: AsyncSession):
    """Return the group if it exists AND the caller is its admin.

    Raises 404 if missing, 403 if the caller isn't the creator. Used by
    rename / pause / delete — anything only the group admin should run.
    """
    g_res = await db.execute(
        select(NjangiGroup).where(NjangiGroup.id == group_id))
    group = g_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")
    if str(group.creator_id) != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="Only the admin can do this")
    return group


# ── Rename / edit description ──────────────────────────────────────
class _UpdateGroupRequest(BaseModel):
    name: str | None = None
    description: str | None = None


@router.patch("/groups/{group_id}", status_code=200)
async def update_group(
    group_id: str,
    body: _UpdateGroupRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update editable group fields. Admin-only. Only fields present in
    the body are touched, so a name-only edit doesn't clear description."""
    group = await _load_admin_group(group_id, current_user, db)
    if body.name is not None:
        trimmed = body.name.strip()
        if not trimmed:
            raise HTTPException(status_code=400, detail="Name cannot be empty")
        if len(trimmed) > 100:
            raise HTTPException(status_code=400, detail="Name too long (max 100)")
        group.name = trimmed
    if body.description is not None:
        # Empty string is a valid signal to clear the description.
        if len(body.description) > 500:
            raise HTTPException(status_code=400,
                detail="Description too long (max 500)")
        group.description = body.description.strip() or None
    await db.flush()
    return {"message": "Group updated",
            "name": group.name, "description": group.description}


# ── Pause / resume ─────────────────────────────────────────────────
@router.post("/groups/{group_id}/pause", status_code=200)
async def pause_group(
    group_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Toggle an active group into PAUSED, or resume a paused one back
    to ACTIVE. Pending or completed groups can't be paused."""
    group = await _load_admin_group(group_id, current_user, db)
    if group.status == GroupStatus.ACTIVE:
        group.status = GroupStatus.PAUSED
    elif group.status == GroupStatus.PAUSED:
        group.status = GroupStatus.ACTIVE
    else:
        raise HTTPException(status_code=400,
            detail=f"Can't pause a {group.status.value} group")
    await db.flush()
    return {"message": "Group status toggled", "status": group.status.value}


# ── Delete ─────────────────────────────────────────────────────────
@router.delete("/groups/{group_id}", status_code=200)
async def delete_group(
    group_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Admin-only hard delete. CASCADE on the FK constraints removes the
    members and contribution rows automatically. We refuse to delete an
    active group with members other than the creator — that would orphan
    real cycle data — to force the admin to first pause/refund manually."""
    group = await _load_admin_group(group_id, current_user, db)
    # Block deletion whenever real users other than the admin would lose
    # data — pending groups can already have members who joined via invite
    # before the group activates, so PENDING needs the same guard as ACTIVE.
    if group.status in (GroupStatus.ACTIVE, GroupStatus.PENDING):
        m_res = await db.execute(
            select(NjangiMember).where(NjangiMember.group_id == group.id))
        members = m_res.scalars().all()
        non_admin = [m for m in members
                     if str(m.user_id) != current_user["user_id"]]
        if non_admin:
            raise HTTPException(status_code=400,
                detail="Pause the group and remove other members first")
    await db.delete(group)
    await db.flush()
    return {"message": "Group deleted"}


# ── Leave (for non-admin members) ──────────────────────────────────
@router.post("/groups/{group_id}/leave", status_code=200)
async def leave_group(
    group_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Remove the calling user's membership. Admins can't leave — they
    must transfer ownership or delete the group instead. We also block
    leaving mid-cycle if the user has already paid this cycle, so the
    pot stays consistent until the next cycle boundary."""
    g_res = await db.execute(
        select(NjangiGroup).where(NjangiGroup.id == group_id))
    group = g_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")
    if str(group.creator_id) == current_user["user_id"]:
        raise HTTPException(status_code=400,
            detail="Admins can't leave their own group. Delete it instead.")

    m_res = await db.execute(
        select(NjangiMember).where(
            NjangiMember.group_id == group.id,
            NjangiMember.user_id == current_user["user_id"]))
    member = m_res.scalar_one_or_none()
    if not member:
        raise HTTPException(status_code=404, detail="You aren't in this group")

    if group.status == GroupStatus.ACTIVE and member.has_paid:
        raise HTTPException(status_code=400,
            detail="You already paid this cycle. Wait until the next "
                   "cycle starts before leaving.")

    await db.delete(member)
    await db.flush()
    return {"message": "Left the group"}


# ── Payment history ────────────────────────────────────────────────
@router.get("/groups/{group_id}/history", status_code=200)
async def group_history(
    group_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Returns a unified, time-ordered event stream for the group:
       - contributions (every time a member paid in)
       - payouts       (every time a cycle closed and someone got paid)

    Only members of the group can fetch this. The response shape mirrors
    a feed: each item has `type`, a human label, an amount, the cycle it
    relates to, and the actor's name/picture, so the client can render
    one timeline without needing two parallel sections.
    """
    g_res = await db.execute(
        select(NjangiGroup).where(NjangiGroup.id == group_id))
    group = g_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    # Caller must be a member (or the creator, for the case where the
    # creator hasn't been added to njangi_members — defensive).
    m_res = await db.execute(
        select(NjangiMember).where(
            NjangiMember.group_id == group.id,
            NjangiMember.user_id  == current_user["user_id"]))
    if not m_res.scalar_one_or_none() and \
            str(group.creator_id) != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="Not a member")

    # Pre-load every member + their user record so we can label rows
    # without a query per row.
    all_m_res = await db.execute(
        select(NjangiMember).where(NjangiMember.group_id == group.id))
    members = {str(m.id): m for m in all_m_res.scalars().all()}
    users = {}
    if members:
        u_res = await db.execute(
            select(User).where(
                User.id.in_([m.user_id for m in members.values()])))
        users = {str(u.id): u for u in u_res.scalars().all()}

    def _label(member_id, user_id_for_self):
        m = members.get(str(member_id))
        if not m:
            return "Former member"
        u = users.get(str(m.user_id))
        if not u:
            return "Unknown"
        if str(m.user_id) == user_id_for_self:
            return f"You ({u.full_name})"
        return u.full_name

    def _picture(member_id):
        m = members.get(str(member_id))
        if not m:
            return None
        u = users.get(str(m.user_id))
        return u.profile_picture if u else None

    me = current_user["user_id"]

    # Contributions
    c_res = await db.execute(
        select(NjangiContribution).where(
            NjangiContribution.group_id == group.id))
    contribs = c_res.scalars().all()

    # Payouts
    p_res = await db.execute(
        select(NjangiPayout).where(NjangiPayout.group_id == group.id))
    payouts = p_res.scalars().all()

    events = []
    for c in contribs:
        events.append({
            "type":       "contribution",
            "actor":      _label(c.member_id, me),
            "picture":    _picture(c.member_id),
            "cycle":      c.cycle,
            "amount":     c.amount,
            "provider":   c.provider,
            "created_at": c.created_at.isoformat() if c.created_at else None,
        })
    for p in payouts:
        events.append({
            "type":          "payout",
            "actor":         _label(p.recipient_id, me),
            "picture":       _picture(p.recipient_id),
            "cycle":         p.cycle,
            "amount":        p.net_amount,
            "gross_amount":  p.gross_amount,
            "escrow_amount": p.escrow_amount,
            "trust_score":   p.trust_score,
            "created_at":    p.created_at.isoformat() if p.created_at else None,
        })

    # Newest first. Items with no timestamp (shouldn't happen normally
    # since the column has server_default) sort to the bottom.
    events.sort(
        key=lambda e: e["created_at"] or "",
        reverse=True,
    )
    return {"events": events}
