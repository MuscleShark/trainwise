import os

os.environ["DATABASE_URL"] = "sqlite://"
os.environ["CLERK_ISSUER"] = "https://test-instance.clerk.accounts.dev"
os.environ["FRONTEND_URL"] = "http://localhost:3000"

import time
import uuid

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from jose import jwk, jwt
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import security
from catalog import sync_builtin_exercises
from database import Base, get_db
from main import app
from template_catalog import sync_builtin_templates

test_engine = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=test_engine,
)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db

# A local RSA key stands in for the Clerk instance's signing key.
TEST_KID = "test-key"
_private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
PRIVATE_PEM = _private_key.private_bytes(
    serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption(),
).decode()
_public_pem = (
    _private_key.public_key()
    .public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    .decode()
)
TEST_JWKS = {
    "keys": [{**jwk.construct(_public_pem, "RS256").to_dict(), "kid": TEST_KID, "use": "sig"}]
}


def make_session_token(
    email: str | None = "user@example.com",
    clerk_user_id: str | None = None,
    *,
    issuer: str = os.environ["CLERK_ISSUER"],
    azp: str | None = "http://localhost:3000",
    expires_in: int = 60,
    private_key: str = PRIVATE_PEM,
    kid: str = TEST_KID,
) -> str:
    now = int(time.time())
    claims = {
        "sub": clerk_user_id or f"user_{uuid.uuid4().hex}",
        "iss": issuer,
        "iat": now,
        "nbf": now,
        "exp": now + expires_in,
        "sid": f"sess_{uuid.uuid4().hex}",
    }
    if azp is not None:
        claims["azp"] = azp
    if email is not None:
        claims["email"] = email
    return jwt.encode(claims, private_key, algorithm="RS256", headers={"kid": kid})


def auth_headers(email: str, clerk_user_id: str | None = None) -> dict[str, str]:
    return {"Authorization": f"Bearer {make_session_token(email, clerk_user_id)}"}


@pytest.fixture(autouse=True)
def fake_clerk_jwks(monkeypatch):
    monkeypatch.setattr(security, "fetch_jwks", lambda: TEST_JWKS)
    monkeypatch.setitem(security._jwks_cache, "keys", None)


@pytest.fixture
def client():
    Base.metadata.drop_all(bind=test_engine)
    Base.metadata.create_all(bind=test_engine)
    with TestingSessionLocal() as db:
        sync_builtin_exercises(db)
        sync_builtin_templates(db)

    with TestClient(app) as test_client:
        yield test_client

    Base.metadata.drop_all(bind=test_engine)
