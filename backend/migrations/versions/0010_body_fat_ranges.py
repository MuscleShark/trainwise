"""Body fat estimates: the range a user picked instead of a measured value.

Revision ID: 0010
Revises: 0009
Create Date: 2026-11-01
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("body_measurements", sa.Column("value_low", sa.Numeric(8, 3), nullable=True))
    op.add_column("body_measurements", sa.Column("value_high", sa.Numeric(8, 3), nullable=True))


def downgrade() -> None:
    op.drop_column("body_measurements", "value_high")
    op.drop_column("body_measurements", "value_low")
