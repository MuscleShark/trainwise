import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import (
    AfterValidator,
    AwareDatetime,
    BaseModel,
    Field,
    PlainSerializer,
    WithJsonSchema,
    field_validator,
    model_validator,
)

Muscle = Literal[
    "chest",
    "upper_back",
    "lats",
    "traps",
    "front_delts",
    "side_delts",
    "rear_delts",
    "biceps",
    "triceps",
    "forearms",
    "abs",
    "obliques",
    "lower_back",
    "glutes",
    "quads",
    "hamstrings",
    "adductors",
    "abductors",
    "calves",
]
Equipment = Literal[
    "barbell", "dumbbell", "machine", "cable", "smith", "bodyweight", "kettlebell", "band", "other"
]
LoadType = Literal["total", "per_side", "bodyweight_plus", "assisted"]
SetType = Literal["warmup", "working", "drop", "failure"]
Level = Literal["beginner", "intermediate", "advanced"]
Source = Literal["manual", "healthkit"]
MeasurementKind = Literal["weight", "body_fat", "waist", "chest", "arm", "thigh", "hips", "neck"]

Name = Annotated[str, Field(min_length=1, max_length=120)]
Notes = Annotated[str, Field(max_length=2000)]
HealthKitId = Annotated[str, Field(max_length=64)]
Reps = Annotated[int, Field(ge=0, le=1000)]
Rir = Annotated[int, Field(ge=0, le=10)]
Seconds = Annotated[int, Field(ge=0, le=86_400)]
HeartRate = Annotated[int, Field(ge=20, le=250)]
Minutes = Annotated[int, Field(ge=0, le=1440)]


def _json_number(**bounds) -> WithJsonSchema:
    return WithJsonSchema({"type": "number", **bounds})


# Decimals are stored exactly but sent as JSON numbers: Pydantic would otherwise send
# them as strings and document them as "number or string", which generated clients
# turn into awkward types. Three decimal places survive the trip through a double.
AsNumber = PlainSerializer(float, return_type=float, when_used="json")

WeightKg = Annotated[
    Decimal,
    Field(ge=0, le=2000, max_digits=7, decimal_places=3),
    AsNumber,
    _json_number(minimum=0, maximum=2000),
]
# kg for weight, % for body_fat, cm for girths.
MeasurementValue = Annotated[
    Decimal,
    Field(gt=0, le=1000, max_digits=8, decimal_places=3),
    AsNumber,
    _json_number(exclusiveMinimum=0, maximum=1000),
]


def _check_time_zone(value: str) -> str:
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError):
        raise ValueError("Unknown time zone; use an IANA name such as Europe/Berlin")
    return value


TimeZone = Annotated[str, Field(max_length=64), AfterValidator(_check_time_zone)]


class SyncedRead(BaseModel):
    """Fields every synced record returns, so the app can merge changes."""

    id: uuid.UUID
    updated_at: datetime
    deleted_at: datetime | None
    change_seq: int

    model_config = {"from_attributes": True}


class UserRead(BaseModel):
    id: int
    email: str
    created_at: datetime

    model_config = {"from_attributes": True}


# Profile


class ProfileWrite(BaseModel):
    birthday: date | None = None
    height_cm: Annotated[float, Field(gt=0, le=300)] | None = None
    gender: Annotated[str, Field(max_length=30)] | None = None
    training_location: Literal["gym", "home", "mixed"] | None = None
    unit_system: Literal["metric", "imperial"] = "metric"
    experience_level: Level | None = None
    goal: Literal["strength", "hypertrophy", "general"] | None = None
    training_days_per_week: Annotated[int, Field(ge=1, le=7)] | None = None


class ProfileRead(ProfileWrite):
    updated_at: datetime
    change_seq: int

    model_config = {"from_attributes": True}


# Exercises


class ExerciseWrite(BaseModel):
    name_en: Name
    name_zh: Name | None = None
    equipment: Equipment
    load_type: LoadType
    primary_muscles: Annotated[list[Muscle], Field(min_length=1, max_length=5)]
    secondary_muscles: Annotated[list[Muscle], Field(max_length=8)] = []
    base_exercise_id: uuid.UUID | None = None


class ExerciseRead(SyncedRead, ExerciseWrite):
    is_custom: bool


# Workouts: the whole session (exercises and sets) is written in one request.


class SetWrite(BaseModel):
    id: uuid.UUID
    set_type: SetType = "working"
    reps: Reps | None = None
    weight_kg: WeightKg | None = None
    rir: Rir | None = None
    duration_seconds: Seconds | None = None
    completed_at: AwareDatetime | None = None


class WorkoutExerciseWrite(BaseModel):
    id: uuid.UUID
    exercise_id: uuid.UUID
    notes: Notes | None = None
    superset_group: Annotated[int, Field(ge=1, le=50)] | None = None
    rest_seconds: Seconds | None = None
    sets: Annotated[list[SetWrite], Field(max_length=50)] = []


class WorkoutWrite(BaseModel):
    title: Name
    template_id: uuid.UUID | None = None
    started_at: AwareDatetime
    ended_at: AwareDatetime | None = None
    time_zone: TimeZone
    notes: Notes | None = None
    avg_heart_rate: HeartRate | None = None
    max_heart_rate: HeartRate | None = None
    healthkit_workout_id: HealthKitId | None = None
    exercises: Annotated[list[WorkoutExerciseWrite], Field(max_length=50)] = []

    @model_validator(mode="after")
    def ends_after_start(self):
        if self.ended_at is not None and self.ended_at < self.started_at:
            raise ValueError("ended_at must not be before started_at")
        return self

    @field_validator("exercises")
    @classmethod
    def ids_are_unique(cls, exercises: list[WorkoutExerciseWrite]):
        ids = [exercise.id for exercise in exercises]
        ids += [s.id for exercise in exercises for s in exercise.sets]
        if len(ids) != len(set(ids)):
            raise ValueError("Exercise and set ids must be unique")
        return exercises


class SetRead(SetWrite):
    model_config = {"from_attributes": True}


class WorkoutExerciseRead(WorkoutExerciseWrite):
    sets: list[SetRead]

    model_config = {"from_attributes": True}


class WorkoutRead(SyncedRead, WorkoutWrite):
    exercises: list[WorkoutExerciseRead]


class WorkoutPage(BaseModel):
    items: list[WorkoutRead]
    # Pass as `before` to get the next (older) page; null on the last page.
    next_before: datetime | None


# Templates


class TemplateSetWrite(BaseModel):
    id: uuid.UUID
    set_type: SetType = "working"
    rep_min: Reps | None = None
    rep_max: Reps | None = None
    target_rir: Rir | None = None

    @model_validator(mode="after")
    def rep_range_is_ordered(self):
        if self.rep_min is not None and self.rep_max is not None and self.rep_min > self.rep_max:
            raise ValueError("rep_min must not be greater than rep_max")
        return self


class TemplateExerciseWrite(BaseModel):
    id: uuid.UUID
    exercise_id: uuid.UUID
    rest_seconds: Seconds | None = None
    superset_group: Annotated[int, Field(ge=1, le=50)] | None = None
    sets: Annotated[list[TemplateSetWrite], Field(max_length=20)] = []


class TemplateDayWrite(BaseModel):
    id: uuid.UUID
    name: Name
    exercises: Annotated[list[TemplateExerciseWrite], Field(max_length=30)] = []


class TemplateWrite(BaseModel):
    name_en: Name
    name_zh: Name | None = None
    level: Level | None = None
    days_per_week: Annotated[int, Field(ge=1, le=7)] | None = None
    notes: Notes | None = None
    days: Annotated[list[TemplateDayWrite], Field(min_length=1, max_length=7)]

    @field_validator("days")
    @classmethod
    def ids_are_unique(cls, days: list[TemplateDayWrite]):
        ids = [day.id for day in days]
        ids += [e.id for day in days for e in day.exercises]
        ids += [s.id for day in days for e in day.exercises for s in e.sets]
        if len(ids) != len(set(ids)):
            raise ValueError("Day, exercise and set ids must be unique")
        return days


class TemplateSetRead(TemplateSetWrite):
    model_config = {"from_attributes": True}


class TemplateExerciseRead(TemplateExerciseWrite):
    sets: list[TemplateSetRead]

    model_config = {"from_attributes": True}


class TemplateDayRead(TemplateDayWrite):
    exercises: list[TemplateExerciseRead]

    model_config = {"from_attributes": True}


class TemplateRead(SyncedRead, TemplateWrite):
    days: list[TemplateDayRead]
    is_custom: bool


# Body measurements and readiness


class BodyMeasurementWrite(BaseModel):
    measured_at: AwareDatetime
    kind: MeasurementKind
    value: MeasurementValue
    source: Source = "manual"
    healthkit_sample_id: HealthKitId | None = None


class BodyMeasurementRead(SyncedRead, BodyMeasurementWrite):
    pass


class ReadinessWrite(BaseModel):
    sleep_minutes: Minutes | None = None
    deep_minutes: Minutes | None = None
    rem_minutes: Minutes | None = None
    core_minutes: Minutes | None = None
    awake_minutes: Minutes | None = None
    hrv_sdnn_ms: Annotated[float, Field(gt=0, le=500)] | None = None
    resting_hr_bpm: Annotated[float, Field(ge=20, le=250)] | None = None
    source: Source = "healthkit"


class ReadinessRead(SyncedRead, ReadinessWrite):
    date: date


# Sync


class SyncResponse(BaseModel):
    """Everything of the user's that changed after `since`, including deletions."""

    change_seq: int
    # True when more changes are waiting: call again with since=change_seq.
    has_more: bool
    profile: ProfileRead | None
    exercises: list[ExerciseRead]
    workouts: list[WorkoutRead]
    templates: list[TemplateRead]
    body_measurements: list[BodyMeasurementRead]
    readiness: list[ReadinessRead]
