from fastapi import APIRouter, Depends, Response, status
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from database import get_db
from models import (
    BodyMeasurement,
    DailyReadiness,
    Exercise,
    Profile,
    Template,
    User,
    Workout,
)
from schemas import UserRead
from security import get_current_user

# Sign-up and sign-in happen in Clerk. The API only identifies the signed-in user.
router = APIRouter(
    tags=["Authentication"],
)


@router.get("/me", response_model=UserRead)
def me(
    current_user: User = Depends(get_current_user),
):
    return current_user


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_me(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Deletes the signed-in user's account and all of their data.

    The Clerk user is deleted by the client afterwards (web and iOS call Clerk's
    `user.delete()`), so the API never needs the Clerk secret key. If that step
    fails, the next sign-in simply starts a new, empty account.
    """
    # Workouts and templates go through the ORM so their exercises and sets are
    # deleted with them. Custom exercises go last: workouts and templates use them.
    for workout in db.scalars(select(Workout).where(Workout.user_id == current_user.id)):
        db.delete(workout)
    for template in db.scalars(select(Template).where(Template.owner_user_id == current_user.id)):
        db.delete(template)
    db.flush()
    db.execute(delete(BodyMeasurement).where(BodyMeasurement.user_id == current_user.id))
    db.execute(delete(DailyReadiness).where(DailyReadiness.user_id == current_user.id))
    db.execute(delete(Profile).where(Profile.user_id == current_user.id))
    db.execute(delete(Exercise).where(Exercise.owner_user_id == current_user.id))
    db.delete(current_user)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
