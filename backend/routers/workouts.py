import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status
from pydantic import AwareDatetime
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from database import get_db
from models import User, Workout, WorkoutExercise, WorkoutSet, utcnow
from schemas import WorkoutPage, WorkoutRead, WorkoutWrite
from security import get_current_user
from sync import (
    check_exercises_visible,
    commit_or_conflict,
    id_conflict,
    next_change_seq,
    not_found,
)

router = APIRouter(
    prefix="/workouts",
    tags=["Workouts"],
)

WITH_SETS = selectinload(Workout.exercises).selectinload(WorkoutExercise.sets)


def own_workout(db: Session, user: User, workout_id: uuid.UUID) -> Workout:
    workout = db.get(Workout, workout_id, options=[WITH_SETS])
    if workout is None or workout.user_id != user.id or workout.deleted_at is not None:
        raise not_found("Workout")
    return workout


@router.get("", response_model=WorkoutPage)
def list_workouts(
    before: AwareDatetime | None = None,
    from_: Annotated[AwareDatetime | None, Query(alias="from")] = None,
    to: AwareDatetime | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Newest first. Pass `next_before` from a page as `before` to get the next page."""
    query = (
        select(Workout)
        .options(WITH_SETS)
        .where(Workout.user_id == current_user.id, Workout.deleted_at.is_(None))
        .order_by(Workout.started_at.desc(), Workout.id.desc())
        .limit(limit)
    )
    if before is not None:
        query = query.where(Workout.started_at < before)
    if from_ is not None:
        query = query.where(Workout.started_at >= from_)
    if to is not None:
        query = query.where(Workout.started_at < to)

    workouts = list(db.scalars(query))
    next_before: datetime | None = workouts[-1].started_at if len(workouts) == limit else None
    return WorkoutPage(items=workouts, next_before=next_before)


@router.get("/{workout_id}", response_model=WorkoutRead)
def get_workout(
    workout_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return own_workout(db, current_user, workout_id)


@router.put("/{workout_id}", response_model=WorkoutRead)
def put_workout(
    workout_id: uuid.UUID,
    workout_data: WorkoutWrite,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Creates the workout or replaces it completely, exercises and sets included.

    Sending the same body again gives the same result, so the app can retry safely.
    """
    workout = db.get(Workout, workout_id, options=[WITH_SETS])
    if workout is not None and workout.user_id != current_user.id:
        raise id_conflict()
    check_exercises_visible(
        db, current_user, {exercise.exercise_id for exercise in workout_data.exercises}
    )

    if workout is None:
        workout = Workout(id=workout_id, user_id=current_user.id)
        db.add(workout)
    else:
        # Replace the children: flush the removals first so reused ids can be inserted.
        workout.exercises.clear()
        db.flush()

    fields = workout_data.model_dump(exclude={"exercises"})
    for field, value in fields.items():
        setattr(workout, field, value)
    workout.exercises = [
        WorkoutExercise(
            id=exercise.id,
            exercise_id=exercise.exercise_id,
            position=position,
            notes=exercise.notes,
            superset_group=exercise.superset_group,
            rest_seconds=exercise.rest_seconds,
            sets=[
                WorkoutSet(position=set_position, **workout_set.model_dump())
                for set_position, workout_set in enumerate(exercise.sets)
            ],
        )
        for position, exercise in enumerate(workout_data.exercises)
    ]
    workout.deleted_at = None
    workout.change_seq = next_change_seq(db, current_user)
    commit_or_conflict(db)
    return own_workout(db, current_user, workout_id)


@router.delete("/{workout_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_workout(
    workout_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    workout = own_workout(db, current_user, workout_id)
    workout.deleted_at = utcnow()
    workout.change_seq = next_change_seq(db, current_user)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
