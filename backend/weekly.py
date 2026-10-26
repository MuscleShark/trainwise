"""The numbers for a user's weekly summary, computed from their synced workouts and
readiness. The model only puts them into words (coach/skills/weekly_summary.md).

The rules mirror the phone, so the summary agrees with what the app shows: sets per
muscle (TrainingProgress.weeklySets), estimated one-rep max and records
(WorkoutLog, ExerciseProgress), stalls (NextSession.isStalled), short nights
(NextSession.isShortNight) and the 28-day usual (ReadinessComparison).
"""

from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import get_args
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from coach.schemas import (
    Metric,
    MuscleSets,
    WeeklyInput,
    WeekReadiness,
    WeekRecord,
)
from models import (
    DailyReadiness,
    Exercise,
    Profile,
    User,
    Workout,
    WorkoutExercise,
)
from schemas import Muscle

# Sessions without progress before a lift counts as stalled.
STALL_SESSIONS = 3
# The usual is the average of the 28 days before the week, once 7 of them have data.
BASELINE_DAYS = 28
MINIMUM_DAYS = 7
# A short night: under 6 hours, or at least an hour below usual.
SHORT_NIGHT_MINUTES = 6 * 60
SHORT_NIGHT_BELOW_USUAL = 60
# A lighter week is suggested from this many stalled lifts, or this many short nights
# (docs/coaching.md: repeated stalls across exercises, or readiness that stays low).
# HRV and resting heart rate never suggest one.
DELOAD_STALLS = 2
DELOAD_SHORT_NIGHTS = 4

MUSCLE_ORDER = {muscle: index for index, muscle in enumerate(get_args(Muscle))}


def week_to_summarize(today: date) -> date:
    """The Monday of the last full week before `today`."""
    return today - timedelta(days=today.weekday() + 7)


def zone(name: str | None) -> ZoneInfo | timezone:
    try:
        return ZoneInfo(name) if name else timezone.utc
    except (ZoneInfoNotFoundError, ValueError):
        return timezone.utc


def user_today(db: Session, user: User, now: datetime) -> date | None:
    """The user's local date at `now`, in the time zone of their latest workout; None
    when they have never finished one."""
    time_zone = db.scalar(
        select(Workout.time_zone)
        .where(
            Workout.user_id == user.id,
            Workout.deleted_at.is_(None),
            Workout.ended_at.is_not(None),
        )
        .order_by(Workout.started_at.desc())
        .limit(1)
    )
    return None if time_zone is None else now.astimezone(zone(time_zone)).date()


def estimated_one_rep_max(weight_kg: float, reps: int) -> float | None:
    if weight_kg <= 0 or not 1 <= reps <= 12:
        return None
    return weight_kg if reps == 1 else weight_kg * (1 + reps / 30)


@dataclass
class ExerciseSession:
    """One exercise in one workout: its completed working sets with reps."""

    day: date
    sets: list[tuple[float, int]]  # (weight_kg, reps)

    @property
    def best_estimate(self) -> float | None:
        return max(
            (e for w, r in self.sets if (e := estimated_one_rep_max(w, r)) is not None),
            default=None,
        )


def build_input(db: Session, user: User, week_start: date) -> WeeklyInput | None:
    """The week's numbers, or None when the user finished no workout that week."""
    week_end = week_start + timedelta(days=6)
    # Local dates can be a day ahead of UTC; the exact filter is on the local date.
    before = datetime.combine(week_end + timedelta(days=2), datetime.min.time(), timezone.utc)
    history = [
        (workout.started_at.astimezone(zone(workout.time_zone)).date(), workout)
        for workout in db.scalars(
            select(Workout)
            .options(selectinload(Workout.exercises).selectinload(WorkoutExercise.sets))
            .where(
                Workout.user_id == user.id,
                Workout.deleted_at.is_(None),
                Workout.ended_at.is_not(None),
                Workout.started_at < before,
            )
            .order_by(Workout.started_at.desc())
        )
    ]
    history = [(day, workout) for day, workout in history if day <= week_end]
    this_week = [workout for day, workout in history if day >= week_start]
    if not this_week:
        return None

    exercise_ids = {item.exercise_id for _, workout in history for item in workout.exercises}
    exercises = {
        exercise.id: exercise
        for exercise in db.scalars(select(Exercise).where(Exercise.id.in_(exercise_ids)))
    }
    profile = db.get(Profile, user.id)
    # The app sends its language when the coach is turned on (PUT /v1/coach/settings).
    language = user.coach_language or "en"
    unit = "lb" if profile is not None and profile.unit_system == "imperial" else "kg"

    def name(exercise_id) -> str:
        exercise = exercises[exercise_id]
        return (exercise.name_zh if language == "zh" else None) or exercise.name_en

    sessions: dict = {}  # exercise id -> sessions, newest first
    for day, workout in history:
        by_exercise: dict = {}
        for item in workout.exercises:
            done = [
                (float(s.weight_kg or 0), s.reps)
                for s in item.sets
                if s.completed_at is not None and s.set_type != "warmup" and (s.reps or 0) > 0
            ]
            if done and item.exercise_id in exercises:
                by_exercise.setdefault(item.exercise_id, []).extend(done)
        for exercise_id, done in by_exercise.items():
            sessions.setdefault(exercise_id, []).append(ExerciseSession(day, done))

    # Exercises done this week, in the order they were first done.
    trained = []
    for workout in reversed(this_week):
        for item in workout.exercises:
            if item.exercise_id in sessions and item.exercise_id not in trained:
                if sessions[item.exercise_id][0].day >= week_start:
                    trained.append(item.exercise_id)

    stalled = [e for e in trained if is_stalled(sessions[e])]
    readiness = week_readiness(db, user, week_start)
    return WeeklyInput(
        language=language if language in ("en", "zh") else "en",
        unit=unit,
        goal=profile.goal if profile else None,
        experience=profile.experience_level if profile else None,
        week_start=week_start.isoformat(),
        week_end=week_end.isoformat(),
        workouts=len(this_week),
        sets_per_muscle=sets_per_muscle(this_week, exercises),
        records=[
            record
            for e in trained
            if (record := new_record(sessions[e], exercises[e], week_start, name(e)))
        ][:5],
        stalled=[name(e) for e in stalled][:8],
        readiness=readiness,
        deload_suggested=deload_suggested(len(stalled), readiness),
    )


def sets_per_muscle(workouts: list[Workout], exercises: dict) -> list[MuscleSets]:
    """Completed working sets per muscle: 1 per primary muscle, 0.5 per secondary one.
    Most sets first."""
    totals: dict[str, float] = {}
    for workout in workouts:
        for item in workout.exercises:
            exercise = exercises.get(item.exercise_id)
            done = sum(
                1 for s in item.sets if s.completed_at is not None and s.set_type != "warmup"
            )
            if exercise is None or not done:
                continue
            for muscle in exercise.primary_muscles:
                totals[muscle] = totals.get(muscle, 0) + done
            for muscle in exercise.secondary_muscles:
                if muscle not in exercise.primary_muscles:
                    totals[muscle] = totals.get(muscle, 0) + done / 2
    ordered = sorted(totals.items(), key=lambda m: (-m[1], MUSCLE_ORDER.get(m[0], 99)))
    return [MuscleSets(muscle=muscle, sets=sets) for muscle, sets in ordered]


def is_stalled(sessions: list[ExerciseSession]) -> bool:
    """The best estimated one-rep max of the last three sessions is no better than the
    best before them."""
    if len(sessions) <= STALL_SESSIONS:
        return False
    recent = [s.best_estimate for s in sessions[:STALL_SESSIONS] if s.best_estimate]
    earlier = [s.best_estimate for s in sessions[STALL_SESSIONS:] if s.best_estimate]
    return bool(recent and earlier) and max(recent) <= max(earlier) + 0.0005


def new_record(
    sessions: list[ExerciseSession], exercise: Exercise, week_start: date, name: str
) -> WeekRecord | None:
    """This week's heaviest weight or best estimated one-rep max, when it beats every
    earlier session. None for a first time, and for assisted exercises (less assistance
    is the harder set)."""
    if exercise.load_type == "assisted":
        return None
    week = [(w, r) for s in sessions if s.day >= week_start for w, r in s.sets if w > 0]
    earlier = [(w, r) for s in sessions if s.day < week_start for w, r in s.sets if w > 0]
    if not week or not earlier:
        return None
    heaviest = max(week)
    if heaviest[0] > max(w for w, _ in earlier) + 0.0005:
        return WeekRecord(
            name=name, kind="heaviest", weight_kg=round(heaviest[0], 3), reps=heaviest[1]
        )
    estimates = [(e, w, r) for w, r in week if (e := estimated_one_rep_max(w, r)) is not None]
    before = [e for w, r in earlier if (e := estimated_one_rep_max(w, r)) is not None]
    if estimates and before:
        best, weight, reps = max(estimates)
        if best > max(before) + 0.0005:
            return WeekRecord(
                name=name, kind="estimated_1rm", weight_kg=round(weight, 3), reps=reps
            )
    return None


def week_readiness(db: Session, user: User, week_start: date) -> WeekReadiness:
    """The week's averages next to the usual of the 28 days before the week, and its
    short nights, each judged against the 28 days before that night, as on the phone."""
    week_end = week_start + timedelta(days=6)
    rows = list(
        db.scalars(
            select(DailyReadiness).where(
                DailyReadiness.user_id == user.id,
                DailyReadiness.deleted_at.is_(None),
                DailyReadiness.date >= week_start - timedelta(days=BASELINE_DAYS),
                DailyReadiness.date <= week_end,
            )
        )
    )
    week = [row for row in rows if row.date >= week_start]

    def usual(field: str, before: date) -> float | None:
        start = before - timedelta(days=BASELINE_DAYS)
        values = [
            v
            for row in rows
            if start <= row.date < before and (v := getattr(row, field)) is not None
        ]
        return sum(values) / len(values) if len(values) >= MINIMUM_DAYS else None

    def metric(field: str) -> Metric | None:
        values = [v for row in week if (v := getattr(row, field)) is not None]
        if not values:
            return None
        baseline = usual(field, week_start)
        return Metric(
            value=round(sum(values) / len(values)),
            usual=None if baseline is None else round(baseline),
        )

    def is_short(row: DailyReadiness) -> bool:
        if row.sleep_minutes < SHORT_NIGHT_MINUTES:
            return True
        night_usual = usual("sleep_minutes", row.date)
        return (
            night_usual is not None and night_usual - row.sleep_minutes >= SHORT_NIGHT_BELOW_USUAL
        )

    nights = [row for row in week if row.sleep_minutes is not None]
    return WeekReadiness(
        nights=len(nights),
        sleep_minutes=metric("sleep_minutes"),
        hrv_ms=metric("hrv_sdnn_ms"),
        resting_hr_bpm=metric("resting_hr_bpm"),
        short_nights=sum(is_short(row) for row in nights),
    )


def deload_suggested(stalls: int, readiness: WeekReadiness) -> bool:
    return stalls >= DELOAD_STALLS or readiness.short_nights >= DELOAD_SHORT_NIGHTS
