# Campay Real Payouts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace virtual-balance-only payout logic with real Campay outbound transfers for savings withdrawals and Njangi cycle payouts.

**Architecture:** Add `momo_provider.transfer()` as the outbound symmetric of the existing `request_to_pay()`. Savings withdrawal calls it inline (fail = 400, goal unchanged). Njangi payout uses a two-phase pattern: commit the `pending_momo` payout record first, then call Campay outside the transaction, then update status — preventing DB locks from being held during slow operator responses.

**Tech Stack:** FastAPI, SQLAlchemy 2.0 async, httpx (already installed), pytest + pytest-asyncio (to add), Campay REST API.

## Global Constraints

- Never make an HTTP call to Campay while an open SQLAlchemy transaction is in progress — hold no DB lock across network I/O.
- All migration functions must be idempotent (`IF NOT EXISTS` / `IF EXISTS`).
- Existing rows in `njangi_payouts` must keep working — new columns default to `completed`/NULL.
- Do not touch `user.total_balance` in withdrawal or Njangi payout paths — real money goes to MoMo, not to the virtual balance.
- Follow the existing error-type convention: `MoMoNotConfigured` and `MoMoApiError` from `services/momo_provider.py`.
- All tests live in `backend/tests/`. Run them from the `backend/` directory.

---

### Task 1: Test infrastructure + `momo_provider.transfer()`

**Files:**
- Modify: `backend/requirements.txt`
- Modify: `backend/services/momo_provider.py`
- Create: `backend/tests/__init__.py`
- Create: `backend/tests/test_momo_provider.py`

**Interfaces:**
- Produces:
  ```python
  # in services/momo_provider.py
  def transfer(
      *,
      phone: str,
      amount: int,
      external_id: str,
      description: str,
  ) -> str:
      """Initiate a Campay outbound transfer. Returns Campay reference string.
      Raises MoMoApiError on HTTP 4xx/5xx or missing reference.
      Raises MoMoNotConfigured if creds are absent."""
  ```

- [ ] **Step 1: Add pytest dependencies to requirements.txt**

  Append to `backend/requirements.txt`:
  ```
  # Testing
  pytest>=8.0
  pytest-asyncio>=0.23
  ```

- [ ] **Step 2: Install them**

  ```bash
  cd backend && source venv/bin/activate && pip install pytest>=8.0 pytest-asyncio>=0.23
  ```

- [ ] **Step 3: Create test package**

  Create `backend/tests/__init__.py` — empty file.

- [ ] **Step 4: Write the failing tests for `transfer()`**

  Create `backend/tests/test_momo_provider.py`:

  ```python
  from unittest.mock import MagicMock, patch
  import pytest
  from services import momo_provider


  # ── helpers ────────────────────────────────────────────────────────

  def _mock_settings(monkeypatch):
      monkeypatch.setattr(momo_provider.settings, "CAMPAY_USERNAME", "user")
      monkeypatch.setattr(momo_provider.settings, "CAMPAY_PASSWORD", "pass")
      monkeypatch.setattr(momo_provider.settings, "CAMPAY_ENV", "sandbox")
      monkeypatch.setattr(momo_provider.settings, "DEFAULT_COUNTRY_CODE", "237")


  def _ok_token_response():
      m = MagicMock()
      m.status_code = 200
      m.json.return_value = {"token": "tok123", "expires_in": 3300}
      return m


  def _ok_transfer_response():
      m = MagicMock()
      m.status_code = 200
      m.json.return_value = {"reference": "ref-transfer-001"}
      return m


  # ── transfer() tests ───────────────────────────────────────────────

  def test_transfer_returns_reference(monkeypatch):
      """Happy path: transfer() returns the Campay reference string."""
      _mock_settings(monkeypatch)
      # Force token refresh so we don't need a real cache
      monkeypatch.setattr(momo_provider, "_token_cache", None)

      with patch("httpx.post") as mock_post:
          mock_post.side_effect = [_ok_token_response(), _ok_transfer_response()]
          ref = momo_provider.transfer(
              phone="670000000",
              amount=5000,
              external_id="ext-001",
              description="Test payout",
          )

      assert ref == "ref-transfer-001"
      # Second call should be to /transfer/
      transfer_call = mock_post.call_args_list[1]
      assert "/transfer/" in transfer_call.args[0]
      body = transfer_call.kwargs["json"]
      assert body["amount"] == "5000"
      assert body["to"] == "237670000000"
      assert body["external_reference"] == "ext-001"
      assert body["description"] == "Test payout"


  def test_transfer_raises_on_4xx(monkeypatch):
      """Campay 4xx → MoMoApiError."""
      _mock_settings(monkeypatch)
      monkeypatch.setattr(momo_provider, "_token_cache", None)

      err_response = MagicMock()
      err_response.status_code = 400
      err_response.text = '{"message":"Bad request"}'

      with patch("httpx.post") as mock_post:
          mock_post.side_effect = [_ok_token_response(), err_response]
          with pytest.raises(momo_provider.MoMoApiError):
              momo_provider.transfer(
                  phone="670000000", amount=100,
                  external_id="ext-002", description="fail",
              )


  def test_transfer_raises_when_reference_missing(monkeypatch):
      """Campay 200 but no 'reference' field → MoMoApiError."""
      _mock_settings(monkeypatch)
      monkeypatch.setattr(momo_provider, "_token_cache", None)

      bad_response = MagicMock()
      bad_response.status_code = 200
      bad_response.json.return_value = {}  # no "reference" key

      with patch("httpx.post") as mock_post:
          mock_post.side_effect = [_ok_token_response(), bad_response]
          with pytest.raises(momo_provider.MoMoApiError, match="missing 'reference'"):
              momo_provider.transfer(
                  phone="670000000", amount=100,
                  external_id="ext-003", description="fail",
              )


  def test_transfer_raises_when_not_configured(monkeypatch):
      """Missing credentials → MoMoNotConfigured before any HTTP call."""
      monkeypatch.setattr(momo_provider.settings, "CAMPAY_USERNAME", None)
      monkeypatch.setattr(momo_provider.settings, "CAMPAY_PASSWORD", None)
      monkeypatch.setattr(momo_provider, "_token_cache", None)

      with pytest.raises(momo_provider.MoMoNotConfigured):
          momo_provider.transfer(
              phone="670000000", amount=100,
              external_id="ext-004", description="fail",
          )


  def test_transfer_normalises_local_phone(monkeypatch):
      """9-digit local number is prefixed with country code."""
      _mock_settings(monkeypatch)
      monkeypatch.setattr(momo_provider, "_token_cache", None)

      with patch("httpx.post") as mock_post:
          mock_post.side_effect = [_ok_token_response(), _ok_transfer_response()]
          momo_provider.transfer(
              phone="670123456", amount=1000,
              external_id="ext-005", description="norm",
          )

      transfer_call = mock_post.call_args_list[1]
      assert transfer_call.kwargs["json"]["to"] == "237670123456"
  ```

- [ ] **Step 5: Run tests — expect all to FAIL**

  ```bash
  cd backend && source venv/bin/activate && python -m pytest tests/test_momo_provider.py -v
  ```
  Expected: `AttributeError: module 'services.momo_provider' has no attribute 'transfer'`

- [ ] **Step 6: Implement `transfer()` in `services/momo_provider.py`**

  Add this function after `request_to_pay()` (around line 189), before `get_status()`:

  ```python
  def transfer(
      *, phone: str, amount: int, external_id: str, description: str,
  ) -> str:
      """Initiate a Campay outbound transfer to a subscriber.

      Sends `amount` XAF from the merchant wallet to `phone`. Returns the
      Campay reference string. Raises MoMoApiError on rejection.
      """
      _require_creds()
      url = f"{_base_url()}/transfer/"
      body = {
          "amount":             str(int(amount)),
          "to":                 _msisdn(phone),
          "description":        description[:160],
          "external_reference": external_id,
      }
      try:
          resp = httpx.post(url, headers=_auth_headers(), json=body, timeout=30.0)
      except httpx.HTTPError as e:
          raise MoMoApiError(f"Network error on transfer: {e}") from e

      if resp.status_code >= 400:
          raise MoMoApiError(
              f"Campay transfer rejected: {resp.status_code} {resp.text[:200]}"
          )

      data = resp.json()
      reference = data.get("reference")
      if not reference:
          raise MoMoApiError(f"Campay transfer response missing 'reference': {data}")
      logger.info(
          "Campay transfer accepted ref=%s amount=%s phone=%s",
          reference, amount, _msisdn(phone),
      )
      return reference
  ```

- [ ] **Step 7: Run tests — expect all to PASS**

  ```bash
  cd backend && source venv/bin/activate && python -m pytest tests/test_momo_provider.py -v
  ```
  Expected: 5 tests PASSED

- [ ] **Step 8: Commit**

  ```bash
  git add backend/requirements.txt backend/services/momo_provider.py backend/tests/__init__.py backend/tests/test_momo_provider.py
  git commit -m "feat: add Campay transfer() for outbound MoMo payouts"
  ```

---

### Task 2: `MoMoTransfer` model + `NjangiPayout` columns + migrations

**Files:**
- Modify: `backend/models/momo.py`
- Modify: `backend/models/njangi.py`
- Modify: `backend/core/migrations.py`

**Interfaces:**
- Produces:
  ```python
  # models/momo.py
  class MoMoTransfer(Base):
      __tablename__ = "momo_transfers"
      id, user_id, reference_id, external_id, amount, currency, phone,
      status, reason, purpose, related_id, initiated_at, completed_at

  # models/njangi.py — NjangiPayout gets 3 new columns:
  payout_status: str       # "pending_momo" | "completed" | "failed"
  transfer_reference: str  # Campay reference
  recipient_phone: str     # destination MSISDN
  ```

- [ ] **Step 1: Add `MoMoTransfer` to `backend/models/momo.py`**

  Append this class at the end of `backend/models/momo.py` (after the `MoMoTransaction` class):

  ```python


  class MoMoTransfer(Base):
      """Audit log of every outbound Campay transfer (money sent TO a user).

      Symmetric counterpart to MoMoTransaction (inbound collects).
      `purpose` distinguishes savings withdrawals from njangi payouts.
      """
      __tablename__ = "momo_transfers"

      id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
      user_id       = Column(UUID(as_uuid=True),
                             ForeignKey("users.id", ondelete="CASCADE"),
                             nullable=False, index=True)
      reference_id  = Column(String(64), unique=True, nullable=False, index=True)
      external_id   = Column(String(64), nullable=False)
      amount        = Column(Float, nullable=False)
      currency      = Column(String(8), nullable=False, default="XAF")
      phone         = Column(String(20), nullable=False)
      status        = Column(String(20), nullable=False, default="SUCCESSFUL")
      reason        = Column(Text, nullable=True)
      # "savings_withdrawal" | "njangi_payout"
      purpose       = Column(String(30), nullable=False)
      # goal_id for savings_withdrawal; payout_id (str) for njangi_payout
      related_id    = Column(String(64), nullable=True)
      initiated_at  = Column(DateTime(timezone=True), server_default=func.now())
      completed_at  = Column(DateTime(timezone=True), nullable=True)
  ```

- [ ] **Step 2: Add 3 columns to `NjangiPayout` in `backend/models/njangi.py`**

  Find the `NjangiPayout` class (currently ends at `created_at` column around line 131). Add 3 columns after `trust_score` and before `created_at`:

  ```python
      # Outbound transfer tracking. payout_status defaults to 'completed' so
      # existing rows (paid before real transfers existed) remain valid.
      payout_status      = Column(String(30), nullable=False, default="completed")
      transfer_reference = Column(String(64), nullable=True)
      recipient_phone    = Column(String(20), nullable=True)
      created_at    = Column(DateTime(timezone=True), server_default=func.now())
  ```

  The full `NjangiPayout` class should now look like:
  ```python
  class NjangiPayout(Base):
      __tablename__ = "njangi_payouts"
      id            = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
      group_id      = Column(UUID(as_uuid=True),
                             ForeignKey("njangi_groups.id", ondelete="CASCADE"),
                             nullable=False, index=True)
      recipient_id  = Column(UUID(as_uuid=True),
                             ForeignKey("njangi_members.id", ondelete="CASCADE"),
                             nullable=False, index=True)
      cycle         = Column(Integer, nullable=False)
      gross_amount  = Column(Float, nullable=False)
      net_amount    = Column(Float, nullable=False)
      escrow_amount = Column(Float, default=0.0)
      trust_score   = Column(Float, nullable=False)
      payout_status      = Column(String(30), nullable=False, default="completed")
      transfer_reference = Column(String(64), nullable=True)
      recipient_phone    = Column(String(20), nullable=True)
      created_at    = Column(DateTime(timezone=True), server_default=func.now())
  ```

- [ ] **Step 3: Add two migration functions to `backend/core/migrations.py`**

  Add these two functions before `run_dev_migrations()`:

  ```python
  async def add_njangi_payout_transfer_columns(engine: AsyncEngine) -> None:
      """Add payout_status, transfer_reference, recipient_phone to njangi_payouts.

      Existing rows keep payout_status='completed' — they were paid before
      real Campay transfers existed and are considered settled."""
      async with engine.begin() as conn:
          for sql in [
              "ALTER TABLE njangi_payouts ADD COLUMN IF NOT EXISTS "
              "payout_status VARCHAR(30) NOT NULL DEFAULT 'completed'",
              "ALTER TABLE njangi_payouts ADD COLUMN IF NOT EXISTS "
              "transfer_reference VARCHAR(64)",
              "ALTER TABLE njangi_payouts ADD COLUMN IF NOT EXISTS "
              "recipient_phone VARCHAR(20)",
          ]:
              await conn.execute(text(sql))


  async def add_momo_transfers_table(engine: AsyncEngine) -> None:
      """Create the momo_transfers table for outbound Campay transfer audit log."""
      async with engine.begin() as conn:
          await conn.execute(text("""
              CREATE TABLE IF NOT EXISTS momo_transfers (
                  id UUID PRIMARY KEY,
                  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                  reference_id VARCHAR(64) UNIQUE NOT NULL,
                  external_id VARCHAR(64) NOT NULL,
                  amount FLOAT NOT NULL,
                  currency VARCHAR(8) NOT NULL DEFAULT 'XAF',
                  phone VARCHAR(20) NOT NULL,
                  status VARCHAR(20) NOT NULL DEFAULT 'SUCCESSFUL',
                  reason TEXT,
                  purpose VARCHAR(30) NOT NULL,
                  related_id VARCHAR(64),
                  initiated_at TIMESTAMPTZ DEFAULT now(),
                  completed_at TIMESTAMPTZ
              )
          """))
  ```

- [ ] **Step 4: Register both functions in `run_dev_migrations()`**

  In `migrations.py`, update the `run_dev_migrations` function body. Replace:
  ```python
      try:
          await migrate_expenses_to_unified(engine)
          await add_user_kyc_reviewer_column(engine)
          await add_njangi_contribution_payment_columns(engine)
          await backfill_njangi_creator_admin(engine)
          await add_email_verification_columns(engine)
          await add_momo_goal_id_column(engine)
          await add_auto_save_plan_columns(engine)
          await unlock_existing_savings_goals(engine)
  ```
  With:
  ```python
      try:
          await migrate_expenses_to_unified(engine)
          await add_user_kyc_reviewer_column(engine)
          await add_njangi_contribution_payment_columns(engine)
          await backfill_njangi_creator_admin(engine)
          await add_email_verification_columns(engine)
          await add_momo_goal_id_column(engine)
          await add_auto_save_plan_columns(engine)
          await unlock_existing_savings_goals(engine)
          await add_njangi_payout_transfer_columns(engine)
          await add_momo_transfers_table(engine)
  ```

- [ ] **Step 5: Verify the module imports cleanly**

  ```bash
  cd backend && source venv/bin/activate && python -c "from models.momo import MoMoTransfer; from models.njangi import NjangiPayout; print('OK', MoMoTransfer.__tablename__, NjangiPayout.__tablename__)"
  ```
  Expected: `OK momo_transfers njangi_payouts`

- [ ] **Step 6: Commit**

  ```bash
  git add backend/models/momo.py backend/models/njangi.py backend/core/migrations.py
  git commit -m "feat: add MoMoTransfer model and NjangiPayout transfer columns"
  ```

---

### Task 3: Savings withdrawal — real Campay transfer

**Files:**
- Modify: `backend/routers/savings.py`
- Create: `backend/tests/test_savings_withdraw.py`

**Interfaces:**
- Consumes:
  - `momo_provider.transfer(*, phone, amount, external_id, description) -> str` (Task 1)
  - `MoMoTransfer` model (Task 2)
  - `MoMoConnection` model (already exists in `models/momo.py`)
- Produces:
  - `PATCH /api/v1/savings/goals/{goal_id}/withdraw` now requires a verified MoMo wallet and performs a real Campay transfer before zeroing the goal.
  - Response: `{"payout": float, "penalty": float, "momo_reference": str, "message": str}`

- [ ] **Step 1: Write failing tests**

  Create `backend/tests/test_savings_withdraw.py`:

  ```python
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

      # First execute → goal result
      goal_result = MagicMock()
      goal_result.scalar_one_or_none.return_value = goal

      # Second execute → MoMoConnection result
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
      # Goal must be untouched
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
      assert goal.current == 10000.0   # goal must be untouched


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
      # MoMoTransfer should have been added to the session
      db.add.assert_called_once()
      transfer_obj = db.add.call_args[0][0]
      from models.momo import MoMoTransfer
      assert isinstance(transfer_obj, MoMoTransfer)
      assert transfer_obj.amount == 9000.0
      assert transfer_obj.purpose == "savings_withdrawal"
      assert transfer_obj.status == "SUCCESSFUL"
  ```

- [ ] **Step 2: Run tests — expect FAIL**

  ```bash
  cd backend && source venv/bin/activate && python -m pytest tests/test_savings_withdraw.py -v
  ```
  Expected: tests fail because `withdraw` still has the old implementation.

- [ ] **Step 3: Refactor `withdraw` in `backend/routers/savings.py`**

  Add `import uuid` at the top of the file if not already present, and add the import for `MoMoTransfer` and `momo_provider`:

  At the top of `backend/routers/savings.py`, after the existing imports, ensure these are present:
  ```python
  import uuid
  from services import momo_provider
  from models.momo import AutoSavePlan, MoMoConnection, MoMoTransaction, MoMoTransfer
  ```

  Then replace the entire `withdraw` endpoint function:

  **Old function** (lines ~362–394):
  ```python
  @router.patch("/goals/{goal_id}/withdraw", status_code=200)
  async def withdraw(
      goal_id: str,
      current_user: dict = Depends(get_current_user),
      db: AsyncSession = Depends(get_db),
  ):
      res  = await db.execute(
          select(SavingsGoal).where(
              SavingsGoal.id      == goal_id,
              SavingsGoal.user_id == current_user["user_id"],
          ))
      goal = res.scalar_one_or_none()
      if not goal:
          raise HTTPException(status_code=404, detail="Goal not found")
   
      # 10% early withdrawal penalty
      penalty = goal.current * 0.10
      payout  = goal.current - penalty
   
      u_res = await db.execute(
          select(User).where(User.id == current_user["user_id"]))
      user        = u_res.scalar_one()
      user.total_balance += payout
      goal.current        = 0
      goal.is_completed   = False
      goal.is_locked      = True
      await db.flush()
   
      return {
          "message": "Early withdrawal processed",
          "payout":  payout,
          "penalty": penalty,
      }
  ```

  **New function:**
  ```python
  @router.patch("/goals/{goal_id}/withdraw", status_code=200)
  async def withdraw(
      goal_id: str,
      current_user: dict = Depends(get_current_user),
      db: AsyncSession = Depends(get_db),
  ):
      user_id = current_user["user_id"]
      res = await db.execute(
          select(SavingsGoal).where(
              SavingsGoal.id      == goal_id,
              SavingsGoal.user_id == user_id,
          ))
      goal = res.scalar_one_or_none()
      if not goal:
          raise HTTPException(status_code=404, detail="Goal not found")

      conn_res = await db.execute(
          select(MoMoConnection).where(
              MoMoConnection.user_id == user_id,
              MoMoConnection.verified == True,  # noqa: E712
          ))
      conn = conn_res.scalar_one_or_none()
      if not conn:
          raise HTTPException(
              status_code=400,
              detail="Link a verified MoMo wallet before withdrawing.",
          )

      penalty = goal.current * 0.10
      payout  = goal.current - penalty

      external_id = uuid.uuid4().hex[:32]
      try:
          reference = momo_provider.transfer(
              phone=conn.phone,
              amount=int(payout),
              external_id=external_id,
              description="NkapSave savings withdrawal",
          )
      except (momo_provider.MoMoApiError, momo_provider.MoMoNotConfigured) as e:
          raise HTTPException(status_code=400, detail=str(e))

      goal.current      = 0
      goal.is_completed = False
      goal.is_locked    = True
      db.add(MoMoTransfer(
          user_id      = user_id,
          reference_id = reference,
          external_id  = external_id,
          amount       = payout,
          phone        = conn.phone,
          status       = "SUCCESSFUL",
          purpose      = "savings_withdrawal",
          related_id   = str(goal.id),
      ))
      await db.flush()

      return {
          "message":        "Withdrawal processed — funds sent to your MoMo wallet.",
          "payout":         payout,
          "penalty":        penalty,
          "momo_reference": reference,
      }
  ```

- [ ] **Step 4: Run tests — expect PASS**

  ```bash
  cd backend && source venv/bin/activate && python -m pytest tests/test_savings_withdraw.py -v
  ```
  Expected: 3 tests PASSED

- [ ] **Step 5: Commit**

  ```bash
  git add backend/routers/savings.py backend/tests/test_savings_withdraw.py
  git commit -m "feat: savings withdrawal sends real Campay transfer"
  ```

---

### Task 4: Njangi payout — two-phase real transfer + retry endpoint

**Files:**
- Modify: `backend/routers/njangi.py`
- Create: `backend/tests/test_njangi_payout.py`

**Interfaces:**
- Consumes:
  - `momo_provider.transfer(*, phone, amount, external_id, description) -> str` (Task 1)
  - `MoMoTransfer` model (Task 2)
  - `NjangiPayout.payout_status`, `.transfer_reference`, `.recipient_phone` (Task 2)
  - `MoMoConnection` model (already in `models/momo.py`)
- Produces:
  - `_settle_contribution()` no longer credits `r_user.total_balance`; creates `NjangiPayout` with `payout_status="pending_momo"` and returns payout info for the caller to act on.
  - `poll_contribution()` commits Phase 1, then calls Campay, then updates payout status.
  - `POST /njangi/groups/{group_id}/payout/retry` — admin-only retry for `pending_momo` payouts.

- [ ] **Step 1: Write failing tests**

  Create `backend/tests/test_njangi_payout.py`:

  ```python
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
      from models.njangi import GroupStatus

      group = _make_group(contribution=5000.0, current_cycle=1)
      paying_member = _make_member(position=1, trust_score=100.0)
      user = _make_user(total_balance=20000.0)

      # Other members have NOT paid
      other = _make_member(position=2, trust_score=90.0, has_paid=False, user_id="user-uuid-2")
      paying_member.has_paid = False  # will be set True inside _settle_contribution

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
      # all_members query
      members_result = MagicMock()
      members_result.scalars.return_value.all.return_value = [paying_member, other_member]
      # recipient User query
      recipient_user = _make_user(user_id="user-uuid-1", total_balance=5000.0)
      recipient_result = MagicMock()
      recipient_result.scalar_one.return_value = recipient_user
      db.execute = AsyncMock(side_effect=[members_result, recipient_result])
      db.add = MagicMock()
      db.flush = AsyncMock()

      result = await _settle_contribution(db, group, paying_member, user)

      assert result["all_paid"] is True
      assert result["payout_id"] is not None
      # NjangiPayout was added with pending_momo
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

      db = AsyncMock()
      # group query
      group_result = MagicMock()
      group_result.scalar_one_or_none.return_value = _make_group()
      # payout query — no pending
      payout_result = MagicMock()
      payout_result.scalar_one_or_none.return_value = None
      db.execute = AsyncMock(side_effect=[group_result, payout_result])

      current_user = {"user_id": "creator-uuid"}
      group = _make_group()
      group.creator_id = "creator-uuid"

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
      conn_result.scalar_one_or_none.return_value = None  # no MoMo
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
  ```

- [ ] **Step 2: Run tests — expect FAIL**

  ```bash
  cd backend && source venv/bin/activate && python -m pytest tests/test_njangi_payout.py -v
  ```
  Expected: failures on `_settle_contribution` and `retry_njangi_payout` not matching new spec.

- [ ] **Step 3: Refactor `_settle_contribution` in `backend/routers/njangi.py`**

  Also add `import uuid` near the top of `njangi.py` if not present, and add `MoMoTransfer` and `MoMoConnection` to its momo imports:

  Near the top of `njangi.py`, add or update the momo import:
  ```python
  from models.momo import MoMoConnection, MoMoTransfer
  ```
  Also add `import uuid` if not already there.

  Replace the entire `_settle_contribution` function (currently lines ~202–248) with:

  ```python
  async def _settle_contribution(db: AsyncSession, group: NjangiGroup,
                                  member: NjangiMember, user: User) -> dict:
      """Apply the effects of a confirmed (SUCCESSFUL) MoMo contribution.

      Marks the member paid, bumps trust, and — if all members have now paid —
      creates a NjangiPayout with payout_status='pending_momo'. The caller is
      responsible for attempting the actual Campay transfer AFTER committing,
      so no DB lock is held during the HTTP call.
      """
      member.has_paid    = True
      member.trust_score = min(member.trust_score + 2, 100)
      user.total_balance -= group.contribution

      all_members_res = await db.execute(
          select(NjangiMember).where(NjangiMember.group_id == group.id))
      all_members = all_members_res.scalars().all()
      all_paid = all(m.has_paid for m in all_members)

      if not all_paid:
          return {"all_paid": False, "payout_id": None, "net": None, "recipient_user_id": None}

      recipient = next(
          (m for m in all_members if m.position == group.current_cycle), None)
      if not recipient:
          return {"all_paid": True, "payout_id": None, "net": None, "recipient_user_id": None}

      pool   = group.contribution * len(all_members)
      net    = (recipient.trust_score / 100) * pool
      escrow = pool - net

      r_res  = await db.execute(
          select(User).where(User.id == recipient.user_id))
      r_user = r_res.scalar_one()

      payout = NjangiPayout(
          group_id      = group.id,
          recipient_id  = recipient.id,
          cycle         = group.current_cycle,
          gross_amount  = pool,
          net_amount    = net,
          escrow_amount = escrow,
          trust_score   = recipient.trust_score,
          payout_status = "pending_momo",
      )
      db.add(payout)
      recipient.payout_received = True

      for m in all_members:
          m.has_paid = False
      group.current_cycle += 1
      group.cycle_start_date = datetime.now(timezone.utc)
      if group.current_cycle > group.total_cycles:
          from models.njangi import GroupStatus
          group.status = GroupStatus.COMPLETED

      await db.flush()

      return {
          "all_paid":          True,
          "payout_id":         str(payout.id),
          "net":               net,
          "recipient_user_id": str(r_user.id),
      }
  ```

- [ ] **Step 4: Refactor `poll_contribution` in `backend/routers/njangi.py`**

  Replace the block inside the `if momo_status == "SUCCESSFUL":` branch (roughly lines 360–374). The full replacement for that branch:

  ```python
      if momo_status == "SUCCESSFUL":
          # Row-lock the group — the "all paid → payout" check below must
          # serialise against other members confirming concurrently.
          g_res = await db.execute(
              select(NjangiGroup).where(NjangiGroup.id == group_id).with_for_update())
          group = g_res.scalar_one()

          u_res = await db.execute(
              select(User).where(User.id == current_user["user_id"]))
          user = u_res.scalar_one()

          contrib.status = "successful"
          settle = await _settle_contribution(db, group, member, user)
          # Phase 1: commit DB (mark paid, create pending_momo payout) before
          # making the Campay HTTP call — never hold a DB lock across network I/O.
          await db.commit()

          payout_msg = None
          if settle["all_paid"] and settle["payout_id"]:
              payout_msg = await _attempt_njangi_transfer(db, settle)

          return {"status": "successful", "all_paid": settle["all_paid"], "payout_msg": payout_msg}
  ```

- [ ] **Step 5: Add `_attempt_njangi_transfer` helper and `retry_njangi_payout` endpoint**

  Add these two new pieces to `backend/routers/njangi.py`, just before or after `_settle_contribution`:

  ```python
  async def _attempt_njangi_transfer(db: AsyncSession, settle: dict) -> str | None:
      """Attempt the Campay outbound transfer for a pending_momo NjangiPayout.

      Called OUTSIDE any open DB transaction (caller must have committed first).
      Updates payout status in a fresh flush. Returns a user-visible message.
      """
      payout_res = await db.execute(
          select(NjangiPayout).where(NjangiPayout.id == settle["payout_id"]))
      payout = payout_res.scalar_one_or_none()
      if not payout:
          return None

      # Load the recipient member → their user_id → their MoMoConnection
      member_res = await db.execute(
          select(NjangiMember).where(NjangiMember.id == payout.recipient_id))
      recipient_member = member_res.scalar_one_or_none()
      if not recipient_member:
          return f"Payout of {payout.net_amount:,.0f} FCFA pending — recipient not found."

      conn_res = await db.execute(
          select(MoMoConnection).where(
              MoMoConnection.user_id == recipient_member.user_id,
              MoMoConnection.verified == True,  # noqa: E712
          ))
      conn = conn_res.scalar_one_or_none()
      if not conn:
          return (
              f"Payout of {payout.net_amount:,.0f} FCFA pending — "
              "recipient must link a verified MoMo wallet."
          )

      external_id = uuid.uuid4().hex[:32]
      try:
          reference = momo_provider.transfer(
              phone=conn.phone,
              amount=int(payout.net_amount),
              external_id=external_id,
              description=f"Njangi payout cycle {payout.cycle}",
          )
      except (momo_provider.MoMoApiError, momo_provider.MoMoNotConfigured) as e:
          logger.error("njangi payout transfer failed payout=%s: %s", payout.id, e)
          return f"Payout of {payout.net_amount:,.0f} FCFA pending — transfer failed: {e}"

      payout.payout_status      = "completed"
      payout.transfer_reference = reference
      payout.recipient_phone    = conn.phone
      db.add(MoMoTransfer(
          user_id      = str(recipient_member.user_id),
          reference_id = reference,
          external_id  = external_id,
          amount       = payout.net_amount,
          phone        = conn.phone,
          status       = "SUCCESSFUL",
          purpose      = "njangi_payout",
          related_id   = str(payout.id),
      ))
      await db.flush()
      return f"Payout of {payout.net_amount:,.0f} FCFA sent!"
  ```

  Then add the retry endpoint (add anywhere after `poll_contribution`):

  ```python
  @router.post("/groups/{group_id}/payout/retry", status_code=200)
  async def retry_njangi_payout(
      group_id: str,
      current_user: dict = Depends(get_current_user),
      db: AsyncSession = Depends(get_db),
  ):
      """Retry a pending_momo Njangi payout. Admin (group creator) only.

      Use this when the automatic transfer failed because the recipient had
      no linked MoMo wallet or Campay was temporarily unavailable.
      """
      g_res = await db.execute(
          select(NjangiGroup).where(NjangiGroup.id == group_id))
      group = g_res.scalar_one_or_none()
      if not group or str(group.creator_id) != current_user["user_id"]:
          raise HTTPException(status_code=403, detail="Admin only")

      p_res = await db.execute(
          select(NjangiPayout).where(
              NjangiPayout.group_id     == group_id,
              NjangiPayout.payout_status == "pending_momo",
          ).order_by(NjangiPayout.created_at.desc()))
      payout = p_res.scalar_one_or_none()
      if not payout:
          raise HTTPException(status_code=404, detail="No pending payout for this group")

      member_res = await db.execute(
          select(NjangiMember).where(NjangiMember.id == payout.recipient_id))
      recipient_member = member_res.scalar_one_or_none()
      if not recipient_member:
          raise HTTPException(status_code=404, detail="Recipient member not found")

      conn_res = await db.execute(
          select(MoMoConnection).where(
              MoMoConnection.user_id == recipient_member.user_id,
              MoMoConnection.verified == True,  # noqa: E712
          ))
      conn = conn_res.scalar_one_or_none()
      if not conn:
          raise HTTPException(
              status_code=400,
              detail="Recipient has not linked a verified MoMo wallet.",
          )

      external_id = uuid.uuid4().hex[:32]
      try:
          reference = momo_provider.transfer(
              phone=conn.phone,
              amount=int(payout.net_amount),
              external_id=external_id,
              description=f"Njangi payout cycle {payout.cycle}",
          )
      except (momo_provider.MoMoApiError, momo_provider.MoMoNotConfigured) as e:
          raise HTTPException(status_code=400, detail=str(e))

      payout.payout_status      = "completed"
      payout.transfer_reference = reference
      payout.recipient_phone    = conn.phone
      db.add(MoMoTransfer(
          user_id      = str(recipient_member.user_id),
          reference_id = reference,
          external_id  = external_id,
          amount       = payout.net_amount,
          phone        = conn.phone,
          status       = "SUCCESSFUL",
          purpose      = "njangi_payout",
          related_id   = str(payout.id),
      ))
      await db.flush()

      return {
          "status":         "completed",
          "momo_reference": reference,
          "amount":         payout.net_amount,
          "message":        f"Payout of {payout.net_amount:,.0f} FCFA sent successfully.",
      }
  ```

- [ ] **Step 6: Add `import uuid` and momo model imports to `njangi.py`**

  Ensure the top of `backend/routers/njangi.py` has:
  ```python
  import uuid
  from models.momo import MoMoConnection, MoMoTransfer
  ```
  (Add next to the existing `from services import momo_provider` line.)

- [ ] **Step 7: Run all tests — expect PASS**

  ```bash
  cd backend && source venv/bin/activate && python -m pytest tests/ -v
  ```
  Expected: all tests in `test_momo_provider.py`, `test_savings_withdraw.py`, `test_njangi_payout.py` PASS.

- [ ] **Step 8: Verify import correctness**

  ```bash
  cd backend && source venv/bin/activate && python -c "from routers import njangi, savings; print('imports OK')"
  ```
  Expected: `imports OK`

- [ ] **Step 9: Commit**

  ```bash
  git add backend/routers/njangi.py backend/tests/test_njangi_payout.py
  git commit -m "feat: Njangi payout sends real Campay transfer with retry endpoint"
  ```

---

## Self-Review

**Spec coverage:**
- ✅ `momo_provider.transfer()` — Task 1
- ✅ `MoMoTransfer` model — Task 2
- ✅ `NjangiPayout` 3 new columns — Task 2
- ✅ Migration functions registered in `run_dev_migrations` — Task 2
- ✅ Savings withdrawal: verified MoMo required, transfer inline, goal unchanged on failure — Task 3
- ✅ Savings withdrawal: `user.total_balance` not touched — Task 3
- ✅ Njangi: two-phase (commit before HTTP call) — Task 4
- ✅ Njangi: `r_user.total_balance` not touched — Task 4 (`_settle_contribution` refactor)
- ✅ Retry endpoint admin-only — Task 4
- ✅ No HTTP call inside DB transaction — Tasks 3 and 4 both honour this

**Placeholder scan:** No TBD/TODO/similar to task N patterns. All code blocks complete.

**Type consistency:**
- `payout.net_amount` used in Task 4 matches `NjangiPayout.net_amount` column defined in Task 2. ✅
- `payout.payout_status` used in Task 4 matches column added in Task 2. ✅
- `momo_provider.transfer(phone, amount, external_id, description)` signature consistent across Tasks 1, 3, 4. ✅
- `MoMoTransfer` constructor args match model columns in Task 2. ✅
