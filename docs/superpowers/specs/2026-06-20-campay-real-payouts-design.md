# Design: Real Campay Payouts for Savings Withdrawal & Njangi

**Date:** 2026-06-20  
**Status:** Approved  
**Scope:** Backend only — no Flutter changes required for the transfer logic itself.

## Problem

Money flows IN via Campay `collect/` (real XAF moves from user MoMo → merchant wallet).  
Money flows OUT via DB-only number changes — no real Campay call. The merchant wallet accumulates funds indefinitely.

Two surfaces need real outbound transfers:
1. **Savings goal withdrawal** — user pulls money out of a locked goal
2. **Njangi cycle payout** — when all members have contributed, the pool is sent to the cycle recipient

## Decisions

| Question | Answer |
|---|---|
| Transfer failure handling | Block & retry — show error, leave state as `pending_momo`, user/admin retries |
| Njangi payout destination | Recipient's verified `MoMoConnection` in NkapSave |
| Savings withdrawal destination | User's verified `MoMoConnection` in NkapSave |
| Early withdrawal penalty | 10% stays in Campay merchant wallet (existing rule, now enforced in real XAF) |

## Critical Safety Rule

**Never make an HTTP call to Campay inside an open DB transaction.**  
MTN/Orange transfers can take 30–60 seconds. Holding a DB lock for that duration risks connection timeouts and deadlocks. All flows follow the pattern:

```
1. Commit DB intent (pending state)
2. Call Campay (outside transaction)
3. Update DB result (new transaction)
```

## Files Changed

| File | Change |
|---|---|
| `backend/services/momo_provider.py` | Add `transfer()` function |
| `backend/models/momo.py` | Add `MoMoTransfer` model |
| `backend/models/njangi.py` | Add 3 columns to `NjangiPayout` |
| `backend/routers/savings.py` | Refactor `withdraw` endpoint |
| `backend/routers/njangi.py` | Refactor `_settle_contribution` + poll endpoint; add retry endpoint |
| `backend/core/migrations.py` | Migrate new columns and new table |

## Component Designs

### 1. `momo_provider.transfer()`

New function alongside `request_to_pay()`. Symmetric outbound counterpart.

```
POST {base_url}/transfer/
Body: {
  "amount": str(int(amount)),
  "to": _msisdn(phone),
  "description": description[:160],
  "external_reference": external_id
}
Returns: reference string (str)
Raises: MoMoApiError on HTTP 4xx/5xx or missing reference in response
```

Uses same `_auth_headers()`, `_msisdn()`, `_require_creds()`, and `_base_url()` as the existing collect path. No new error types needed.

### 2. `MoMoTransfer` model (new table: `momo_transfers`)

Outbound audit log — the "send" counterpart to `MoMoTransaction` (which logs inbound collects).

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK → users | The user receiving the transfer |
| `reference_id` | String(64) unique | Campay reference returned by `/transfer/` |
| `external_id` | String(64) | Our UUID we sent as external_reference |
| `amount` | Float | XAF amount sent |
| `currency` | String(8) | Default "XAF" |
| `phone` | String(20) | Destination MSISDN |
| `status` | String(20) | SUCCESSFUL \| FAILED |
| `reason` | Text nullable | Failure reason if any |
| `purpose` | String(30) | `savings_withdrawal` \| `njangi_payout` |
| `related_id` | String(64) nullable | goal_id for savings; payout_id for njangi |
| `initiated_at` | DateTime(tz) | server_default=now() |
| `completed_at` | DateTime(tz) nullable | Set when status resolves |

### 3. `NjangiPayout` — new columns

| Column | Type | Default | Notes |
|---|---|---|---|
| `payout_status` | String(30) | `completed` | `pending_momo` \| `completed` \| `failed`. Default `completed` preserves existing rows. |
| `transfer_reference` | String(64) | NULL | Campay reference for outbound transfer |
| `recipient_phone` | String(20) | NULL | Phone the transfer was sent to |

### 4. Savings Withdrawal — refactored `PATCH /savings/goals/{goal_id}/withdraw`

**Current behaviour (broken):** Credits `user.total_balance`, zeros goal. No real money movement.

**New behaviour:**

```
1. Load goal (owner check)
2. Load user's MoMoConnection where verified=True
   → HTTP 400 "Link a verified MoMo wallet to withdraw" if none
3. payout  = goal.current * 0.90
   penalty = goal.current * 0.10
4. Call momo_provider.transfer(
       phone=conn.phone, amount=int(payout),
       external_id=uuid.uuid4().hex[:32],
       description="NkapSave savings withdrawal"
   )
   → On MoMoApiError: return HTTP 400 with Campay's message. Goal is UNCHANGED.
5. On success:
   - goal.current = 0, goal.is_completed = False, goal.is_locked = True
   - INSERT MoMoTransfer(purpose="savings_withdrawal", related_id=goal.id, status="SUCCESSFUL", ...)
   - DO NOT touch user.total_balance (money went to real MoMo, not virtual balance)
6. Commit. Return {payout, penalty, momo_reference, message}.
```

**Removed:** `user.total_balance += payout` — this was a virtual-model hack that is no longer correct once real money flows out via Campay.

### 5. Njangi Payout — refactored `_settle_contribution` + poll endpoint

**Current behaviour (broken):** `r_user.total_balance += net` when all members paid. No real transfer.

**New behaviour — two-phase:**

**Phase 1 — inside the existing DB transaction in `_settle_contribution`:**
```
When all_paid:
  - Compute pool, net, escrow as before
  - INSERT NjangiPayout with payout_status="pending_momo", recipient_phone=NULL
  - DO NOT credit r_user.total_balance
  - DO NOT call Campay
  - Return {"all_paid": True, "payout_id": str(payout.id), "net": net, "recipient_user_id": ...}
```

**Phase 2 — in the poll endpoint, AFTER the DB commit:**
```
If settle result contains payout_id:
  - Load recipient's MoMoConnection (verified=True)
  - If no wallet:
      → payout_status stays "pending_momo"
      → payout_msg = "Payout pending — recipient must link a verified MoMo wallet"
  - If wallet found:
      → Call momo_provider.transfer(phone=conn.phone, amount=int(payout.net_amount), ...)
      → If success: UPDATE payout SET payout_status="completed", transfer_reference=ref, recipient_phone=phone
      → If fail: payout_status stays "pending_momo"; payout_msg = Campay error
  - Commit payout status update
```

**Removed:** `r_user.total_balance += net` — same rationale as savings withdrawal.

### 6. Retry Endpoint — `POST /njangi/groups/{group_id}/payout/retry`

- Requires current user to be the group admin (creator)
- Finds the latest `NjangiPayout` for the group where `payout_status="pending_momo"`
- 404 if none pending
- Loads recipient's `MoMoConnection` (verified) — 400 if still not linked
- Calls `momo_provider.transfer()`
- Updates payout status in DB
- Returns `{status, momo_reference, message}`

### 7. Migration (`backend/core/migrations.py`)

Two idempotent DDL operations appended to `run_dev_migrations`:

```sql
-- 1. New columns on njangi_payouts
ALTER TABLE njangi_payouts
  ADD COLUMN IF NOT EXISTS payout_status VARCHAR(30) DEFAULT 'completed',
  ADD COLUMN IF NOT EXISTS transfer_reference VARCHAR(64),
  ADD COLUMN IF NOT EXISTS recipient_phone VARCHAR(20);

-- 2. New momo_transfers table
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
);
```

## Error Handling Summary

| Scenario | Behaviour |
|---|---|
| User has no verified MoMo wallet | HTTP 400 before any Campay call |
| Campay credentials not configured | `MoMoNotConfigured` → HTTP 400 "MoMo payments not configured" |
| Campay rejects transfer (4xx) | HTTP 400 with Campay's message; no DB state change for withdrawal; `pending_momo` for njangi |
| Network error to Campay | Same as rejection |
| DB commit fails after successful transfer | Goal/payout still shows old state; Campay transfer already happened. Risk accepted for v1. User contacts support with the Campay reference returned in the response. |

## What Is NOT Changed

- `add_funds` endpoint and `user.total_balance` deduction — unrelated manual flow
- Auto-save `_credit_goal` logic — inbound, unaffected
- Njangi contribution deduction from `user.total_balance` — separate concern, out of scope
- KYC gate (`_require_verified`) — already in place
- Any Flutter code — the API response shape is extended (new fields), not changed
