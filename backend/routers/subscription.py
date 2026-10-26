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
    return "active" if subscription.access_until > (now or utcnow()) else "expired"


def users_subscription(db: Session, user: User) -> Subscription | None:
    return db.scalar(select(Subscription).where(Subscription.user_id == user.id))


def has_coach_access(db: Session, user: User) -> bool:
    """An active subscription, or a test account allowed by hand (users.coach_enabled)."""
    return user.coach_enabled or subscription_status(users_subscription(db, user)) == "active"


def read(db: Session, user: User) -> SubscriptionRead:
    subscription = users_subscription(db, user)
    return SubscriptionRead(
        status=subscription_status(subscription),
        product_id=subscription and subscription.product_id,
        expires_at=subscription and subscription.access_until,
        environment=subscription and subscription.environment,
        offer_type=subscription and subscription.offer_type,
        coach_access=has_coach_access(db, user),
    )


def apply(
    subscription: Subscription,
    transaction: appstore.Transaction,
    notification: appstore.Notification | None = None,
) -> None:
    """Brings the subscription up to date with a transaction of it.

    Transactions arrive out of order and can be sent again (a notification, then the
    phone's copy of an older one; a saved copy from before a refund), so a different
    transaction that ends earlier, or an older copy of the stored one, is ignored.
    """
    if subscription.transaction_id is not None:
        if transaction.transaction_id == subscription.transaction_id:
            if transaction.signed_at < subscription.signed_at:
                return
        elif transaction.expires_at < subscription.expires_at:
            return
    subscription.product_id = transaction.product_id
    subscription.transaction_id = transaction.transaction_id
    subscription.signed_at = transaction.signed_at
    subscription.environment = transaction.environment
    subscription.offer_type = transaction.offer_type
    subscription.offer_identifier = transaction.offer_identifier
    subscription.expires_at = transaction.expires_at
    if notification is not None and notification.has_renewal_info:
        subscription.grace_period_expires_at = notification.grace_period_expires_at
    if transaction.revoked_at is not None:
        subscription.status = "revoked"
    else:
        subscription.status = "active" if subscription.access_until > utcnow() else "expired"


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

    The phone sends the transaction StoreKit signed after each purchase, restore,
    redeemed offer code or renewal it sees. It is verified against Apple's root
    certificate, so a forged or altered one is refused (400). An expired one is stored
    and reported as expired.
    409 when the same App Store subscription is already linked to another account.
    """
    try:
        transaction = appstore.verify_transaction(request.signed_transaction)
    except appstore.VerificationError as error:
        raise invalid(error) from error
    # A concurrent request may insert the same subscription first; the second attempt
    # then finds it.
    for attempt in range(2):
        try:
            link(db, current_user, transaction)
            db.commit()
            break
        except IntegrityError as error:
            db.rollback()
            if attempt == 1:
                raise belongs_to_another_account() from error
    return read(db, current_user)


def link(db: Session, user: User, transaction: appstore.Transaction) -> None:
    subscription = db.get(Subscription, transaction.original_transaction_id)
    if subscription is not None and subscription.user_id not in (None, user.id):
        raise belongs_to_another_account()
    current = users_subscription(db, user)
    if current is not None and current is not subscription:
        # Another Apple Account's subscription: it takes over unless the stored one is
        # still running and this one isn't.
        if subscription_status(current) == "active" and transaction.expires_at <= utcnow():
            return
        current.user_id = None
        db.flush()
    if subscription is None:
        subscription = Subscription(original_transaction_id=transaction.original_transaction_id)
        db.add(subscription)
    subscription.user_id = user.id
    apply(subscription, transaction)


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
        subscription = db.get(Subscription, transaction.original_transaction_id)
        if subscription is not None:
            apply(subscription, transaction, verified)
            db.commit()
    print(
        f"App Store notification {verified.notification_type}"
        f"{'/' + verified.subtype if verified.subtype else ''}"
    )
    return {}
