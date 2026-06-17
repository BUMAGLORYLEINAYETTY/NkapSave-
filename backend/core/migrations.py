"""Lightweight idempotent schema migrations for development.

`Base.metadata.create_all` only creates missing tables — it never alters
existing columns or drops legacy constraints. This module runs after
`create_all` to bring an old database forward to the current model.

Each function is idempotent: safe to call on a fresh DB *or* one that
already has the new shape. Functions log when they actually do work.

This is dev-grade. For production you'd write proper Alembic revisions.
"""
from __future__ import annotations

import logging

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine

logger = logging.getLogger("nkapsave.migrations")


async def migrate_expenses_to_unified(engine: AsyncEngine) -> None:
    """Bring `expenses` table from legacy → unified schema.

    Legacy:
      * `category` is a Postgres ENUM type with 9 values
      * `amount` is stored negative for expenses
      * No `txn_type`, `payment_method`, `location`, `txn_date`

    New:
      * `category` is varchar(40)
      * `amount` is always positive; `txn_type` is 'EXPENSE' or 'INCOME'
      * Extra columns present
      * Old "Housing" rows are remapped to "Rent"
    """
    async with engine.begin() as conn:
        # 1) Make sure the columns we want exist. Idempotent: ADD COLUMN IF NOT EXISTS.
        for sql in [
            "ALTER TABLE expenses ADD COLUMN IF NOT EXISTS txn_type VARCHAR(10) NOT NULL DEFAULT 'EXPENSE'",
            "ALTER TABLE expenses ADD COLUMN IF NOT EXISTS payment_method VARCHAR(30)",
            "ALTER TABLE expenses ADD COLUMN IF NOT EXISTS location VARCHAR(120)",
            "ALTER TABLE expenses ADD COLUMN IF NOT EXISTS txn_date TIMESTAMPTZ",
        ]:
            await conn.execute(text(sql))

        # 2) If `category` is still a Postgres enum, alter it to varchar.
        category_type = await conn.scalar(text(
            "SELECT data_type FROM information_schema.columns "
            "WHERE table_name='expenses' AND column_name='category'"
        ))
        if category_type and category_type.lower() not in ("character varying", "text"):
            logger.info("Converting expenses.category from %s to varchar(40)", category_type)
            await conn.execute(text(
                "ALTER TABLE expenses ALTER COLUMN category TYPE VARCHAR(40) "
                "USING category::text"
            ))
            # Drop the now-orphaned enum type if it exists.
            await conn.execute(text(
                "DROP TYPE IF EXISTS expensecategory"
            ))

        # 3) Remap legacy "Housing" rows to "Rent".
        await conn.execute(text(
            "UPDATE expenses SET category='Rent' WHERE category='Housing'"
        ))

        # 4) Flip stored amounts to positive (legacy stored expenses as negative).
        #    Any row with a negative amount becomes positive + EXPENSE type.
        #    We do this in two steps so the type flag is correct first, then
        #    the absolute value is taken.
        await conn.execute(text(
            "UPDATE expenses SET txn_type='EXPENSE' "
            "WHERE amount < 0 AND (txn_type IS NULL OR txn_type='EXPENSE')"
        ))
        flipped = await conn.execute(text(
            "UPDATE expenses SET amount=ABS(amount) WHERE amount < 0"
        ))
        if flipped.rowcount:
            logger.info("Flipped %s legacy negative expense rows to positive", flipped.rowcount)


async def add_user_kyc_reviewer_column(engine: AsyncEngine) -> None:
    """Add `users.is_kyc_reviewer` if missing. `create_all` only creates
    new tables, never alters existing columns — so old databases need
    this nudge before the KYC admin endpoints can read it."""
    async with engine.begin() as conn:
        await conn.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS "
            "is_kyc_reviewer BOOLEAN NOT NULL DEFAULT FALSE"
        ))


async def add_njangi_contribution_payment_columns(engine: AsyncEngine) -> None:
    """Add MoMo payment-tracking columns to `njangi_contributions`.

    Existing rows default to status='successful' — they were only ever
    inserted at the moment a contribution was recorded as paid, before
    real MoMo confirmation existed."""
    async with engine.begin() as conn:
        for sql in [
            "ALTER TABLE njangi_contributions ADD COLUMN IF NOT EXISTS "
            "status VARCHAR(20) NOT NULL DEFAULT 'successful'",
            "ALTER TABLE njangi_contributions ADD COLUMN IF NOT EXISTS "
            "momo_reference VARCHAR(64)",
            "ALTER TABLE njangi_contributions ADD COLUMN IF NOT EXISTS "
            "phone VARCHAR(20)",
        ]:
            await conn.execute(text(sql))


async def backfill_njangi_creator_admin(engine: AsyncEngine) -> None:
    """Mark each group's creator as `is_admin` on their member row.

    `create_group` now sets `is_admin=True` for new groups, but groups
    created before that change left their creator's membership row with
    `is_admin=False` or NULL. Backfill those so the "Admin" badge shows up.

    The ADD COLUMN step is defensive: if the table pre-dates the column,
    `create_all` won't add it — this ensures it exists before the UPDATE."""
    async with engine.begin() as conn:
        # Ensure the column exists on old databases that pre-date the model.
        await conn.execute(text(
            "ALTER TABLE njangi_members "
            "ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE"
        ))
        # Handle both FALSE and NULL (NULL can appear when the column was added
        # via ADD COLUMN DEFAULT FALSE after rows already existed in older DBs).
        result = await conn.execute(text(
            "UPDATE njangi_members m SET is_admin = TRUE "
            "FROM njangi_groups g "
            "WHERE m.group_id = g.id AND m.user_id = g.creator_id "
            "AND (m.is_admin = FALSE OR m.is_admin IS NULL)"
        ))
        if result.rowcount:
            logger.info("Backfilled is_admin for %s njangi group creators", result.rowcount)


async def add_email_verification_columns(engine: AsyncEngine) -> None:
    """Add email_verified / email_verify_token to users.

    Existing accounts are backfilled with email_verified=TRUE so they are
    not locked out after the migration — only new registrations go through
    the verify-email flow going forward.
    """
    async with engine.begin() as conn:
        await conn.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS "
            "email_verified BOOLEAN NOT NULL DEFAULT FALSE"
        ))
        await conn.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS "
            "email_verify_token VARCHAR(64)"
        ))
        result = await conn.execute(text(
            "UPDATE users SET email_verified = TRUE "
            "WHERE email_verified = FALSE AND email_verify_token IS NULL"
        ))
        if result.rowcount:
            logger.info(
                "Backfilled email_verified=TRUE for %s existing users",
                result.rowcount,
            )


async def run_dev_migrations(engine: AsyncEngine) -> None:
    """Run every idempotent dev migration in order."""
    try:
        await migrate_expenses_to_unified(engine)
        await add_user_kyc_reviewer_column(engine)
        await add_njangi_contribution_payment_columns(engine)
        await backfill_njangi_creator_admin(engine)
        await add_email_verification_columns(engine)
    except Exception as e:  # pragma: no cover — dev only
        logger.exception("Dev migration failed: %s", e)
        raise
