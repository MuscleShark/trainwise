from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from database import get_db
from models import Profile, User, Workout
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
    db.query(Workout).filter(Workout.user_id == current_user.id).delete()
    db.query(Profile).filter(Profile.user_id == current_user.id).delete()
    db.delete(current_user)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
