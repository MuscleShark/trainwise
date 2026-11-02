"""Who may use the coach: an active subscription, or a test account allowed by hand.

Kept apart from the API's routers so the coach worker (coach_handler), which has no
sign-in settings such as CLERK_ISSUER, can check access without importing them.
"""

from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from models import Subscription, User, utcnow


def subscription_status(subscription: Subscription | None, now: datetime | None = None) -> str:
    if subscription is None:
        return "none"
    if subscription.status == "revoked":
        return "revoked"
    return "active" if subscription.access_until > (now or utcnow()) else "expired"


def users_subscription(db: Session, user: User) -> Subscription | None:
    return db.scalar(select(Subscription).where(Subscription.user_id == user.id))


def has_coach_access(db: Session, user: User) -> bool:
    """An active subscription, or a test account allowed by hand (users.coach_enabled)."""
    return user.coach_enabled or subscription_status(users_subscription(db, user)) == "active"
