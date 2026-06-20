"""Tests for the two-phase Njangi payout flow and retry endpoint."""
from unittest.mock import AsyncMock, MagicMock, patch
import pytest
from fastapi import HTTPException


def _make_group(contribution=5000.0, current_cycle=1, total_cycles=4, member_count=4):
    g = MagicMock()
    g.id = "group-uuid-1"
    g.name = "Test Njangi"
    g.contribution = contribution
    g.current_cycle = current_cycle
    g.total_cycles = total_cycles
    g.status = MagicMock()
    g.status.value = "active"
    return g


def _make_member(position=1, trust_score=100.0, has_paid=False, user_id="user-uuid-1"):
    m = MagicMock()
    m.id = "member-uuid-1"
    m.user_id = user_id
    m.position = position
    m.trust_score = trust_score
    m.has_paid = has_paid
    m.payout_received = False
    return m


def _make_user(user_id="user-uuid-1", total_balance=20000.0):
    u = MagicMock()
    u.id = user_id
    u.total_balance = total_balance
    return u


def _make_conn(phone="670000000", verified=True):
    c = MagicMock()
    c.phone = phone
    c.verified = verified
    return c


# ── _settle_contribution ────────────────────────────────────────────

@pytest.mark.asyncio
async def test_settle_contribution_not_all_paid():
    """When members haven't all paid, no payout is created."""
    from routers.njangi import _settle_contribution

    group = _make_group(contribution=5000.0, current_cycle=1)
    paying_member = _make_member(position=1, trust_score=100.0)
    user = _make_user(total_balance=20000.0)

    other = _make_member(position=2, trust_score=90.0, has_paid=False, user_id="user-uuid-2")
    paying_member.has_paid = False

    db = AsyncMock()
    members_result = MagicMock()
    members_result.scalars.return_value.all.return_value = [paying_member, other]
    db.execute = AsyncMock(return_value=members_result)
    db.add = MagicMock()
    db.flush = AsyncMock()

    result = await _settle_contribution(db, group, paying_member, user)

    assert result["all_paid"] is False
    assert result.get("payout_id") is None
    db.add.assert_not_called()


@pytest.mark.asyncio
async def test_settle_contribution_all_paid_creates_pending_payout():
    """When all members paid, creates NjangiPayout with payout_status='pending_momo'."""
    from routers.njangi import _settle_contribution
    from models.njangi import NjangiPayout

    group = _make_group(contribution=5000.0, current_cycle=1, total_cycles=4)
    paying_member = _make_member(position=1, trust_score=100.0)
    other_member = _make_member(position=2, trust_score=90.0, has_paid=True, user_id="user-uuid-2")
    user = _make_user()

    db = AsyncMock()
    members_result = MagicMock()
    members_result.scalars.return_value.all.return_value = [paying_member, other_member]
    recipient_user = _make_user(user_id="user-uuid-1", total_balance=5000.0)
    recipient_result = MagicMock()
    recipient_result.scalar_one.return_value = recipient_user
    db.execute = AsyncMock(side_effect=[members_result, recipient_result])
    db.add = MagicMock()
    db.flush = AsyncMock()

    result = await _settle_contribution(db, group, paying_member, user)

    assert result["all_paid"] is True
    assert result["payout_id"] is not None
    db.add.assert_called()
    added_obj = db.add.call_args[0][0]
    assert isinstance(added_obj, NjangiPayout)
    assert added_obj.payout_status == "pending_momo"
    # total_balance must NOT have been modified
    assert recipient_user.total_balance == 5000.0


# ── retry endpoint ──────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_retry_payout_no_pending():
    """Retry with no pending_momo payout → 404."""
    from routers.njangi import retry_njangi_payout

    group = _make_group()
    group.creator_id = "creator-uuid"

    db = AsyncMock()
    group_result = MagicMock()
    group_result.scalar_one_or_none.return_value = group
    payout_result = MagicMock()
    payout_result.scalar_one_or_none.return_value = None
    db.execute = AsyncMock(side_effect=[group_result, payout_result])

    current_user = {"user_id": "creator-uuid"}

    with pytest.raises(HTTPException) as exc_info:
        await retry_njangi_payout("group-uuid-1", current_user=current_user, db=db)

    assert exc_info.value.status_code == 404


@pytest.mark.asyncio
async def test_retry_payout_no_recipient_momo():
    """Pending payout but recipient has no verified MoMo → 400."""
    from routers.njangi import retry_njangi_payout
    from models.njangi import NjangiPayout

    payout = MagicMock(spec=NjangiPayout)
    payout.id = "payout-uuid-1"
    payout.net_amount = 20000.0
    payout.payout_status = "pending_momo"
    payout.recipient_id = "member-uuid-1"

    recipient_member = _make_member(user_id="user-uuid-2")
    group = _make_group()
    group.creator_id = "creator-uuid"

    db = AsyncMock()
    group_result = MagicMock()
    group_result.scalar_one_or_none.return_value = group
    payout_result = MagicMock()
    payout_result.scalar_one_or_none.return_value = payout
    member_result = MagicMock()
    member_result.scalar_one_or_none.return_value = recipient_member
    conn_result = MagicMock()
    conn_result.scalar_one_or_none.return_value = None
    db.execute = AsyncMock(side_effect=[group_result, payout_result, member_result, conn_result])
    db.flush = AsyncMock()

    current_user = {"user_id": "creator-uuid"}

    with pytest.raises(HTTPException) as exc_info:
        await retry_njangi_payout("group-uuid-1", current_user=current_user, db=db)

    assert exc_info.value.status_code == 400
    assert "MoMo" in exc_info.value.detail


@pytest.mark.asyncio
async def test_retry_payout_transfer_succeeds():
    """Retry with valid wallet → transfer called, payout_status set to completed."""
    from routers.njangi import retry_njangi_payout
    from models.njangi import NjangiPayout

    payout = MagicMock(spec=NjangiPayout)
    payout.id = "payout-uuid-1"
    payout.net_amount = 20000.0
    payout.payout_status = "pending_momo"
    payout.recipient_id = "member-uuid-1"
    payout.cycle = 1

    recipient_member = _make_member(user_id="user-uuid-2")
    conn = _make_conn(phone="670111222")
    group = _make_group()
    group.creator_id = "creator-uuid"

    db = AsyncMock()
    group_result = MagicMock()
    group_result.scalar_one_or_none.return_value = group
    payout_result = MagicMock()
    payout_result.scalar_one_or_none.return_value = payout
    member_result = MagicMock()
    member_result.scalar_one_or_none.return_value = recipient_member
    conn_result = MagicMock()
    conn_result.scalar_one_or_none.return_value = conn
    db.execute = AsyncMock(side_effect=[group_result, payout_result, member_result, conn_result])
    db.add = MagicMock()
    db.flush = AsyncMock()

    current_user = {"user_id": "creator-uuid"}

    with patch("routers.njangi.momo_provider.transfer", return_value="ref-retry-001"):
        result = await retry_njangi_payout("group-uuid-1", current_user=current_user, db=db)

    assert result["status"] == "completed"
    assert result["momo_reference"] == "ref-retry-001"
    assert payout.payout_status == "completed"
    assert payout.transfer_reference == "ref-retry-001"
    assert payout.recipient_phone == "670111222"
