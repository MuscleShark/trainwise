"""Built-in templates each user hid from their list.

Revision ID: 0009
Revises: 0008
Create Date: 2026-10-28
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "profiles",
        sa.Column("hidden_template_ids", sa.JSON(), server_default="[]", nullable=False),
    )


def downgrade() -> None:
    op.drop_column("profiles", "hidden_template_ids")
