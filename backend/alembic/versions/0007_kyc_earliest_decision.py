"""kyc: minimum-review-time gate

Revision ID: 0007_kyc_earliest_decision
Revises: 0006_njangi_payouts
Create Date: 2026-05-28

Adds `identity_verifications.earliest_decision_at` so the backend can
reject approve/reject calls that come in faster than the configured
review-minimum (5 minutes today). Nullable column — existing rows
keep NULL and bypass the gate so we don't retroactively block
already-pending submissions.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0007_kyc_earliest_decision"
down_revision: Union[str, None] = "0006_njangi_payouts"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "identity_verifications",
        sa.Column(
            "earliest_decision_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column("identity_verifications", "earliest_decision_at")
