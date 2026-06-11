"""njangi: add PAUSED to groupstatus enum

Revision ID: 0005_njangi_paused_status
Revises: 0004_user_income_language
Create Date: 2026-05-22

Adds a 'paused' value to the existing groupstatus enum so admins can halt
cycles without deleting the group (used by the new top-right "More" menu
in the group dashboard). Downgrade is destructive — any rows currently in
the 'paused' state are flipped to 'active' first so the ALTER TYPE can
proceed without orphaning data.
"""
from typing import Sequence, Union

from alembic import op


revision: str = "0005_njangi_paused_status"
down_revision: Union[str, None] = "0004_user_income_language"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Postgres requires ADD VALUE to run outside a wrapping transaction.
    # Alembic's default env opens one; commit it before issuing ALTER TYPE.
    connection = op.get_bind()
    connection.exec_driver_sql("COMMIT")
    connection.exec_driver_sql(
        "ALTER TYPE groupstatus ADD VALUE IF NOT EXISTS 'paused'"
    )


def downgrade() -> None:
    # Postgres cannot DROP a value from an enum. The safe path is to
    # rebuild the type without 'paused', after rewriting any rows.
    op.execute("UPDATE njangi_groups SET status = 'active' WHERE status = 'paused'")
    op.execute("ALTER TYPE groupstatus RENAME TO groupstatus_old")
    op.execute(
        "CREATE TYPE groupstatus AS ENUM ('pending', 'active', 'completed')"
    )
    op.execute(
        "ALTER TABLE njangi_groups "
        "ALTER COLUMN status TYPE groupstatus "
        "USING status::text::groupstatus"
    )
    op.execute("DROP TYPE groupstatus_old")
