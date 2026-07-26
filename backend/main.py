from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from schemas import UserLogin, UserCreate, WorkoutCreate, WorkoutRead, WorkoutUpdate
from database import SessionLocal
from models import User, Workout
from pwdlib import PasswordHash
from sqlalchemy.orm import Session
from database import get_db
from security import create_access_token, decode_access_token, get_current_user
from fastapi.security import OAuth2PasswordRequestForm


password_hasher = PasswordHash.recommended()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root():
    return {
        "message": "Backend is running!"
    }

@app.get("/hello")
def hello():
    return {
        "message": "Hello from FastAPI!"
    }

@app.post("/users")
def create_user(user: UserCreate):

    db = SessionLocal()

    new_user = User(
        email=user.email,
        password_hash = password_hasher.hash(user.password)
    )

    db.add(new_user)
    db.commit()
    db.close()

    return {
        "message": "User created successfully!"
    }

@app.post("/login")
def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
):

    db_user = db.query(User).filter(
        User.email == form_data.username
    ).first()

    if db_user is None:
        db.close()
        return {"message": "Invalid email or password"}

    if not password_hasher.verify(
        form_data.password,
        db_user.password_hash
    ):
        db.close()
        return {"message": "Invalid email or password"}

    token = create_access_token(db_user.id)


    return {
        "access_token": token,
        "token_type": "bearer"
    }

@app.get("/me")
def me(current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "email": current_user.email,
    }

@app.post("/workouts", response_model=WorkoutRead)
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

@app.get("/workouts/{workout_id}", response_model=WorkoutRead)
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

@app.put("/workouts/{workout_id}", response_model=WorkoutRead)
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