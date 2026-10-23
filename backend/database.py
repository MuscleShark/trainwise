import os

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is not configured")

connect_args = {}
if DATABASE_URL.startswith("postgresql+psycopg"):
    # Neon's pooled endpoint (PgBouncer) does not keep server-side prepared statements.
    connect_args["prepare_threshold"] = None

# pre_ping replaces connections that went stale while a Lambda instance was frozen.
engine = create_engine(DATABASE_URL, pool_pre_ping=True, connect_args=connect_args)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()