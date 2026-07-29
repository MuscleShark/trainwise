from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models import User, Workout
from schemas import WorkoutCreate, WorkoutRead, WorkoutUpdate
from security import get_current_user


router = APIRouter(
    prefix="/workouts",
    tags=["Workouts"],
)

@router.post("", response_model=WorkoutRead)
def create_workout(
    workout_data: WorkoutCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = Workout(
        user_id=current_user.id,
        workout_date=workout_data.workout_date,
        workout_type=workout_data.workout_type,
        duration_minutes=workout_data.duration_minutes,
        notes=workout_data.notes,
    )

    db.add(workout)
    db.commit()
    db.refresh(workout)

    return workout


@router.get("", response_model=list[WorkoutRead])
def get_workouts(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workouts = (
        db.query(Workout)
        .filter(Workout.user_id == current_user.id)
        .all()
    )

    return workouts


@router.get("/{workout_id}", response_model=WorkoutRead)
def get_workout(
    workout_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = (
        db.query(Workout)
        .filter(
            Workout.id == workout_id,
            Workout.user_id == current_user.id,
        )
        .first()
    )

    if workout is None:
        raise HTTPException(
            status_code=404,
            detail="Workout not found",
        )

    return workout


@router.put("/{workout_id}", response_model=WorkoutRead)
def update_workout(
    workout_id: int,
    workout_data: WorkoutUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = (
        db.query(Workout)
        .filter(
            Workout.id == workout_id,
            Workout.user_id == current_user.id,
        )
        .first()
    )

    if workout is None:
        raise HTTPException(
            status_code=404,
            detail="Workout not found",
        )

    workout.workout_date = workout_data.workout_date
    workout.workout_type = workout_data.workout_type
    workout.duration_minutes = workout_data.duration_minutes
    workout.notes = workout_data.notes

    db.commit()
    db.refresh(workout)

    return workout


@router.delete("/{workout_id}")
def delete_workout(
    workout_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = (
        db.query(Workout)
        .filter(
            Workout.id == workout_id,
            Workout.user_id == current_user.id,
        )
        .first()
    )

    if workout is None:
        raise HTTPException(
            status_code=404,
            detail="Workout not found",
        )

    db.delete(workout)
    db.commit()

    return {"message": "Workout deleted successfully"}