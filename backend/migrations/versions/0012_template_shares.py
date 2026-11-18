"""Template shares: a link that lets anyone copy one of a user's templates.

Revision ID: 0012
Revises: 0011
Create Date: 2026-11-17
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "template_shares",
        sa.Column("code", sa.String(16), primary_key=True),
        sa.Column(
            "template_id",
            sa.Uuid(),
            sa.ForeignKey("templates.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("owner_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("snapshot", sa.JSON(), nullable=False),
        sa.Column("copy_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("shared_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(op.f("ix_template_shares_owner_user_id"), "template_shares", ["owner_user_id"])


def downgrade() -> None:
    op.drop_index(op.f("ix_template_shares_owner_user_id"), table_name="template_shares")
    op.drop_table("template_shares")
