"""Helpers shared by the routers that write synced records.

Every write takes the next value of the user's counter (users.change_seq) and
stores it on the record. The UPDATE locks the user's row until the transaction
commits, so one user's changes always commit in counter order and `GET /v1/sync`
never skips a change. Different users never wait for each other.
"""

import uuid

from fastapi import HTTPException, status
from sqlalchemy import or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from models import Exercise, Template, User
from schemas import ExerciseRead, TemplateRead


def next_change_seq(db: Session, user: User) -> int:
    return db.execute(
        update(User)
        .where(User.id == user.id)
        .values(change_seq=User.change_seq + 1)
        .returning(User.change_seq)
    ).scalar_one()


def not_found(what: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"{what} not found")


def id_conflict() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail="This id is already used. Generate a new UUID.",
    )


def commit_or_conflict(db: Session) -> None:
    """Commits; a child id (exercise, set, day) that another record already uses is a 409."""
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise id_conflict()


def check_exercises_visible(db: Session, user: User, exercise_ids: set[uuid.UUID]) -> None:
    """Workouts and templates may only use built-in exercises or the user's own."""
    if not exercise_ids:
        return
    found = set(
        db.scalars(
            select(Exercise.id).where(
                Exercise.id.in_(exercise_ids),
                or_(Exercise.owner_user_id.is_(None), Exercise.owner_user_id == user.id),
            )
        )
    )
    missing = exercise_ids - found
    if missing:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f"Unknown exercise: {sorted(str(i) for i in missing)[0]}",
        )


def exercise_read(exercise: Exercise) -> ExerciseRead:
    return ExerciseRead.model_validate(
        {
            **{c: getattr(exercise, c) for c in ExerciseRead.model_fields if c != "is_custom"},
            "is_custom": exercise.owner_user_id is not None,
        }
    )


def template_read(template: Template) -> TemplateRead:
    return TemplateRead.model_validate(
        {
            **{c: getattr(template, c) for c in TemplateRead.model_fields if c != "is_custom"},
            "is_custom": template.owner_user_id is not None,
        }
    )
