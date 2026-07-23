from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from schemas import UserCreate
from database import SessionLocal
from models import User
from pwdlib import PasswordHash


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