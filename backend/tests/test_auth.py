from conftest import TestingSessionLocal, make_session_token
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from models import User


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_me_creates_user_on_first_sign_in(client):
    token = make_session_token("New.User@Example.com", "user_new")

    response = client.get("/v1/me", headers=bearer(token))

    assert response.status_code == 200
    assert response.json()["email"] == "new.user@example.com"
    # A date-time needs an offset; the iPhone app rejects one without.
    assert response.json()["created_at"].endswith("Z")
    with TestingSessionLocal() as db:
        user = db.query(User).one()
        assert user.clerk_user_id == "user_new"


def test_same_clerk_user_maps_to_same_account(client):
    first = client.get("/v1/me", headers=bearer(make_session_token("a@example.com", "user_a")))
    # A later token may carry a changed primary email; the Clerk user id wins.
    second = client.get("/v1/me", headers=bearer(make_session_token("new@example.com", "user_a")))

    assert first.json()["id"] == second.json()["id"]


def test_existing_password_account_is_linked_by_email(client):
    with TestingSessionLocal() as db:
        db.add(User(email="legacy@example.com", password_hash="old-hash"))
        db.commit()

    response = client.get(
        "/v1/me", headers=bearer(make_session_token("Legacy@Example.com", "user_legacy"))
    )

    assert response.status_code == 200
    with TestingSessionLocal() as db:
        user = db.query(User).one()
        assert user.email == "legacy@example.com"
        assert user.clerk_user_id == "user_legacy"


def test_missing_token_is_rejected(client):
    response = client.get("/v1/me")
    assert response.status_code == 401
    assert response.json()["detail"] == "Not authenticated"


def test_expired_token_is_rejected(client):
    token = make_session_token(expires_in=-60)
    assert client.get("/v1/me", headers=bearer(token)).status_code == 401


def test_token_from_other_issuer_is_rejected(client):
    token = make_session_token(issuer="https://evil.clerk.accounts.dev")
    assert client.get("/v1/me", headers=bearer(token)).status_code == 401


def test_token_signed_with_other_key_is_rejected(client):
    other_key = (
        rsa.generate_private_key(public_exponent=65537, key_size=2048)
        .private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        .decode()
    )
    token = make_session_token(private_key=other_key)
    assert client.get("/v1/me", headers=bearer(token)).status_code == 401


def test_token_for_unknown_origin_is_rejected(client):
    token = make_session_token(azp="https://evil.example")
    assert client.get("/v1/me", headers=bearer(token)).status_code == 401


def test_native_app_token_without_azp_is_accepted(client):
    token = make_session_token("ios@example.com", azp=None)
    assert client.get("/v1/me", headers=bearer(token)).status_code == 200


def test_token_without_email_claim_is_rejected(client):
    token = make_session_token(email=None)
    response = client.get("/v1/me", headers=bearer(token))
    assert response.status_code == 401
    assert response.json()["detail"] == "Session token has no email claim"


def test_old_password_endpoints_are_gone(client):
    assert client.post("/users", json={"email": "a@b.c", "password": "x"}).status_code in (404, 405)
    assert client.post("/login", data={"username": "a@b.c", "password": "x"}).status_code in (
        404,
        405,
    )


def test_endpoints_are_only_served_under_v1(client):
    headers = bearer(make_session_token())
    assert client.get("/me", headers=headers).status_code == 404
    assert client.get("/v1/me", headers=headers).status_code == 200


def test_account_moves_to_a_new_clerk_user_with_the_same_email(client):
    first = client.get("/v1/me", headers=bearer(make_session_token("me@example.com", "user_old")))
    # The old Clerk user was deleted in Clerk; the person signed up again.
    second = client.get("/v1/me", headers=bearer(make_session_token("me@example.com", "user_new")))

    assert second.status_code == 200
    assert second.json()["id"] == first.json()["id"]
    with TestingSessionLocal() as db:
        assert db.query(User).one().clerk_user_id == "user_new"
