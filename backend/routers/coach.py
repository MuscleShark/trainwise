import os
import uuid
from collections.abc import Callable
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from database import get_db
from models import Recommendation, User, utcnow
from routers.subscription import has_coach_access
from schemas import CoachSettings, RecommendationRead, RecommendationWrite
from security import get_current_user
from sync import id_conflict, next_change_seq

router = APIRouter(tags=["Coach"])

# Requests per user in any 24 hours: one after each workout and one each morning,
# with room for a retry.
DAILY_LIMIT = 5

# A request still unfinished after this was lost (the worker crashed or never
# started); it is marked failed, so the app stops waiting.
STALE_AFTER = timedelta(minutes=2)


def invoke_coach_worker(recommendation_id: uuid.UUID) -> None:
    """Starts the coach worker Lambda without waiting for it (see coach_handler.py).

    Without COACH_FUNCTION_NAME (local development) nothing runs; run the worker by
    hand with `python coach_handler.py <id>`.
    """
    function_name = os.getenv("COACH_FUNCTION_NAME")
    if not function_name:
        return
    import json

    import boto3  # bundled with the Lambda Python runtime

    boto3.client("lambda").invoke(
        FunctionName=function_name,
        InvocationType="Event",
        Payload=json.dumps({"recommendation_id": str(recommendation_id)}).encode(),
    )


def get_coach_starter() -> Callable[[uuid.UUID], None]:
    return invoke_coach_worker


@router.put("/coach/settings", response_model=CoachSettings)
def put_coach_settings(
    settings: CoachSettings,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Records whether the user turned the AI coach on in the app, and its language.

    The weekly summary is written only while it is on. Works without a subscription,
    so turning the coach off always succeeds.
    """
    current_user.coach_consent = settings.enabled
    current_user.coach_language = settings.language
    db.commit()
    return settings


@router.put("/recommendations/{recommendation_id}", response_model=RecommendationRead)
def request_recommendation(
    recommendation_id: uuid.UUID,
    request: RecommendationWrite,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    start_coach: Callable[[uuid.UUID], None] = Depends(get_coach_starter),
):
    """Asks the AI coach to adjust and explain the phone's rule plan.

    Returns at once with status "pending"; the advice arrives through GET /v1/sync
    when it is ready, usually within seconds. Sending the same id again returns the
    existing request without asking again, so retries are safe.

    402 without an active coach subscription (test accounts can be allowed by hand
    with users.coach_enabled); 429 after DAILY_LIMIT requests in
    24 hours.
    """
    recommendation = db.get(Recommendation, recommendation_id)
    if recommendation is not None:
        if recommendation.user_id != current_user.id:
            raise id_conflict()
        if recommendation.status in ("pending", "running") and (
            recommendation.updated_at < utcnow() - STALE_AFTER
        ):
            fail(db, recommendation, current_user, "timed_out")
        return recommendation

    if not has_coach_access(db, current_user):
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="The AI coach needs a subscription.",
        )
    # Taking the change_seq first locks the user's row, so concurrent requests are
    # counted one after another and can't all slip under the limit.
    change_seq = next_change_seq(db, current_user)
    recent = db.scalar(
        select(func.count())
        .select_from(Recommendation)
        .where(
            Recommendation.user_id == current_user.id,
            Recommendation.created_at >= utcnow() - timedelta(hours=24),
        )
    )
    if recent >= DAILY_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Daily limit for the AI coach reached. Try again tomorrow.",
        )

    recommendation = Recommendation(
        id=recommendation_id,
        user_id=current_user.id,
        for_date=request.for_date,
        status="pending",
        input=request.input.model_dump(mode="json"),
        input_tokens=0,
        output_tokens=0,
        change_seq=change_seq,
    )
    db.add(recommendation)
    db.commit()
    db.refresh(recommendation)
    try:
        start_coach(recommendation.id)
    except Exception as error:
        print(f"recommendation {recommendation.id}: could not start the worker: {error!r}")
        fail(db, recommendation, current_user, "unavailable")
    return recommendation


def fail(db: Session, recommendation: Recommendation, user: User, error: str) -> None:
    recommendation.status = "failed"
    recommendation.error = error
    recommendation.change_seq = next_change_seq(db, user)
    db.commit()
    db.refresh(recommendation)
