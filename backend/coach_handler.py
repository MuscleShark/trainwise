"""Coach worker Lambda (function handler: "coach_handler.handler").

The API starts it without waiting (routers/coach.py) with {"recommendation_id": ...}.
It asks the model, applies the guardrails and stores the advice, or the reason there
is none, on the recommendation. Either way the record takes a new change_seq, so the
phone picks it up on its next sync. Errors are stored rather than raised, so Lambda
does not retry: the provider SDK already retries a short outage once. A run that dies
anyway (timeout, crash) leaves the record "running"; the API marks it failed once it is
older than STALE_AFTER (routers/coach.py).

Only this function may read ANTHROPIC_API_KEY.
"""

import json
import os
import sys
import uuid

from ssm_parameters import load_ssm_parameters

# What the phone is told when there is no advice. The details go to the logs only.
ERRORS = {"invalid": "invalid_answer", "declined": "declined", "unavailable": "unavailable"}


def run(db, recommendation_id: uuid.UUID, coach_model) -> str:
    """Works on one recommendation; returns its new status, or "skipped" when another
    run has it or it no longer exists."""
    from sqlalchemy import update

    from coach.schemas import CoachInput
    from coach.service import CoachError, advise
    from models import Recommendation, User, utcnow
    from sync import next_change_seq

    # Claim it: async invokes can arrive twice, and only one run may call the model.
    claimed = db.execute(
        update(Recommendation)
        .where(Recommendation.id == recommendation_id, Recommendation.status == "pending")
        .values(status="running", updated_at=utcnow())
    ).rowcount
    if not claimed:
        db.rollback()
        return "skipped"
    plan = CoachInput.model_validate(db.get(Recommendation, recommendation_id).input)
    # Commit before calling the model, so no transaction stays open while it works.
    db.commit()

    outcome: dict = {}
    try:
        result = advise(plan, coach_model)
    except CoachError as error:
        declined = "declined" in str(error)
        outcome = {"status": "failed", "error": ERRORS["declined" if declined else "invalid"]}
        print(f"recommendation {recommendation_id}: {error}")
    except Exception as error:  # the provider's API errors, after its own retry
        outcome = {"status": "failed", "error": ERRORS["unavailable"]}
        print(f"recommendation {recommendation_id}: {type(error).__name__}: {error}")
    else:
        outcome = {
            "status": "ready",
            "output": result.model_dump(mode="json"),
            "model": result.model,
            "input_tokens": result.input_tokens,
            "output_tokens": result.output_tokens,
        }

    # The account may have been deleted in the meantime.
    recommendation = db.get(Recommendation, recommendation_id)
    user = recommendation and db.get(User, recommendation.user_id)
    if recommendation is None or user is None:
        db.rollback()
        return "skipped"
    for field, value in outcome.items():
        setattr(recommendation, field, value)
    recommendation.change_seq = next_change_seq(db, user)
    db.commit()
    return recommendation.status


def handler(event, context):
    load_ssm_parameters(os.getenv("SSM_PARAMETER_PREFIX"), ("DATABASE_URL", "ANTHROPIC_API_KEY"))
    from coach.providers import DEFAULT_MODEL, model
    from database import SessionLocal
    from models import Recommendation

    line = {"recommendation_id": event["recommendation_id"]}
    with SessionLocal() as db:
        recommendation_id = uuid.UUID(event["recommendation_id"])
        status = run(db, recommendation_id, model(DEFAULT_MODEL))
        line["status"] = status
        if status == "ready":
            recommendation = db.get(Recommendation, recommendation_id)
            line["input_tokens"] = recommendation.input_tokens
            line["output_tokens"] = recommendation.output_tokens
    # One JSON line per run; CloudWatch metric filters count the failed ones and the
    # tokens (infra/trainwise_infra/api_stack.py).
    print(json.dumps(line))
    return {"status": status}


if __name__ == "__main__":
    # Local development: python coach_handler.py <recommendation id>
    print(handler({"recommendation_id": sys.argv[1]}, None))
