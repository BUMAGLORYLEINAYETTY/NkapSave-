"""initial schema

Revision ID: 0001_initial
Revises:
Create Date: 2026-05-09

Creates the full NkapSave schema as it stands today, including:
  * cascade ON DELETE on all user/group foreign keys
  * unique constraint on (group_id, user_id) in njangi_members
  * push_tokens + notifications tables for FCM
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "0001_initial"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("full_name", sa.String(100), nullable=False),
        sa.Column("email", sa.String(150), nullable=False),
        sa.Column("phone", sa.String(20), nullable=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("pin_hash", sa.String(255), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("is_verified", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("total_balance", sa.Float(), server_default=sa.text("0")),
        sa.Column("trust_score", sa.Float(), server_default=sa.text("100")),
        sa.Column("auto_save_pct", sa.Integer(), server_default=sa.text("10")),
        sa.Column("auto_save_on", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("profile_picture", sa.String(500), nullable=True),
        sa.Column("bio", sa.String(300), nullable=True),
        sa.Column("location", sa.String(100), nullable=True),
        sa.Column("occupation", sa.String(100), nullable=True),
        sa.Column("date_of_birth", sa.String(20), nullable=True),
        sa.Column("city", sa.String(100), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True)),
        sa.UniqueConstraint("email"),
        sa.UniqueConstraint("phone"),
    )
    op.create_index("ix_users_email", "users", ["email"])

    op.create_table(
        "expenses",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(150), nullable=False),
        sa.Column("category",
                  sa.Enum("Food", "Transport", "Utilities", "Shopping", "Housing",
                          "Health", "Njangi", "Savings", "Other",
                          name="expensecategory"),
                  nullable=False),
        sa.Column("amount", sa.Float(), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("source", sa.String(50), server_default="manual"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_expenses_user_id", "expenses", ["user_id"])
    op.create_index("ix_expenses_created_at", "expenses", ["created_at"])

    op.create_table(
        "savings_goals",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("emoji", sa.String(10), server_default="🎯"),
        sa.Column("target", sa.Float(), nullable=False),
        sa.Column("current", sa.Float(), server_default=sa.text("0")),
        sa.Column("is_locked", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("is_completed", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True)),
    )
    op.create_index("ix_savings_goals_user_id", "savings_goals", ["user_id"])

    op.create_table(
        "transactions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(150), nullable=False),
        sa.Column("category",
                  sa.Enum("Income", "Food & Drink", "Transport", "Utilities", "Shopping",
                          "Housing", "Health", "Njangi", "Savings", "Other",
                          name="txcategory"),
                  nullable=False),
        sa.Column("amount", sa.Float(), nullable=False),
        sa.Column("note", sa.String(300), nullable=True),
        sa.Column("source", sa.String(50), server_default="manual"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_transactions_user_id", "transactions", ["user_id"])
    op.create_index("ix_transactions_created_at", "transactions", ["created_at"])

    op.create_table(
        "njangi_groups",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("description", sa.String(500), nullable=True),
        sa.Column("invite_code", sa.String(6), nullable=False),
        sa.Column("creator_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("contribution", sa.Float(), nullable=False),
        sa.Column("frequency", sa.String(20), server_default="Monthly"),
        sa.Column("max_members", sa.Integer(), server_default=sa.text("10")),
        sa.Column("current_cycle", sa.Integer(), server_default=sa.text("1")),
        sa.Column("total_cycles", sa.Integer(), server_default=sa.text("1")),
        sa.Column("status",
                  sa.Enum("pending", "active", "completed", name="groupstatus"),
                  server_default="pending"),
        sa.Column("escrow_balance", sa.Float(), server_default=sa.text("0")),
        sa.Column("cycle_start_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("start_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("invite_code"),
    )
    op.create_index("ix_njangi_groups_invite_code", "njangi_groups", ["invite_code"])
    op.create_index("ix_njangi_groups_creator_id", "njangi_groups", ["creator_id"])

    op.create_table(
        "njangi_members",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("group_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("njangi_groups.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("trust_score", sa.Float(), server_default=sa.text("100")),
        sa.Column("has_paid", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("payout_received", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("is_admin", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("joined_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("group_id", "user_id", name="uq_njangi_member_group_user"),
    )
    op.create_index("ix_njangi_members_group_id", "njangi_members", ["group_id"])
    op.create_index("ix_njangi_members_user_id", "njangi_members", ["user_id"])
    op.create_index("ix_njangi_members_user_group", "njangi_members", ["user_id", "group_id"])

    op.create_table(
        "njangi_contributions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("group_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("njangi_groups.id", ondelete="CASCADE"), nullable=False),
        sa.Column("member_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("njangi_members.id", ondelete="CASCADE"), nullable=False),
        sa.Column("amount", sa.Float(), nullable=False),
        sa.Column("cycle", sa.Integer(), nullable=False),
        sa.Column("provider", sa.String(30), server_default="MTN Money"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_njangi_contributions_group_id", "njangi_contributions", ["group_id"])
    op.create_index("ix_njangi_contributions_member_id", "njangi_contributions", ["member_id"])

    op.create_table(
        "reminder_logs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("group_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("njangi_groups.id", ondelete="CASCADE"), nullable=False),
        sa.Column("cycle", sa.Integer(), nullable=False),
        sa.Column("channel", sa.String(20), nullable=False),
        sa.Column("message", sa.String(500), nullable=False),
        sa.Column("delivered", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("sent_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_reminder_logs_user_id", "reminder_logs", ["user_id"])
    op.create_index("ix_reminder_logs_group_id", "reminder_logs", ["group_id"])

    op.create_table(
        "push_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token", sa.String(512), nullable=False),
        sa.Column("platform", sa.String(20), nullable=False),
        sa.Column("device_id", sa.String(120), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True)),
        sa.UniqueConstraint("token", name="uq_push_tokens_token"),
    )
    op.create_index("ix_push_tokens_user_id", "push_tokens", ["user_id"])
    op.create_index("ix_push_tokens_user_active", "push_tokens", ["user_id", "is_active"])

    op.create_table(
        "notifications",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("title", sa.String(150), nullable=False),
        sa.Column("body", sa.String(500), nullable=False),
        sa.Column("category", sa.String(40), nullable=False, server_default="general"),
        sa.Column("deep_link", sa.String(300), nullable=True),
        sa.Column("read", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("push_sent", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("push_error", sa.String(300), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_notifications_user_id", "notifications", ["user_id"])
    op.create_index("ix_notifications_user_created", "notifications",
                    ["user_id", "created_at"])


def downgrade() -> None:
    op.drop_table("notifications")
    op.drop_table("push_tokens")
    op.drop_table("reminder_logs")
    op.drop_table("njangi_contributions")
    op.drop_table("njangi_members")
    op.drop_table("njangi_groups")
    op.drop_table("transactions")
    op.drop_table("savings_goals")
    op.drop_table("expenses")
    op.drop_table("users")
    sa.Enum(name="groupstatus").drop(op.get_bind(), checkfirst=True)
    sa.Enum(name="txcategory").drop(op.get_bind(), checkfirst=True)
    sa.Enum(name="expensecategory").drop(op.get_bind(), checkfirst=True)
