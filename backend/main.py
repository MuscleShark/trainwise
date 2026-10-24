import os

from fastapi import APIRouter, Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum
from sqlalchemy import text
from sqlalchemy.orm import Session

from database import get_db
from routers import auth, body, exercises, profiles, sync, templates, workouts

app = FastAPI()

# Comma-separated, e.g. "https://trainwise.vercel.app,http://localhost:3000".
frontend_urls = [
    url.strip()
    for url in os.getenv("FRONTEND_URL", "http://localhost:3000").split(",")
    if url.strip()
]

# Every client-facing endpoint lives under /v1, so a later breaking change can ship as
# /v2 while installed iOS app versions keep calling /v1. /health stays unversioned
# because the deploy smoke test calls it.
v1 = APIRouter(prefix="/v1")
v1.include_router(auth.router)
v1.include_router(profiles.router)
v1.include_router(exercises.router)
v1.include_router(workouts.router)
v1.include_router(templates.router)
v1.include_router(body.router)
v1.include_router(sync.router)
app.include_router(v1)

app.add_middleware(
    CORSMiddleware,
    allow_origins=frontend_urls,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ok"}


# Entry point for AWS Lambda (configure the function handler as "main.handler").
handler = Mangum(app, lifespan="off")
