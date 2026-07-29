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


class ProfileCreate(BaseModel):
    birthday: date | None = None
    gender: str | None = None
    height_cm: float | None = None
    weight_kg: float | None = None
    body_fat_percentage: float | None = None
    fitness_goal: str | None = None
    training_frequency: int | None = None
    training_location: str | None = None
    sleep_hours: float | None = None


class ProfileRead(BaseModel):
    id: int
    user_id: int
    birthday: date | None
    gender: str | None
    height_cm: float | None
    weight_kg: float | None
    body_fat_percentage: float | None
    fitness_goal: str | None
    training_frequency: int | None
    training_location: str | None
    sleep_hours: float | None
    created_at: datetime
    updated_at: datetime

    model_config = {
        "from_attributes": True
    }


class ProfileUpdate(BaseModel):
    birthday: date | None = None
    gender: str | None = None
    height_cm: float | None = None
    weight_kg: float | None = None
    body_fat_percentage: float | None = None
    fitness_goal: str | None = None
    training_frequency: int | None = None
    training_location: str | None = None
    sleep_hours: float | None = None


