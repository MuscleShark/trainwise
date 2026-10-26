from fastapi import APIRouter, Depends, Response, status
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from database import get_db
from models import (
    BodyMeasurement,
    DailyReadiness,
    Exercise,
    Profile,
    Recommendation,
    Subscription,
    Template,
    TemplateDay,
    TemplateExercise,
    TemplateSet,
    User,
    Workout,
    WorkoutExercise,
    WorkoutSet,
)
from schemas import UserRead
from security import get_current_user

# Sign-up and sign-in happen in Clerk. The API only identifies the signed-in user.
router = APIRouter(
    tags=["Authentication"],
)


@router.get("/me", response_model=UserRead)
def get_me(
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
    # Bulk deletes, children first, so a long history is a handful of queries.
    # Custom exercises go last: workouts and templates use them.
    workouts = select(Workout.id).where(Workout.user_id == current_user.id)
    workout_exercises = select(WorkoutExercise.id).where(WorkoutExercise.workout_id.in_(workouts))
    templates = select(Template.id).where(Template.owner_user_id == current_user.id)
    days = select(TemplateDay.id).where(TemplateDay.template_id.in_(templates))
    template_exercises = select(TemplateExercise.id).where(
        TemplateExercise.template_day_id.in_(days)
    )
    db.execute(delete(WorkoutSet).where(WorkoutSet.workout_exercise_id.in_(workout_exercises)))
    db.execute(delete(WorkoutExercise).where(WorkoutExercise.workout_id.in_(workouts)))
    db.execute(delete(Workout).where(Workout.user_id == current_user.id))
    db.execute(delete(TemplateSet).where(TemplateSet.template_exercise_id.in_(template_exercises)))
    db.execute(delete(TemplateExercise).where(TemplateExercise.template_day_id.in_(days)))
    db.execute(delete(TemplateDay).where(TemplateDay.template_id.in_(templates)))
    db.execute(delete(Template).where(Template.owner_user_id == current_user.id))
    db.execute(delete(BodyMeasurement).where(BodyMeasurement.user_id == current_user.id))
    db.execute(delete(DailyReadiness).where(DailyReadiness.user_id == current_user.id))
    db.execute(delete(Recommendation).where(Recommendation.user_id == current_user.id))
    db.execute(delete(Subscription).where(Subscription.user_id == current_user.id))
    db.execute(delete(Profile).where(Profile.user_id == current_user.id))
    db.execute(delete(Exercise).where(Exercise.owner_user_id == current_user.id))
    db.delete(current_user)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
