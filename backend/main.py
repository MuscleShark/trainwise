import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routers import auth, workouts, profiles

app = FastAPI()

frontend_url = os.getenv("FRONTEND_URL", "http://localhost:3000")

app.include_router(workouts.router)
app.include_router(auth.router)
app.include_router(profiles.router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[frontend_url],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
