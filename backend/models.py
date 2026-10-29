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
    Boolean,
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
    false,
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
    # May use the AI coach without a subscription. Set by hand for test accounts.
    coach_enabled: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default=false(), nullable=False
    )
    # The user turned the AI coach on in the app (its consent screen), and the app's
    # language then. The weekly summary is only written while it is on, in that language.
    coach_consent: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default=false(), nullable=False
    )
    coach_language: Mapped[str | None] = mapped_column(String(5))

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
    # Built-in templates the user hid from their list, as UUID strings.
    hidden_template_ids: Mapped[list[str]] = mapped_column(
        JSON, default=list, server_default="[]", nullable=False
    )
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
    # Chinese name of a built-in template's day; users' own days only have `name`.
    name_zh: Mapped[str | None] = mapped_column(String(120))

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


class Recommendation(SyncedMixin, Base):
    """The AI coach's advice for one session, with what it was given.

    The phone creates it with the rule plan (status "pending"); the coach worker fills
    in the result and sets "ready", or "failed" with the reason. Both changes take a
    new change_seq, so the phone gets them through GET /v1/sync.
    """

    __tablename__ = "recommendations"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    # The local date the advice is for.
    for_date: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(10), nullable=False)
    input: Mapped[dict] = mapped_column(JSON, nullable=False)
    output: Mapped[dict | None] = mapped_column(JSON)
    model: Mapped[str | None] = mapped_column(String(80))
    input_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    error: Mapped[str | None] = mapped_column(Text)


class Subscription(Base):
    """An App Store subscription to the AI coach, and the account it belongs to.

    Written from signed transactions the phone sends after a purchase, restore or
    redeemed code (PUT /v1/subscription) and from App Store Server Notifications
    (renewals, expiries, refunds). The original transaction id stays the same across
    renewals; it belongs to at most one account, and an account has at most one.
    Deleting the account only unlinks the row (user_id null), so a refunded purchase
    can't be claimed again by a new account.
    """

    __tablename__ = "subscriptions"

    original_transaction_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), unique=True)
    product_id: Mapped[str] = mapped_column(String(100), nullable=False)
    # The latest transaction applied (the purchase or a renewal) and when Apple signed
    # that copy of it: an older copy of the same transaction never overrides a newer one.
    transaction_id: Mapped[str] = mapped_column(String(64), nullable=False)
    signed_at: Mapped[datetime] = mapped_column(UtcDateTime, nullable=False)
    # Production, Sandbox (TestFlight and App Review) or Xcode (local testing only).
    environment: Mapped[str] = mapped_column(String(20), nullable=False)
    # active, expired or revoked (refunded), as of the last update; read it through
    # subscription_status(), which also looks at the dates.
    status: Mapped[str] = mapped_column(String(10), nullable=False)
    # The offer the latest transaction used, if any: introductory (the free trial),
    # promotional, offer_code (a redeemed promotion code) or win_back, and for codes
    # and promotions the offer's identifier from App Store Connect.
    offer_type: Mapped[str | None] = mapped_column(String(20))
    offer_identifier: Mapped[str | None] = mapped_column(String(100))
    # End of the paid or trial period of the latest transaction.
    expires_at: Mapped[datetime] = mapped_column(UtcDateTime, nullable=False)
    # While Apple retries a failed renewal (billing grace period) access lasts until
    # then. Only notifications set it; the phone's copy of the transaction doesn't know.
    grace_period_expires_at: Mapped[datetime | None] = mapped_column(UtcDateTime)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime, default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime, default=utcnow, onupdate=utcnow, nullable=False
    )

    @property
    def access_until(self) -> datetime:
        return max(filter(None, (self.expires_at, self.grace_period_expires_at)))


class WeeklySummary(SyncedMixin, Base):
    """The AI coach's recap of one user's week, with the numbers it was given.

    The weekly job (coach_handler.start_weekly_summaries) creates one per user and week
    (status "pending"); the coach worker fills it in like a recommendation.
    """

    __tablename__ = "weekly_summaries"
    __table_args__ = (UniqueConstraint("user_id", "week_start"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    # The Monday the week starts on, in the user's time zone.
    week_start: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(10), nullable=False)
    input: Mapped[dict] = mapped_column(JSON, nullable=False)
    output: Mapped[dict | None] = mapped_column(JSON)
    model: Mapped[str | None] = mapped_column(String(80))
    input_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    error: Mapped[str | None] = mapped_column(Text)
