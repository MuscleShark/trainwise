from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from schemas import UserLogin, UserCreate
from database import SessionLocal
from models import User
from pwdlib import PasswordHash
from sqlalchemy.orm import Session
from database import get_db
from security import create_access_token, decode_access_token, get_current_user
from fastapi.security import OAuth2PasswordRequestForm
from routers import workouts
from routers import auth, workouts

app = FastAPI()

app.include_router(workouts.router)
app.include_router(auth.router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)