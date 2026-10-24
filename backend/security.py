"""Authentication with Clerk session tokens.

Clients (web and iOS) sign in with Clerk and send the short-lived session token as
`Authorization: Bearer <token>`. The token is verified locally against the Clerk
instance's JWKS, then mapped to a row in `users` (linked by Clerk user id, or by email
for accounts that existed before Clerk).

The session token must carry the user's email as a custom claim. In the Clerk
Dashboard → Sessions → Customize session token: {"email": "{{user.primary_email_address}}"}
"""

import json
import os
import time
import urllib.request

from dotenv import load_dotenv
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy import func
from sqlalchemy.orm import Session

from database import get_db
from models import User

load_dotenv()

CLERK_ISSUER = os.getenv("CLERK_ISSUER", "").rstrip("/")

if not CLERK_ISSUER:
    raise RuntimeError("CLERK_ISSUER is not configured")

# Browser origins allowed to use tokens (Clerk's `azp` claim). Native apps omit `azp`.
AUTHORIZED_PARTIES = {
    url.strip()
    for url in os.getenv("FRONTEND_URL", "http://localhost:3000").split(",")
    if url.strip()
}

JWKS_URL = f"{CLERK_ISSUER}/.well-known/jwks.json"
JWKS_CACHE_SECONDS = 60 * 60
CLOCK_SKEW_SECONDS = 5

bearer_scheme = HTTPBearer(auto_error=False)

_jwks_cache: dict = {"keys": None, "fetched_at": 0.0}


def fetch_jwks() -> dict:
    with urllib.request.urlopen(JWKS_URL, timeout=5) as response:
        return json.load(response)


def get_jwks(force_refresh: bool = False) -> dict:
    expired = time.time() - _jwks_cache["fetched_at"] > JWKS_CACHE_SECONDS
    if force_refresh or expired or _jwks_cache["keys"] is None:
        _jwks_cache["keys"] = fetch_jwks()
        _jwks_cache["fetched_at"] = time.time()
    return _jwks_cache["keys"]


def _signing_key(token: str) -> dict:
    kid = jwt.get_unverified_header(token).get("kid")
    for refresh in (False, True):
        for key in get_jwks(force_refresh=refresh).get("keys", []):
            if key.get("kid") == kid:
                return key
    raise JWTError("Unknown signing key")


def verify_session_token(token: str) -> dict:
    claims = jwt.decode(
        token,
        _signing_key(token),
        algorithms=["RS256"],
        issuer=CLERK_ISSUER,
        options={"verify_aud": False, "leeway": CLOCK_SKEW_SECONDS},
    )
    azp = claims.get("azp")
    if azp and azp not in AUTHORIZED_PARTIES:
        raise JWTError("Unauthorized party")
    if not claims.get("sub"):
        raise JWTError("Missing subject")
    return claims


def _unauthorized(detail: str = "Invalid authentication credentials") -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None:
        raise _unauthorized("Not authenticated")

    try:
        claims = verify_session_token(credentials.credentials)
    except (JWTError, ValueError):
        raise _unauthorized()

    clerk_user_id = claims["sub"]
    user = db.query(User).filter(User.clerk_user_id == clerk_user_id).first()
    if user is not None:
        return user

    email = (claims.get("email") or "").strip().lower()
    if not email:
        raise _unauthorized("Session token has no email claim")

    # First sign-in with this Clerk user: link the account with the same email, or
    # create a new one. The account may already belong to an older Clerk user, for
    # example one deleted in Clerk before the person signed up again with the same
    # address. Clerk has verified the email and allows it on one Clerk user only, so
    # the account moves to the new Clerk user.
    user = db.query(User).filter(func.lower(User.email) == email).first()
    if user is None:
        user = User(email=email)
        db.add(user)
    user.clerk_user_id = clerk_user_id
    db.commit()
    db.refresh(user)
    return user
