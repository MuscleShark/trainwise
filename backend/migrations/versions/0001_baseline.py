"""Baseline: users, profiles and workouts as they were before Alembic.

Production already had these tables (created by create_tables.py and
scripts/migrate_add_clerk.py), so each table is only created when it is missing.
On production this revision just records the starting point.

Revision ID: 0001
Revises:
Create Date: 2026-10-24
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    existing = set(sa.inspect(op.get_bind()).get_table_names())

    if "users" not in existing:
        op.create_table(
            "users",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("email", sa.String(255), nullable=False, unique=True),
            sa.Column("clerk_user_id", sa.String(255), nullable=True),
            sa.Column("password_hash", sa.String(255), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False),
        )
        op.create_index("ix_users_clerk_user_id", "users", ["clerk_user_id"], unique=True)

    if "workouts" not in existing:
        op.create_table(
            "workouts",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("workout_date", sa.Date(), nullable=False),
            sa.Column("workout_type", sa.String(50), nullable=False),
            sa.Column("duration_minutes", sa.Integer(), nullable=False),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
        )

    if "profiles" not in existing:
        op.create_table(
            "profiles",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column(
                "user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False, unique=True
            ),
            sa.Column("birthday", sa.Date(), nullable=True),
            sa.Column("gender", sa.String(30), nullable=True),
            sa.Column("height_cm", sa.Float(), nullable=True),
            sa.Column("weight_kg", sa.Float(), nullable=True),
            sa.Column("body_fat_percentage", sa.Float(), nullable=True),
            sa.Column("fitness_goal", sa.String(100), nullable=True),
            sa.Column("training_frequency", sa.Integer(), nullable=True),
            sa.Column("training_location", sa.String(50), nullable=True),
            sa.Column("sleep_hours", sa.Float(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
        )


def downgrade() -> None:
    raise NotImplementedError("The baseline cannot be downgraded. Restore a Neon backup instead.")
