"""auto-save reminder tracking

Revision ID: 0003_auto_save_reminder_tracking
Revises: 0002_goal_deadline_plan_reminder
Create Date: 2026-05-20

Adds `last_reminder_for_run_at` to `auto_save_plans`. Used by the reminder
scheduler to avoid sending the same pre-deduction notification twice for
the same `next_run_at` value.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0003_auto_save_reminder_tracking"
down_revision: Union[str, None] = "0002_goal_deadline_plan_reminder"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "auto_save_plans",
        sa.Column(
            "last_reminder_for_run_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column("auto_save_plans", "last_reminder_for_run_at")
