"""goal deadline + plan reminder

Revision ID: 0002_goal_deadline_plan_reminder
Revises: 0001_initial
Create Date: 2026-05-20

Adds:
  * savings_goals.deadline (nullable DateTime) — the user's target date for
    hitting the goal. Powers the wizard's smart projection.
  * auto_save_plans.reminder_enabled (Boolean, default TRUE) — whether to
    push a notification ~24h before the next scheduled deduction.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0002_goal_deadline_plan_reminder"
down_revision: Union[str, None] = "0001_initial"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "savings_goals",
        sa.Column("deadline", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "auto_save_plans",
        sa.Column(
            "reminder_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
    )


def downgrade() -> None:
    op.drop_column("auto_save_plans", "reminder_enabled")
    op.drop_column("savings_goals", "deadline")
