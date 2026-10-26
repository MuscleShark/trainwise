from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import appstore
from database import get_db
from models import Subscription, User, utcnow
from schemas import AppStoreNotification, SubscriptionRead, SubscriptionWrite
from security import get_current_user

router = APIRouter(tags=["Subscription"])


def subscription_status(subscription: Subscription | None, now: datetime | None = None) -> str:
    if subscription is None:
        return "none"
    if subscription.status == "revoked":
        return "revoked"
    return "active" if subscription.expires_at > (now or utcnow()) else "expired"


def has_coach_access(db: Session, user: User) -> bool:
    """An active subscription, or a test account allowed by hand (users.coach_enabled)."""
    return user.coach_enabled or subscription_status(db.get(Subscription, user.id)) == "active"


def read(db: Session, user: User) -> SubscriptionRead:
    subscription = db.get(Subscription, user.id)
    return SubscriptionRead(
        status=subscription_status(subscription),
        product_id=subscription and subscription.product_id,
        expires_at=subscription and subscription.expires_at,
        environment=subscription and subscription.environment,
        coach_access=has_coach_access(db, user),
    )


def apply(
    subscription: Subscription,
    transaction: appstore.Transaction,
    grace_period_expires_at: datetime | None = None,
) -> None:
    """Brings the entitlement up to date with a transaction of its subscription.

    Transactions can arrive out of order (a notification, then the phone's copy of an
    older one), so one that ends earlier than what is stored is ignored, unless it is
    the stored transaction itself coming back refunded.
    """
    expires_at = max(filter(None, (transaction.expires_at, grace_period_expires_at)))
    same = transaction.transaction_id == subscription.transaction_id
    if subscription.expires_at is not None and expires_at < subscription.expires_at and not same:
        return
    subscription.product_id = transaction.product_id
    subscription.transaction_id = transaction.transaction_id
    subscription.environment = transaction.environment
    subscription.expires_at = expires_at
    if transaction.revoked_at is not None:
        subscription.status = "revoked"
    else:
        subscription.status = "active" if expires_at > utcnow() else "expired"


def invalid(error: appstore.VerificationError) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail=f"The App Store transaction could not be verified: {error}",
    )


def belongs_to_another_account() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail="This App Store subscription belongs to another IronSage account.",
    )


@router.get("/subscription", response_model=SubscriptionRead)
def get_subscription(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return read(db, current_user)


@router.put("/subscription", response_model=SubscriptionRead)
def put_subscription(
    request: SubscriptionWrite,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Records a coach subscription the phone bought or restored.

    The phone sends the transaction StoreKit signed after each purchase, restore or
    renewal it sees. It is verified against Apple's root certificate, so a forged or
    altered one is refused (400). An expired one is stored and reported as expired.
    409 when the same App Store subscription is already linked to another account.
    """
    try:
        transaction = appstore.verify_transaction(request.signed_transaction)
    except appstore.VerificationError as error:
        raise invalid(error) from error

    owned = db.scalar(
        select(Subscription).where(
            Subscription.original_transaction_id == transaction.original_transaction_id
        )
    )
    if owned is not None and owned.user_id != current_user.id:
        raise belongs_to_another_account()
    subscription = db.get(Subscription, current_user.id)
    if subscription is None:
        subscription = Subscription(user_id=current_user.id)
        db.add(subscription)
    elif subscription.original_transaction_id != transaction.original_transaction_id:
        # Another Apple ID's subscription: it takes over unless the stored one is
        # still running and this one isn't.
        if subscription_status(subscription) == "active" and transaction.expires_at <= utcnow():
            return read(db, current_user)
        subscription.expires_at = None
    subscription.original_transaction_id = transaction.original_transaction_id
    apply(subscription, transaction)
    try:
        db.commit()
    except IntegrityError as error:
        # The same subscription was linked to another account a moment ago.
        db.rollback()
        raise belongs_to_another_account() from error
    return read(db, current_user)


@router.post("/app-store/notifications", status_code=status.HTTP_200_OK)
def receive_app_store_notification(
    notification: AppStoreNotification,
    db: Session = Depends(get_db),
) -> dict:
    """App Store Server Notifications V2: renewals, expiries, refunds.

    Called by Apple, not the app, so it needs no sign-in; the payload is verified like a
    transaction instead (400 when it can't be). A subscription no account has claimed
    yet is ignored: the phone sends it after the purchase anyway. Apple retries until
    it gets a 200.
    """
    try:
        verified = appstore.verify_notification(notification.signedPayload)
    except appstore.VerificationError as error:
        raise invalid(error) from error
    transaction = verified.transaction
    if transaction is not None:
        subscription = db.scalar(
            select(Subscription).where(
                Subscription.original_transaction_id == transaction.original_transaction_id
            )
        )
        if subscription is not None:
            apply(subscription, transaction, verified.grace_period_expires_at)
            db.commit()
    print(
        f"App Store notification {verified.notification_type}"
        f"{'/' + verified.subtype if verified.subtype else ''}"
    )
    return {}
