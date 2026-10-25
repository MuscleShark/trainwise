"""Database models.

Records the iPhone app creates offline (exercises, workouts, templates, body
measurements, readiness) use client-generated UUIDs and carry sync columns:
`updated_at`, `deleted_at` (soft delete, so other devices learn about deletions) and
`change_seq`, a per-user counter the app uses to ask for "changes since N".
"""

import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

from sqlalchemy import (
    JSON,
    BigInteger,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    TypeDecorator,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class UtcDateTime(TypeDecorator):
    """A timestamp with time zone that is stored and returned in UTC.

    PostgreSQL keeps the instant either way; SQLite (tests) would otherwise drop the
    offset. The local time zone of a workout is stored separately (Workout.time_zone).
    """

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is not None:
            if value.tzinfo is None:
                raise ValueError("Timestamps must include a time zone")
            value = value.astimezone(timezone.utc)
        return value

    def process_result_value(self, value, dialect):
        if value is not None:
            value = (
                value.replace(tzinfo=timezone.utc)
                if value.tzinfo is None
                else value.astimezone(timezone.utc)
            )
        return value


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(
        String(255),
        unique=True,
        nullable=False,
    )
    # A unique index (not a constraint) named ix_users_clerk_user_id, which is what
    # production got from the one-off Clerk migration before Alembic.
    clerk_user_id: Mapped[str | None] = mapped_column(
        String(255),
        unique=True,
        index=True,
        nullable=True,
    )
    # Only set for accounts created before sign-in moved to Clerk. No longer used.
    password_hash: Mapped[str | None] = mapped_column(
        String(255),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(UtcDateTime, default=utcnow, nullable=False)
    # Last change_seq handed out for this user's records (see sync.py).
    change_seq: Mapped[int] = mapped_column(
        BigInteger,
        default=0,
        server_default="0",
        nullable=False,
    )

    profile: Mapped["Profile | None"] = relationship(back_populates="user", uselist=False)


class SyncedMixin:
    created_at: Mapped[datetime] = mapped_column(UtcDateTime, default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime, default=utcnow, onupdate=utcnow, nullable=False
    )
    deleted_at: Mapped[datetime | None] = mapped_column(UtcDateTime)
    change_seq: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)


class Profile(Base):
    __tablename__ = "profiles"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), primary_key=True)
    birthday: Mapped[date | None] = mapped_column(Date)
    height_cm: Mapped[float | None] = mapped_column(Float)
    gender: Mapped[str | None] = mapped_column(String(30))
    training_location: Mapped[str | None] = mapped_column(String(30))
    unit_system: Mapped[str] = mapped_column(String(10), default="metric", nullable=False)
    experience_level: Mapped[str | None] = mapped_column(String(20))
    goal: Mapped[str | None] = mapped_column(String(20))
    training_days_per_week: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime, default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime, default=utcnow, onupdate=utcnow, nullable=False
    )
    change_seq: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)

    user: Mapped[User] = relationship(back_populates="profile")


class Exercise(SyncedMixin, Base):
    """A built-in exercise (owner_user_id is null) or one a user created."""

    __tablename__ = "exercises"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    owner_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    name_en: Mapped[str] = mapped_column(String(120), nullable=False)
    name_zh: Mapped[str | None] = mapped_column(String(120))
    equipment: Mapped[str] = mapped_column(String(20), nullable=False)
    # total: whole load (barbell, machine stack); per_side: one dumbbell, handle or
    # side; bodyweight_plus: added weight; assisted: assistance (more is easier).
    load_type: Mapped[str] = mapped_column(String(20), nullable=False)
    primary_muscles: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    secondary_muscles: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    # Other names to search by ("RDL", "卧推"); see catalog.ALIASES.
    aliases: Mapped[list[str]] = mapped_column(
        JSON, default=list, server_default="[]", nullable=False
    )
    # The built-in exercise a custom one is a variant of, e.g. a specific machine.
    base_exercise_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("exercises.id"))


class Workout(SyncedMixin, Base):
    __tablename__ = "workouts"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    template_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    started_at: Mapped[datetime] = mapped_column(UtcDateTime, nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(UtcDateTime)
    time_zone: Mapped[str] = mapped_column(String(64), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)
    avg_heart_rate: Mapped[int | None] = mapped_column(Integer)
    max_heart_rate: Mapped[int | None] = mapped_column(Integer)
    healthkit_workout_id: Mapped[str | None] = mapped_column(String(64))

    exercises: Mapped[list["WorkoutExercise"]] = relationship(
        back_populates="workout",
        cascade="all, delete-orphan",
        order_by="WorkoutExercise.position",
    )


class WorkoutExercise(Base):
    __tablename__ = "workout_exercises"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    workout_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("workouts.id", ondelete="CASCADE"), index=True, nullable=False
    )
    exercise_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("exercises.id"), nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)
    superset_group: Mapped[int | None] = mapped_column(Integer)
    rest_seconds: Mapped[int | None] = mapped_column(Integer)

    workout: Mapped[Workout] = relationship(back_populates="exercises")
    sets: Mapped[list["WorkoutSet"]] = relationship(
        back_populates="workout_exercise",
        cascade="all, delete-orphan",
        order_by="WorkoutSet.position",
    )


class WorkoutSet(Base):
    __tablename__ = "sets"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    workout_exercise_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("workout_exercises.id", ondelete="CASCADE"), index=True, nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    set_type: Mapped[str] = mapped_column(String(10), nullable=False)
    reps: Mapped[int | None] = mapped_column(Integer)
    # Always kilograms, 3 decimals, so pounds round-trip exactly (45 lb = 20.412 kg).
    weight_kg: Mapped[Decimal | None] = mapped_column(Numeric(7, 3))
    rir: Mapped[int | None] = mapped_column(Integer)
    duration_seconds: Mapped[int | None] = mapped_column(Integer)
    # Null while the set is only planned (for example prefilled from a template).
    completed_at: Mapped[datetime | None] = mapped_column(UtcDateTime)

    workout_exercise: Mapped[WorkoutExercise] = relationship(back_populates="sets")


class Template(SyncedMixin, Base):
    """A built-in template (owner_user_id is null) or one a user created."""

    __tablename__ = "templates"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    owner_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    name_en: Mapped[str] = mapped_column(String(120), nullable=False)
    name_zh: Mapped[str | None] = mapped_column(String(120))
    level: Mapped[str | None] = mapped_column(String(20))
    days_per_week: Mapped[int | None] = mapped_column(Integer)
    notes: Mapped[str | None] = mapped_column(Text)

    days: Mapped[list["TemplateDay"]] = relationship(
        back_populates="template",
        cascade="all, delete-orphan",
        order_by="TemplateDay.position",
    )


class TemplateDay(Base):
    __tablename__ = "template_days"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    template_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("templates.id", ondelete="CASCADE"), index=True, nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)

    template: Mapped[Template] = relationship(back_populates="days")
    exercises: Mapped[list["TemplateExercise"]] = relationship(
        back_populates="day",
        cascade="all, delete-orphan",
        order_by="TemplateExercise.position",
    )


class TemplateExercise(Base):
    __tablename__ = "template_exercises"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    template_day_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("template_days.id", ondelete="CASCADE"), index=True, nullable=False
    )
    exercise_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("exercises.id"), nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    rest_seconds: Mapped[int | None] = mapped_column(Integer)
    superset_group: Mapped[int | None] = mapped_column(Integer)

    day: Mapped[TemplateDay] = relationship(back_populates="exercises")
    sets: Mapped[list["TemplateSet"]] = relationship(
        back_populates="template_exercise",
        cascade="all, delete-orphan",
        order_by="TemplateSet.position",
    )


class TemplateSet(Base):
    __tablename__ = "template_sets"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    template_exercise_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("template_exercises.id", ondelete="CASCADE"), index=True, nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    set_type: Mapped[str] = mapped_column(String(10), nullable=False)
    rep_min: Mapped[int | None] = mapped_column(Integer)
    rep_max: Mapped[int | None] = mapped_column(Integer)
    target_rir: Mapped[int | None] = mapped_column(Integer)

    template_exercise: Mapped[TemplateExercise] = relationship(back_populates="sets")


class BodyMeasurement(SyncedMixin, Base):
    __tablename__ = "body_measurements"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    measured_at: Mapped[datetime] = mapped_column(UtcDateTime, nullable=False)
    # weight (kg), body_fat (%), or a girth in cm (waist, chest, arm, thigh, hips, neck).
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    value: Mapped[Decimal] = mapped_column(Numeric(8, 3), nullable=False)
    source: Mapped[str] = mapped_column(String(10), nullable=False)
    healthkit_sample_id: Mapped[str | None] = mapped_column(String(64))


class DailyReadiness(SyncedMixin, Base):
    """One row per user and local date: sleep and recovery summaries from Apple Health."""

    __tablename__ = "daily_readiness"
    __table_args__ = (UniqueConstraint("user_id", "date"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    date: Mapped[date] = mapped_column(Date, nullable=False)
    sleep_minutes: Mapped[int | None] = mapped_column(Integer)
    deep_minutes: Mapped[int | None] = mapped_column(Integer)
    rem_minutes: Mapped[int | None] = mapped_column(Integer)
    core_minutes: Mapped[int | None] = mapped_column(Integer)
    awake_minutes: Mapped[int | None] = mapped_column(Integer)
    hrv_sdnn_ms: Mapped[float | None] = mapped_column(Float)
    resting_hr_bpm: Mapped[float | None] = mapped_column(Float)
    source: Mapped[str] = mapped_column(String(10), nullable=False)
