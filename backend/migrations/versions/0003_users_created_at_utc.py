"""Store users.created_at with a time zone, like every other timestamp.

The column predates Clerk and held naive UTC values, so the API returned it without an
offset (`2026-10-25T00:43:41.279616`), which the iPhone app rejects as a date-time.
Existing values are UTC (they came from datetime.utcnow), so they keep their instant.

Code still running the old model during a deploy writes naive UTC values; PostgreSQL
reads those in the session time zone, which is UTC on Neon.

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-25
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("users") as batch:
        batch.alter_column(
            "created_at",
            type_=sa.DateTime(timezone=True),
            existing_type=sa.DateTime(),
            existing_nullable=False,
            postgresql_using="created_at AT TIME ZONE 'UTC'",
        )


def downgrade() -> None:
    with op.batch_alter_table("users") as batch:
        batch.alter_column(
            "created_at",
            type_=sa.DateTime(),
            existing_type=sa.DateTime(timezone=True),
            existing_nullable=False,
            postgresql_using="created_at AT TIME ZONE 'UTC'",
        )
