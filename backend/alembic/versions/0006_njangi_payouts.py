"""njangi: payout history table

Revision ID: 0006_njangi_payouts
Revises: 0005_njangi_paused_status
Create Date: 2026-05-22

Adds `njangi_payouts` so the dashboard can show every past payout for a
group (cycle, recipient, gross/net/escrow amounts). Existing groups won't
have rows here for past cycles — those payouts pre-date the table — but
every payout from this migration forward is recorded as it happens.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


revision: str = "0006_njangi_payouts"
down_revision: Union[str, None] = "0005_njangi_paused_status"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "njangi_payouts",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("group_id", UUID(as_uuid=True),
                  sa.ForeignKey("njangi_groups.id", ondelete="CASCADE"),
                  nullable=False),
        sa.Column("recipient_id", UUID(as_uuid=True),
                  sa.ForeignKey("njangi_members.id", ondelete="CASCADE"),
                  nullable=False),
        sa.Column("cycle", sa.Integer, nullable=False),
        sa.Column("gross_amount", sa.Float, nullable=False),
        sa.Column("net_amount", sa.Float, nullable=False),
        sa.Column("escrow_amount", sa.Float, server_default="0"),
        sa.Column("trust_score", sa.Float, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now()),
    )
    op.create_index("ix_njangi_payouts_group_id",
                    "njangi_payouts", ["group_id"])
    op.create_index("ix_njangi_payouts_recipient_id",
                    "njangi_payouts", ["recipient_id"])


def downgrade() -> None:
    op.drop_index("ix_njangi_payouts_recipient_id",
                  table_name="njangi_payouts")
    op.drop_index("ix_njangi_payouts_group_id",
                  table_name="njangi_payouts")
    op.drop_table("njangi_payouts")
