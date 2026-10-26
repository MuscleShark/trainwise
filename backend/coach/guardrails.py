"""Turns the model's choices into sets, within limits the model can't get around."""

from .schemas import (
    Action,
    CoachInput,
    CoachOutput,
    ExercisePlan,
    FinalExercise,
    PlannedSet,
)


class InvalidAdvice(ValueError):
    """The model's answer doesn't fit the plan it was given."""


def apply(plan: CoachInput, advice: CoachOutput) -> list[FinalExercise]:
    """One final exercise per planned exercise, in the plan's order.

    Every planned exercise must get exactly one piece of advice, and no other. An
    action that can't change anything (holding a weight that wasn't going up) is
    accepted but leaves the sets as planned.
    """
    by_id = {item.exercise_id: item for item in advice.exercises}
    planned_ids = [exercise.exercise_id for exercise in plan.exercises]
    if len(by_id) != len(advice.exercises):
        raise InvalidAdvice("an exercise was advised twice")
    if set(by_id) != set(planned_ids):
        raise InvalidAdvice("the advice doesn't match the planned exercises")
    return [
        FinalExercise(
            exercise_id=exercise.exercise_id,
            action=by_id[exercise.exercise_id].action,
            reason=by_id[exercise.exercise_id].reason.strip(),
            sets=adjusted_sets(exercise, by_id[exercise.exercise_id].action),
        )
        for exercise in plan.exercises
    ]


def adjusted_sets(exercise: ExercisePlan, action: Action) -> list[PlannedSet]:
    sets = [s.model_copy() for s in exercise.planned_sets]
    if action == Action.hold_weight and exercise.last_weight_kg is not None:
        top = max((s.weight_kg or 0 for s in sets if s.set_type != "warmup"), default=0)
        if top > exercise.last_weight_kg:
            # Undo the planned increase: every set moves back by the same amount and
            # aims for last time's reps again.
            delta = top - exercise.last_weight_kg
            last = exercise.recent_sessions[0].sets if exercise.recent_sessions else []
            index = 0
            for s in sets:
                if s.set_type == "warmup" or s.weight_kg is None:
                    continue
                s.weight_kg = round(max(0.0, s.weight_kg - delta), 3)
                if last and s.set_type == "working":
                    s.reps = last[min(index, len(last) - 1)].reps or s.reps
                    index += 1
    elif action == Action.one_set_fewer:
        working = [i for i, s in enumerate(sets) if s.set_type == "working"]
        if len(working) > 1:
            del sets[working[-1]]
    return sets
