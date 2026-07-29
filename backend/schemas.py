from pydantic import BaseModel

from datetime import date, datetime


class UserCreate(BaseModel):
    email: str
    password: str


class UserRead(BaseModel):
    id: int
    email: str
    created_at: datetime

    model_config = {
        "from_attributes": True
    }


class UserLogin(BaseModel):
    email: str
    password: str


class WorkoutCreate(BaseModel):
    workout_date: date
    workout_type: str
    duration_minutes: int
    notes: str | None = None


class WorkoutRead(BaseModel):
    id: int
    user_id: int
    workout_date: date
    workout_type: str
    duration_minutes: int
    notes: str | None
    created_at: datetime
    updated_at: datetime

    model_config = {
        "from_attributes": True
    }


class WorkoutUpdate(BaseModel):
    workout_date: date
    workout_type: str
    duration_minutes: int
    notes: str | None = None

