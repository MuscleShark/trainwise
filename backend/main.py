import os

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum
from sqlalchemy import text
from sqlalchemy.orm import Session

from database import get_db
from routers import auth, profiles, workouts

app = FastAPI()

# Comma-separated, e.g. "https://trainwise.vercel.app,http://localhost:3000".
frontend_urls = [
    url.strip()
    for url in os.getenv("FRONTEND_URL", "http://localhost:3000").split(",")
    if url.strip()
]

app.include_router(workouts.router)
app.include_router(auth.router)
app.include_router(profiles.router)

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
