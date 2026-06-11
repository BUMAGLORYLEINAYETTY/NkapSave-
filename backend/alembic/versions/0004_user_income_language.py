"""user income_bracket + preferred_language

Revision ID: 0004_user_income_language
Revises: 0003_auto_save_reminder_tracking
Create Date: 2026-05-20

Adds two nullable personalisation fields to `users` so NkapBot can:
  * compute the user's savings rate against a discrete income bucket
  * reply in the user's preferred language (en/fr/pidgin)

Both are nullable — existing accounts keep working and the bot falls back
to safe defaults (no rate calc, English) until the user picks values.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0004_user_income_language"
down_revision: Union[str, None] = "0003_auto_save_reminder_tracking"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("income_bracket", sa.String(length=20), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column(
            "preferred_language",
            sa.String(length=10),
            nullable=True,
            server_default=sa.text("'en'"),
        ),
    )


def downgrade() -> None:
    op.drop_column("users", "preferred_language")
    op.drop_column("users", "income_bracket")
