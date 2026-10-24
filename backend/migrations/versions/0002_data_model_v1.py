"""Data model v1: strength sets, exercise catalog, templates, body and readiness history.

Old workouts and profiles are dropped and recreated empty (decided 2026-10-24: the
only data was the developer's own and test data). Users are kept.

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-24
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_table("workouts")
    op.drop_table("profiles")

    op.add_column(
        "users", sa.Column("change_seq", sa.BigInteger(), server_default="0", nullable=False)
    )

    op.create_table(
        "profiles",
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("birthday", sa.Date(), nullable=True),
        sa.Column("height_cm", sa.Float(), nullable=True),
        sa.Column("gender", sa.String(length=30), nullable=True),
        sa.Column("training_location", sa.String(length=30), nullable=True),
        sa.Column("unit_system", sa.String(length=10), nullable=False),
        sa.Column("experience_level", sa.String(length=20), nullable=True),
        sa.Column("goal", sa.String(length=20), nullable=True),
        sa.Column("training_days_per_week", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("change_seq", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("user_id"),
    )
    op.create_table(
        "workouts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("template_id", sa.Uuid(), nullable=True),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("time_zone", sa.String(length=64), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("avg_heart_rate", sa.Integer(), nullable=True),
        sa.Column("max_heart_rate", sa.Integer(), nullable=True),
        sa.Column("healthkit_workout_id", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("change_seq", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_workouts_user_id"), "workouts", ["user_id"], unique=False)

    op.create_table(
        "body_measurements",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("measured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("kind", sa.String(length=20), nullable=False),
        sa.Column("value", sa.Numeric(precision=8, scale=3), nullable=False),
        sa.Column("source", sa.String(length=10), nullable=False),
        sa.Column("healthkit_sample_id", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("change_seq", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_body_measurements_user_id"), "body_measurements", ["user_id"], unique=False
    )
    op.create_table(
        "daily_readiness",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("sleep_minutes", sa.Integer(), nullable=True),
        sa.Column("deep_minutes", sa.Integer(), nullable=True),
        sa.Column("rem_minutes", sa.Integer(), nullable=True),
        sa.Column("core_minutes", sa.Integer(), nullable=True),
        sa.Column("awake_minutes", sa.Integer(), nullable=True),
        sa.Column("hrv_sdnn_ms", sa.Float(), nullable=True),
        sa.Column("resting_hr_bpm", sa.Float(), nullable=True),
        sa.Column("source", sa.String(length=10), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("change_seq", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "date"),
    )
    op.create_table(
        "exercises",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_user_id", sa.Integer(), nullable=True),
        sa.Column("name_en", sa.String(length=120), nullable=False),
        sa.Column("name_zh", sa.String(length=120), nullable=True),
        sa.Column("equipment", sa.String(length=20), nullable=False),
        sa.Column("load_type", sa.String(length=20), nullable=False),
        sa.Column("primary_muscles", sa.JSON(), nullable=False),
        sa.Column("secondary_muscles", sa.JSON(), nullable=False),
        sa.Column("base_exercise_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("change_seq", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(
            ["base_exercise_id"],
            ["exercises.id"],
        ),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_exercises_owner_user_id"), "exercises", ["owner_user_id"], unique=False
    )
    op.create_table(
        "templates",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_user_id", sa.Integer(), nullable=True),
        sa.Column("name_en", sa.String(length=120), nullable=False),
        sa.Column("name_zh", sa.String(length=120), nullable=True),
        sa.Column("level", sa.String(length=20), nullable=True),
        sa.Column("days_per_week", sa.Integer(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("change_seq", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_templates_owner_user_id"), "templates", ["owner_user_id"], unique=False
    )
    op.create_table(
        "template_days",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("template_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.ForeignKeyConstraint(["template_id"], ["templates.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_template_days_template_id"), "template_days", ["template_id"], unique=False
    )
    op.create_table(
        "workout_exercises",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("workout_id", sa.Uuid(), nullable=False),
        sa.Column("exercise_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("superset_group", sa.Integer(), nullable=True),
        sa.Column("rest_seconds", sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(
            ["exercise_id"],
            ["exercises.id"],
        ),
        sa.ForeignKeyConstraint(["workout_id"], ["workouts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_workout_exercises_workout_id"), "workout_exercises", ["workout_id"], unique=False
    )
    op.create_table(
        "sets",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("workout_exercise_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("set_type", sa.String(length=10), nullable=False),
        sa.Column("reps", sa.Integer(), nullable=True),
        sa.Column("weight_kg", sa.Numeric(precision=7, scale=3), nullable=True),
        sa.Column("rir", sa.Integer(), nullable=True),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["workout_exercise_id"], ["workout_exercises.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_sets_workout_exercise_id"), "sets", ["workout_exercise_id"], unique=False
    )
    op.create_table(
        "template_exercises",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("template_day_id", sa.Uuid(), nullable=False),
        sa.Column("exercise_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("rest_seconds", sa.Integer(), nullable=True),
        sa.Column("superset_group", sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(
            ["exercise_id"],
            ["exercises.id"],
        ),
        sa.ForeignKeyConstraint(["template_day_id"], ["template_days.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_template_exercises_template_day_id"),
        "template_exercises",
        ["template_day_id"],
        unique=False,
    )
    op.create_table(
        "template_sets",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("template_exercise_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("set_type", sa.String(length=10), nullable=False),
        sa.Column("rep_min", sa.Integer(), nullable=True),
        sa.Column("rep_max", sa.Integer(), nullable=True),
        sa.Column("target_rir", sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(
            ["template_exercise_id"], ["template_exercises.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_template_sets_template_exercise_id"),
        "template_sets",
        ["template_exercise_id"],
        unique=False,
    )


def downgrade() -> None:
    raise NotImplementedError("Restore a Neon backup instead.")
