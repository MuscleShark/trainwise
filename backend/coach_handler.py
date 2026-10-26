"""Coach worker Lambda (function handler: "coach_handler.handler").

It takes three kinds of events:

- {"recommendation_id": ...}: the API starts it without waiting (routers/coach.py).
- {"job": "weekly_summaries"}: EventBridge Scheduler starts it every Monday morning. It
  creates the past week's summary for every user who may use the coach and starts one
  run per summary, the same way the API does. Near the end of its time it starts itself
  again with {"job": ..., "after_user_id": ...} to go on with the remaining users.
- {"weekly_summary_id": ...}: one of those runs.

A run asks the model, applies the guardrails and stores the answer, or the reason there
is none, on the record. Either way the record takes a new change_seq, so the phone
picks it up on its next sync. Errors are stored rather than raised, so Lambda does not
retry: the provider SDK already retries a short outage once. A run that dies anyway
(timeout, crash) leaves the record "running"; the API marks a recommendation failed
once it is older than STALE_AFTER (routers/coach.py), and the phone only shows ready
weekly summaries.

Only this function may read ANTHROPIC_API_KEY.
"""

import json
import os
import sys
import uuid
from collections.abc import Callable
from datetime import datetime, timedelta

from ssm_parameters import load_ssm_parameters

# What the phone is told when there is no answer. The details go to the logs only.
ERRORS = {"invalid": "invalid_answer", "declined": "declined", "unavailable": "unavailable"}

WEEKLY_JOB = "weekly_summaries"
# The job stops starting users with this much of its time left and hands over to a new run.
JOB_RESERVE_MS = 15_000
# A pending summary older than this was never started (the job died in between); the
# next job run starts it again. The claim keeps a duplicate start harmless.
RESTART_PENDING_AFTER = timedelta(minutes=5)


def run(db, recommendation_id: uuid.UUID, coach_model) -> str:
    """Works on one recommendation; returns its new status, or "skipped" when another
    run has it or it no longer exists."""
    from coach.schemas import CoachInput
    from coach.service import advise
    from models import Recommendation

    return work(
        db,
        Recommendation,
        recommendation_id,
        lambda data: advise(CoachInput.model_validate(data), coach_model),
    )


def run_weekly_summary(db, summary_id: uuid.UUID, coach_model) -> str:
    """Works on one weekly summary, like `run`. Access and consent are checked again
    right before the model is asked: the user may have turned the coach off since the
    job created the summary."""
    from coach.schemas import WeeklyInput
    from coach.service import summarize_week
    from models import WeeklySummary
    from routers.subscription import has_coach_access

    return work(
        db,
        WeeklySummary,
        summary_id,
        lambda data: summarize_week(WeeklyInput.model_validate(data), coach_model),
        allowed=lambda user: user.coach_consent and has_coach_access(db, user),
    )


def work(db, model_class, record_id: uuid.UUID, answer: Callable, allowed=None) -> str:
    from sqlalchemy import update

    from coach.service import CoachError
    from models import User, utcnow
    from sync import next_change_seq

    # Claim it: async invokes can arrive twice, and only one run may call the model.
    claimed = db.execute(
        update(model_class)
        .where(model_class.id == record_id, model_class.status == "pending")
        .values(status="running", updated_at=utcnow())
    ).rowcount
    if not claimed:
        db.rollback()
        return "skipped"
    record = db.get(model_class, record_id)
    data = record.input
    if allowed is not None:
        user = db.get(User, record.user_id)
        if user is None or not allowed(user):
            record.status = "failed"
            record.error = "cancelled"
            if user is not None:
                record.change_seq = next_change_seq(db, user)
            db.commit()
            return "cancelled"
    # Commit before calling the model, so no transaction stays open while it works.
    db.commit()

    label = f"{model_class.__tablename__} {record_id}"
    outcome: dict = {}
    try:
        result = answer(data)
    except CoachError as error:
        declined = "declined" in str(error)
        outcome = {"status": "failed", "error": ERRORS["declined" if declined else "invalid"]}
        print(f"{label}: {error}")
    except Exception as error:  # the provider's API errors, after its own retry
        outcome = {"status": "failed", "error": ERRORS["unavailable"]}
        print(f"{label}: {type(error).__name__}: {error}")
    else:
        outcome = {
            "status": "ready",
            "output": result.model_dump(mode="json"),
            "model": result.model,
            "input_tokens": result.input_tokens,
            "output_tokens": result.output_tokens,
        }

    # The account may have been deleted in the meantime.
    record = db.get(model_class, record_id)
    user = record and db.get(User, record.user_id)
    if record is None or user is None:
        db.rollback()
        return "skipped"
    for field, value in outcome.items():
        setattr(record, field, value)
    record.change_seq = next_change_seq(db, user)
    db.commit()
    return record.status


def start_weekly_summaries(
    db,
    now: datetime,
    start: Callable[[uuid.UUID], None],
    after_user_id: int = 0,
    time_left_ms: Callable[[], int] = lambda: 10**9,
) -> dict:
    """Creates the summary of each coach user's last full week, in their own time zone,
    and starts a run for it. Users who finished no workout that week, or who turned the
    coach off in the app, get none.

    Safe to run again: a user and week has at most one summary (a unique constraint),
    and one that exists is left alone, so a retried job never pays twice. One user's
    error is logged and doesn't stop the others. When time runs short it stops and
    returns `next_user_id`, the user to go on from in a new run.
    """
    from sqlalchemy import select

    from models import User

    counts = {"started": 0, "existing": 0, "no_training": 0, "no_access": 0, "failed": 0}
    # Only users who turned the coach on in the app: nothing is sent without consent.
    # Access (start_weekly_summary) is checked per user, as the API checks it.
    users = select(User.id).where(User.coach_consent, User.id > after_user_id).order_by(User.id)
    for user_id in list(db.scalars(users)):
        if time_left_ms() < JOB_RESERVE_MS:
            return {**counts, "next_user_id": user_id}
        try:
            outcome = start_weekly_summary(db, user_id, now, start)
        except Exception as error:
            db.rollback()
            print(f"weekly_summaries user {user_id}: {type(error).__name__}: {error}")
            outcome = "failed"
        counts[outcome] += 1
    return counts


def start_weekly_summary(db, user_id: int, now: datetime, start: Callable) -> str:
    from sqlalchemy import select
    from sqlalchemy.exc import IntegrityError

    import weekly
    from models import User, WeeklySummary, utcnow
    from routers.subscription import has_coach_access
    from sync import next_change_seq

    user = db.get(User, user_id)
    if user is None:  # deleted since the job began
        return "no_training"
    if not has_coach_access(db, user):
        return "no_access"
    today = weekly.user_today(db, user, now)
    week_start = today and weekly.week_to_summarize(today)
    if week_start is None:
        return "no_training"
    existing = db.scalar(
        select(WeeklySummary).where(
            WeeklySummary.user_id == user.id, WeeklySummary.week_start == week_start
        )
    )
    if existing is not None:
        if existing.status == "pending" and existing.updated_at < utcnow() - RESTART_PENDING_AFTER:
            start(existing.id)
            return "started"
        return "existing"
    week = weekly.build_input(db, user, week_start)
    if week is None:
        db.rollback()
        return "no_training"
    summary = WeeklySummary(
        user_id=user.id,
        week_start=week_start,
        status="pending",
        input=week.model_dump(mode="json"),
        input_tokens=0,
        output_tokens=0,
        change_seq=next_change_seq(db, user),
    )
    db.add(summary)
    try:
        db.commit()
    except IntegrityError:  # another run created it first
        db.rollback()
        return "existing"
    try:
        start(summary.id)
    except Exception as error:
        print(f"weekly_summaries {summary.id}: could not start the worker: {error!r}")
        summary.status = "failed"
        summary.error = ERRORS["unavailable"]
        summary.change_seq = next_change_seq(db, user)
        db.commit()
        return "failed"
    return "started"


def invoke_self(summary_id: uuid.UUID | None, after_user_id: int | None = None) -> None:
    """Starts this function again without waiting: for one summary, or to go on with
    the weekly job after `after_user_id`."""
    import boto3  # bundled with the Lambda Python runtime

    if summary_id is not None:
        event = {"weekly_summary_id": str(summary_id)}
    else:
        event = {"job": WEEKLY_JOB, "after_user_id": after_user_id}
    boto3.client("lambda").invoke(
        FunctionName=os.environ["AWS_LAMBDA_FUNCTION_NAME"],
        InvocationType="Event",
        Payload=json.dumps(event).encode(),
    )


def handler(event, context):
    load_ssm_parameters(os.getenv("SSM_PARAMETER_PREFIX"), ("DATABASE_URL", "ANTHROPIC_API_KEY"))
    from coach.providers import DEFAULT_MODEL, model
    from database import SessionLocal
    from models import Recommendation, WeeklySummary, utcnow

    with SessionLocal() as db:
        if event.get("job") == WEEKLY_JOB:
            time_left = context.get_remaining_time_in_millis if context else lambda: 10**9
            counts = start_weekly_summaries(
                db, utcnow(), invoke_self, event.get("after_user_id", 0), time_left
            )
            print(json.dumps({"job": WEEKLY_JOB, **counts}))
            if "next_user_id" in counts:
                invoke_self(None, after_user_id=counts["next_user_id"] - 1)
            return counts
        if "weekly_summary_id" in event:
            key, model_class, work_on = "weekly_summary_id", WeeklySummary, run_weekly_summary
        else:
            key, model_class, work_on = "recommendation_id", Recommendation, run
        record_id = uuid.UUID(event[key])
        status = work_on(db, record_id, model(DEFAULT_MODEL))
        line = {key: event[key], "status": status}
        # The account may have been deleted since the run committed.
        record = status == "ready" and db.get(model_class, record_id)
        if record:
            line["input_tokens"] = record.input_tokens
            line["output_tokens"] = record.output_tokens
    # One JSON line per run; CloudWatch metric filters count the failed ones and the
    # tokens (infra/trainwise_infra/api_stack.py).
    print(json.dumps(line))
    return {"status": status}


if __name__ == "__main__":
    # Local development: python coach_handler.py <recommendation id>, or
    # python coach_handler.py weekly to write last week's summaries, one after another.
    if sys.argv[1] == "weekly":
        from database import SessionLocal
        from models import utcnow

        def run_here(summary_id):
            print(handler({"weekly_summary_id": str(summary_id)}, None))

        with SessionLocal() as session:
            print(start_weekly_summaries(session, utcnow(), run_here))
    else:
        print(handler({"recommendation_id": sys.argv[1]}, None))
