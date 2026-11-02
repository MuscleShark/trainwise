"""Cardio: exercises logged by time, with distance, speed, incline and the machine's level.

Revision ID: 0011
Revises: 0010
Create Date: 2026-11-01
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "exercises",
        sa.Column("kind", sa.String(10), server_default="strength", nullable=False),
    )
    op.add_column(
        "exercises",
        sa.Column("cardio_metrics", sa.JSON(), server_default="[]", nullable=False),
    )
    op.add_column("sets", sa.Column("distance_m", sa.Numeric(9, 2), nullable=True))
    op.add_column("sets", sa.Column("speed_kmh", sa.Numeric(5, 2), nullable=True))
    op.add_column("sets", sa.Column("incline_pct", sa.Numeric(4, 1), nullable=True))
    op.add_column("sets", sa.Column("level", sa.Integer(), nullable=True))
    op.add_column("sets", sa.Column("floors", sa.Integer(), nullable=True))
    op.add_column("sets", sa.Column("avg_heart_rate", sa.Integer(), nullable=True))
    op.add_column("sets", sa.Column("energy_kcal", sa.Integer(), nullable=True))
    op.add_column("sets", sa.Column("healthkit_workout_id", sa.String(64), nullable=True))
    op.add_column("template_sets", sa.Column("duration_seconds", sa.Integer(), nullable=True))
    op.add_column("template_sets", sa.Column("speed_kmh", sa.Numeric(5, 2), nullable=True))
    op.add_column("template_sets", sa.Column("incline_pct", sa.Numeric(4, 1), nullable=True))
    op.add_column("template_sets", sa.Column("level", sa.Integer(), nullable=True))


def downgrade() -> None:
    for column in ("level", "incline_pct", "speed_kmh", "duration_seconds"):
        op.drop_column("template_sets", column)
    for column in (
        "healthkit_workout_id",
        "energy_kcal",
        "avg_heart_rate",
        "floors",
        "level",
        "incline_pct",
        "speed_kmh",
        "distance_m",
    ):
        op.drop_column("sets", column)
    op.drop_column("exercises", "cardio_metrics")
    op.drop_column("exercises", "kind")
