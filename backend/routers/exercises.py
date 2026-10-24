import uuid

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from database import get_db
from models import Exercise, User, utcnow
from schemas import ExerciseRead, ExerciseWrite
from security import get_current_user
from sync import exercise_read, id_conflict, next_change_seq, not_found

router = APIRouter(
    prefix="/exercises",
    tags=["Exercises"],
)


@router.get("", response_model=list[ExerciseRead])
def list_exercises(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The built-in catalog plus the user's own exercises."""
    exercises = db.scalars(
        select(Exercise)
        .where(
            Exercise.deleted_at.is_(None),
            or_(Exercise.owner_user_id.is_(None), Exercise.owner_user_id == current_user.id),
        )
        .order_by(Exercise.name_en)
    )
    return [exercise_read(exercise) for exercise in exercises]


@router.put("/{exercise_id}", response_model=ExerciseRead)
def put_exercise(
    exercise_id: uuid.UUID,
    exercise_data: ExerciseWrite,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Creates or replaces one of the user's own exercises."""
    exercise = db.get(Exercise, exercise_id)
    if exercise is not None and exercise.owner_user_id is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Built-in exercises cannot be changed")
    if exercise is not None and exercise.owner_user_id != current_user.id:
        raise id_conflict()

    if exercise_data.base_exercise_id is not None:
        base = db.get(Exercise, exercise_data.base_exercise_id)
        if base is None or base.owner_user_id is not None:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_CONTENT,
                "base_exercise_id must be a built-in exercise",
            )

    if exercise is None:
        exercise = Exercise(id=exercise_id, owner_user_id=current_user.id)
        db.add(exercise)
    for field, value in exercise_data.model_dump().items():
        setattr(exercise, field, value)
    exercise.deleted_at = None
    exercise.change_seq = next_change_seq(db, current_user)
    db.commit()
    db.refresh(exercise)
    return exercise_read(exercise)


@router.delete("/{exercise_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_exercise(
    exercise_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Soft-deletes the exercise; past workouts keep showing it."""
    exercise = db.get(Exercise, exercise_id)
    if exercise is None or exercise.owner_user_id != current_user.id:
        raise not_found("Exercise")
    if exercise.deleted_at is None:
        exercise.deleted_at = utcnow()
        exercise.change_seq = next_change_seq(db, current_user)
        db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
