"""Unit tests for the savings withdrawal refactor.

We test the business logic by calling the endpoint function with mocked
DB and mocked Campay. No real DB or network needed.
"""
from unittest.mock import AsyncMock, MagicMock, patch
import pytest
from fastapi import HTTPException


def _make_goal(current=10000.0, target=50000.0):
    g = MagicMock()
    g.id = "goal-uuid-1"
    g.current = current
    g.target = target
    g.is_completed = False
    g.is_locked = False
    return g


def _make_conn(phone="670000000", verified=True):
    c = MagicMock()
    c.phone = phone
    c.verified = verified
    return c


def _make_db(goal, conn_or_none):
    """Return a mock AsyncSession that returns goal and optionally a MoMoConnection."""
    db = AsyncMock()

    goal_result = MagicMock()
    goal_result.scalar_one_or_none.return_value = goal

    conn_result = MagicMock()
    conn_result.scalar_one_or_none.return_value = conn_or_none

    db.execute = AsyncMock(side_effect=[goal_result, conn_result])
    db.add = MagicMock()
    db.flush = AsyncMock()
    return db


@pytest.mark.asyncio
async def test_withdraw_requires_verified_momo():
    """No verified MoMo → 400 before any Campay call."""
    from routers.savings import withdraw

    goal = _make_goal()
    db = _make_db(goal, conn_or_none=None)
    current_user = {"user_id": "user-uuid-1"}

    with pytest.raises(HTTPException) as exc_info:
        await withdraw("goal-uuid-1", current_user=current_user, db=db)

    assert exc_info.value.status_code == 400
    assert "MoMo" in exc_info.value.detail
    assert goal.current == 10000.0


@pytest.mark.asyncio
async def test_withdraw_returns_400_on_transfer_failure():
    """Campay transfer error → 400, goal unchanged."""
    from routers.savings import withdraw
    from services.momo_provider import MoMoApiError

    goal = _make_goal(current=10000.0)
    conn = _make_conn()
    db = _make_db(goal, conn)
    current_user = {"user_id": "user-uuid-1"}

    with patch("routers.savings.momo_provider.transfer", side_effect=MoMoApiError("sandbox limit")):
        with pytest.raises(HTTPException) as exc_info:
            await withdraw("goal-uuid-1", current_user=current_user, db=db)

    assert exc_info.value.status_code == 400
    assert "sandbox limit" in exc_info.value.detail
    assert goal.current == 10000.0


@pytest.mark.asyncio
async def test_withdraw_zeros_goal_on_success():
    """Successful transfer → goal zeroed, MoMoTransfer added, correct payout."""
    from routers.savings import withdraw

    goal = _make_goal(current=10000.0)
    conn = _make_conn(phone="670000000")
    db = _make_db(goal, conn)
    current_user = {"user_id": "user-uuid-1"}

    with patch("routers.savings.momo_provider.transfer", return_value="ref-xyz"):
        result = await withdraw("goal-uuid-1", current_user=current_user, db=db)

    assert result["payout"] == 9000.0
    assert result["penalty"] == 1000.0
    assert result["momo_reference"] == "ref-xyz"
    assert goal.current == 0
    assert goal.is_locked is True
    assert goal.is_completed is False
    db.add.assert_called_once()
    transfer_obj = db.add.call_args[0][0]
    from models.momo import MoMoTransfer
    assert isinstance(transfer_obj, MoMoTransfer)
    assert transfer_obj.amount == 9000.0
    assert transfer_obj.purpose == "savings_withdrawal"
    assert transfer_obj.status == "SUCCESSFUL"
