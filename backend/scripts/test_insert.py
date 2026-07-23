from database import SessionLocal
from models import User

db = SessionLocal()

new_user = User(
    email="kai@example.com",
    password_hash="123456"
)

db.add(new_user)
db.commit()

db.close()

print("User created!")