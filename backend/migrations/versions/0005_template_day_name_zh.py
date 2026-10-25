"""Chinese names for the days of built-in templates.

The templates themselves are filled in by the template sync that runs after migrations.

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-25
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("template_days", sa.Column("name_zh", sa.String(length=120), nullable=True))


def downgrade() -> None:
    op.drop_column("template_days", "name_zh")
