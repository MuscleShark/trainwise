"""Exercise aliases: other names the app's search matches ("RDL", "卧推").

The built-in ones are filled in by the catalog sync that runs after migrations.

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-25
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("exercises", sa.Column("aliases", sa.JSON(), server_default="[]", nullable=False))


def downgrade() -> None:
    op.drop_column("exercises", "aliases")
