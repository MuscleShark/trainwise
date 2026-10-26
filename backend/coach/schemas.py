"""What goes into the coach and what comes out.

The input is a compact daily summary built by the phone: the rule plan for the next
session, the last few sessions of each exercise, and last night's readiness compared
with the user's own baseline. No raw Apple Health samples.
"""

from enum import Enum
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Language = Literal["en", "zh"]


class PlannedSet(BaseModel):
    reps: int | None = None
    weight_kg: float | None = None
    set_type: Literal["warmup", "working", "drop", "failure"] = "working"


class DoneSet(BaseModel):
    reps: int | None = None
    weight_kg: float | None = None
    rir: int | None = None


class Session(BaseModel):
    date: str
    sets: list[DoneSet]


class RuleChange(str, Enum):
    """Mirrors NextSession.Change on the phone."""

    first_time = "first_time"
    increase = "increase"
    add_reps = "add_reps"
    repeat_weight = "repeat_weight"
    decrease = "decrease"
    deload = "deload"
    held_for_sleep = "held_for_sleep"
    add_load_or_variation = "add_load_or_variation"


class ExercisePlan(BaseModel):
    exercise_id: str
    name: str
    is_compound: bool = True
    change: RuleChange
    rep_min: int
    rep_max: int
    stalled: bool = False
    planned_sets: list[PlannedSet]
    # The weight the rules started from, so the coach can hold it instead of increasing.
    last_weight_kg: float | None = None
    recent_sessions: list[Session] = Field(default_factory=list, max_length=5)


class Metric(BaseModel):
    value: float
    usual: float | None = None


class Readiness(BaseModel):
    sleep_minutes: Metric | None = None
    hrv_ms: Metric | None = None
    resting_hr_bpm: Metric | None = None


class CoachInput(BaseModel):
    language: Language = "en"
    unit: Literal["kg", "lb"] = "kg"
    goal: Literal["strength", "hypertrophy", "general"] | None = None
    experience: Literal["beginner", "intermediate", "advanced"] | None = None
    readiness: Readiness = Field(default_factory=Readiness)
    exercises: list[ExercisePlan] = Field(min_length=1, max_length=15)


class Action(str, Enum):
    """The only changes the coach may make to the rule plan."""

    follow = "follow"  # the rule plan as it is
    hold_weight = "hold_weight"  # no weight increase today
    one_set_fewer = "one_set_fewer"  # drop the last working set


class ExerciseAdvice(BaseModel):
    model_config = ConfigDict(extra="forbid")

    exercise_id: str
    action: Action
    reason: str = Field(max_length=280)


class CoachOutput(BaseModel):
    """What the model must return; its JSON schema is sent to every provider."""

    model_config = ConfigDict(extra="forbid")

    summary: str = Field(max_length=280)
    exercises: list[ExerciseAdvice]


class FinalExercise(BaseModel):
    exercise_id: str
    action: Action
    reason: str
    sets: list[PlannedSet]


class CoachResult(BaseModel):
    summary: str
    exercises: list[FinalExercise]
    model: str
    input_tokens: int = 0
    output_tokens: int = 0
