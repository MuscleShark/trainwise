import json
import sys
import uuid
from datetime import date, datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from conftest import TestingSessionLocal, auth_headers
from helpers import BENCH, SQUAT, new_id
from sqlalchemy import select
from test_coach_api import enable_coach

import coach_handler
import weekly
from catalog import exercise_id
from coach import providers
from models import User, WeeklySummary, utcnow

EMAIL = "lifter@example.com"
ASSISTED = str(exercise_id("assisted_pull_up"))
# Monday morning in New York; the week to summarize is 19 to 25 October.
NOW = datetime(2026, 10, 26, 14, 0, tzinfo=timezone.utc)
WEEK = date(2026, 10, 19)


class FakeWeeklyModel:
    """Writes a short summary from the input's own numbers, in its language."""

    name = "fake:model"

    def __init__(self, answer=None, deload=None):
        self.answer = answer
        self.deload = deload
        self.requests = []

    def complete(self, system, user, schema):
        self.requests.append((system, user, schema))
        if self.answer:
            return providers.Completion(self.answer(user), 100, 20)
        data = json.loads(user.split("<input>")[1].split("</input>")[0])
        deload = data.get("deload_suggested", False) if self.deload is None else self.deload
        top = data["sets_per_muscle"][0]
        sets = f"{top['sets']:g}"
        if data["language"] == "zh":
            summary = f"本周你训练了{data['workouts']}次。{top['muscle']}完成了{sets}组。继续保持。"
            suggestions = ["下周做一个减量周。"] if deload else ["下周保持同样的训练。"]
        else:
            summary = (
                f"You trained {data['workouts']} times this week. "
                f"{top['muscle']} got {sets} sets. Keep it up."
            )
            suggestions = ["Take a lighter week."] if deload else ["Keep the same plan."]
        answer = {"summary": summary, "suggestions": suggestions, "deload": deload}
        return providers.Completion(json.dumps(answer, ensure_ascii=False), 1200, 250)


def log(client, started_at, sets, exercise=BENCH, email=EMAIL, time_zone="America/New_York"):
    """A finished workout of one exercise with the given (weight, reps) sets."""
    body = {
        "title": "Training",
        "started_at": started_at,
        "ended_at": started_at,
        "time_zone": time_zone,
        "exercises": [
            {
                "id": new_id(),
                "exercise_id": exercise,
                "sets": [
                    {
                        "id": new_id(),
                        "set_type": "warmup",
                        "reps": 10,
                        "weight_kg": "20",
                        "completed_at": started_at,
                    },
                    *(
                        {
                            "id": new_id(),
                            "set_type": "working",
                            "reps": reps,
                            "weight_kg": str(weight),
                            "completed_at": started_at,
                        }
                        for weight, reps in sets
                    ),
                ],
            }
        ],
    }
    response = client.put(f"/v1/workouts/{new_id()}", json=body, headers=auth_headers(email))
    assert response.status_code == 200, response.text


def night(client, day, minutes, hrv=None, email=EMAIL):
    body = {"sleep_minutes": minutes, "hrv_sdnn_ms": hrv}
    assert (
        client.put(f"/v1/readiness/{day}", json=body, headers=auth_headers(email)).status_code
        == 200
    )


def turn_on(client, email=EMAIL, language="en"):
    """Gives the account the coach and turns it on in the app."""
    enable_coach(client, email)
    settings = {"enabled": True, "language": language}
    response = client.put("/v1/coach/settings", json=settings, headers=auth_headers(email))
    assert response.json() == settings


def week_input(email=EMAIL):
    with TestingSessionLocal() as db:
        user = db.scalar(select(User).where(User.email == email))
        return weekly.build_input(db, user, WEEK)


def test_the_week_is_the_last_full_one_before_today():
    assert weekly.week_to_summarize(date(2026, 10, 26)) == WEEK  # Monday
    assert weekly.week_to_summarize(date(2026, 10, 27)) == WEEK  # Tuesday
    assert weekly.week_to_summarize(date(2026, 10, 25)) == date(2026, 10, 12)  # Sunday
    assert weekly.zone("Not/AZone") == timezone.utc


def test_the_weeks_numbers_are_computed_from_synced_workouts(client):
    # Bench: the same 60 kg × 8 four times, so it has stalled.
    for day in ("2026-10-01", "2026-10-06", "2026-10-12", "2026-10-20"):
        log(client, f"{day}T18:00:00-04:00", [(60, 8), (60, 8), (60, 8)])
    # Squat: heavier than ever on Sunday night, which is Monday in UTC.
    log(client, "2026-10-08T18:00:00-04:00", [(100, 5)], SQUAT)
    log(client, "2026-10-25T23:30:00-04:00", [(105, 5), (105, 4)], SQUAT)
    # Monday morning belongs to the next week.
    log(client, "2026-10-26T08:00:00-04:00", [(200, 1)], SQUAT)
    # A first time and an assisted exercise set no records.
    log(client, "2026-10-21T18:00:00-04:00", [(30, 8)], ASSISTED)

    week = week_input()
    assert (week.week_start, week.week_end, week.workouts) == ("2026-10-19", "2026-10-25", 3)
    assert {m.muscle: m.sets for m in week.sets_per_muscle} == {
        "chest": 3,
        "lats": 1,
        "quads": 2,
        "glutes": 2,
        "front_delts": 1.5,
        "triceps": 1.5,
        "adductors": 1,
        "lower_back": 1,
        "biceps": 0.5,
        "upper_back": 0.5,
    }
    assert week.sets_per_muscle[0].muscle == "chest"  # most sets first
    ((record),) = week.records
    assert (record.name, record.kind, record.weight_kg, record.reps) == (
        "Back squat",
        "heaviest",
        105,
        5,
    )
    assert week.stalled == ["Barbell bench press"]
    assert week.readiness.nights == 0 and week.readiness.sleep_minutes is None
    assert not week.deload_suggested
    assert (week.language, week.unit) == ("en", "kg")


def test_a_better_estimate_is_a_record_and_language_and_unit_follow_the_app(client):
    log(client, "2026-10-12T18:00:00-04:00", [(80, 5)])
    log(client, "2026-10-20T18:00:00-04:00", [(80, 8), (70, 12)])
    turn_on(client, language="zh")
    client.put(
        "/v1/profile",
        json={"unit_system": "imperial", "goal": "strength", "experience_level": "beginner"},
        headers=auth_headers(EMAIL),
    )

    week = week_input()
    ((record),) = week.records
    assert (record.name, record.kind, record.weight_kg, record.reps) == (
        "杠铃卧推",
        "estimated_1rm",
        80,
        8,
    )
    assert (week.language, week.unit, week.goal, week.experience) == (
        "zh",
        "lb",
        "strength",
        "beginner",
    )


def test_short_nights_against_the_usual_can_suggest_a_lighter_week(client):
    log(client, "2026-10-20T18:00:00-04:00", [(60, 8)])
    for day in range(1, 19):  # the usual: 7 h 30 min, HRV 50
        night(client, f"2026-10-{day:02d}", 450, hrv=50)
    for day in (19, 20, 21, 22):  # four nights of 6 h 20 min: an hour below usual
        night(client, f"2026-10-{day}", 380, hrv=40)
    night(client, "2026-10-23", 440)

    readiness = week_input().readiness
    assert readiness.nights == 5 and readiness.short_nights == 4
    assert (readiness.sleep_minutes.value, readiness.sleep_minutes.usual) == (392, 450)
    assert (readiness.hrv_ms.value, readiness.hrv_ms.usual) == (40, 50)
    assert week_input().deload_suggested


def test_low_hrv_alone_or_a_single_stall_suggests_no_lighter_week():
    calm = weekly.WeekReadiness(nights=7, short_nights=1)
    assert not weekly.deload_suggested(1, calm)
    assert weekly.deload_suggested(weekly.DELOAD_STALLS, calm)


def test_a_week_without_training_has_no_summary(client):
    log(client, "2026-10-12T18:00:00-04:00", [(60, 8)])
    assert week_input() is None


# The job and the worker


@pytest.fixture
def started():
    return []


def start_job(started):
    with TestingSessionLocal() as db:
        return coach_handler.start_weekly_summaries(db, NOW, started.append)


def run(summary_id, model):
    with TestingSessionLocal() as db:
        return coach_handler.run_weekly_summary(db, summary_id, model)


def test_the_job_writes_one_summary_per_coach_user_and_week(client, started):
    log(client, "2026-10-20T18:00:00-04:00", [(60, 8)])
    turn_on(client)
    # Without the coach, without training last week, or with the coach turned off in
    # the app, there is no summary.
    log(client, "2026-10-20T18:00:00-04:00", [(60, 8)], email="free@example.com")
    log(client, "2026-10-01T18:00:00-04:00", [(60, 8)], email="resting@example.com")
    turn_on(client, "resting@example.com")
    turn_on(client, "new@example.com")
    log(client, "2026-10-20T18:00:00-04:00", [(60, 8)], email="off@example.com")
    turn_on(client, "off@example.com")
    off = {"enabled": False, "language": "en"}
    client.put("/v1/coach/settings", json=off, headers=auth_headers("off@example.com"))
    # Turning it on works without access too, but without access there is no summary.
    on = {"enabled": True, "language": "en"}
    assert (
        client.put("/v1/coach/settings", json=on, headers=auth_headers("free@example.com")).json()
        == on
    )

    assert start_job(started) == {
        "started": 1,
        "existing": 0,
        "no_training": 2,
        "no_access": 1,
        "failed": 0,
    }
    (summary_id,) = started
    # A retried job doesn't write or pay twice.
    assert start_job(started) == {
        "started": 0,
        "existing": 1,
        "no_training": 2,
        "no_access": 1,
        "failed": 0,
    }
    assert len(started) == 1

    pending = client.get("/v1/sync", headers=auth_headers(EMAIL)).json()
    since = pending["change_seq"]
    ((summary),) = pending["weekly_summaries"]
    assert (summary["status"], summary["week_start"], summary["output"]) == (
        "pending",
        "2026-10-19",
        None,
    )

    model = FakeWeeklyModel()
    assert run(summary_id, model) == "ready"
    assert run(summary_id, model) == "skipped"  # done once
    system, _, schema = model.requests[0]
    assert "# Weekly summary" in system and set(schema["required"]) == {
        "summary",
        "suggestions",
        "deload",
    }

    changes = client.get(f"/v1/sync?since={since}", headers=auth_headers(EMAIL)).json()
    ((ready),) = changes["weekly_summaries"]
    assert ready["status"] == "ready" and ready["error"] is None
    assert ready["output"]["summary"].startswith("You trained 1 times")
    assert ready["output"]["suggestions"] == ["Keep the same plan."]
    assert ready["output"]["deload"] is False
    with TestingSessionLocal() as db:
        stored = db.get(WeeklySummary, summary_id)
        assert (stored.input_tokens, stored.output_tokens) == (1200, 250)
    # Another account sees none of it.
    other = client.get("/v1/sync", headers=auth_headers("free@example.com")).json()
    assert other["weekly_summaries"] == []


@pytest.mark.parametrize(
    ("model", "error"),
    [
        (FakeWeeklyModel(answer=lambda _: "not json"), "invalid_answer"),
        # A lighter week the rules didn't suggest is rejected, not shown.
        (FakeWeeklyModel(deload=True), "invalid_answer"),
        (SimpleNamespace(name="broken", complete=lambda *_: 1 / 0), "unavailable"),
    ],
)
def test_a_failed_summary_says_why(client, started, model, error, capsys):
    log(client, "2026-10-20T18:00:00-04:00", [(60, 8)])
    turn_on(client)
    start_job(started)
    assert run(started[0], model) == "failed"
    ((failed),) = client.get("/v1/sync", headers=auth_headers(EMAIL)).json()["weekly_summaries"]
    assert (failed["status"], failed["error"], failed["output"]) == ("failed", error, None)
    assert str(started[0]) in capsys.readouterr().out


def test_a_run_that_cant_start_fails_and_one_users_error_doesnt_stop_the_others(
    client, monkeypatch, capsys
):
    log(client, "2026-10-20T18:00:00-04:00", [(60, 8)])
    log(client, "2026-10-20T18:00:00-04:00", [(60, 8)], email="second@example.com")
    turn_on(client)
    turn_on(client, "second@example.com")

    def throttled(summary_id):
        raise RuntimeError("throttled")

    with TestingSessionLocal() as db:
        assert coach_handler.start_weekly_summaries(db, NOW, throttled)["failed"] == 2
    ((failed),) = client.get("/v1/sync", headers=auth_headers(EMAIL)).json()["weekly_summaries"]
    assert (failed["status"], failed["error"]) == ("failed", "unavailable")

    real = weekly.build_input
    monkeypatch.setattr(weekly, "week_to_summarize", lambda today: date(2026, 10, 12))
    monkeypatch.setattr(
        weekly,
        "build_input",
        lambda db, user, week: (1 / 0) if user.email == EMAIL else real(db, user, week),
    )
    log(client, "2026-10-13T18:00:00-04:00", [(60, 8)], email="second@example.com")
    started = []
    assert start_job(started) == {
        "started": 1,
        "existing": 0,
        "no_training": 0,
        "no_access": 0,
        "failed": 1,
    }
    assert "ZeroDivisionError" in capsys.readouterr().out


def test_an_account_deleted_during_the_run_is_skipped_and_its_summaries_deleted(client, started):
    log(client, "2026-10-20T18:00:00-04:00", [(60, 8)])
    turn_on(client)
    start_job(started)

    class DeletesTheAccount(FakeWeeklyModel):
        def complete(self, system, user, schema):
            client.delete("/v1/me", headers=auth_headers(EMAIL))
            return super().complete(system, user, schema)

    assert run(started[0], DeletesTheAccount()) == "skipped"
    with TestingSessionLocal() as db:
        assert db.scalars(select(WeeklySummary)).all() == []


def test_a_user_deleted_while_the_job_runs_is_left_out(client, started):
    with TestingSessionLocal() as db:
        assert coach_handler.start_weekly_summary(db, 12345, NOW, started.append) == "no_training"


def test_the_lambda_handler_runs_the_job_and_each_summary(client, monkeypatch, capsys):
    log(client, "2026-10-20T18:00:00-04:00", [(60, 8)])
    turn_on(client)
    invoked = []
    monkeypatch.setattr(coach_handler, "load_ssm_parameters", lambda *args: None)
    monkeypatch.setattr(coach_handler, "invoke_self", invoked.append)
    monkeypatch.setattr("database.SessionLocal", TestingSessionLocal)
    monkeypatch.setattr("models.utcnow", lambda: NOW)
    monkeypatch.setattr("coach.providers.model", lambda spec: FakeWeeklyModel())

    counts = coach_handler.handler({"job": "weekly_summaries"}, None)
    assert counts["started"] == 1
    (summary_id,) = invoked
    result = coach_handler.handler({"weekly_summary_id": str(summary_id)}, None)
    assert result == {"status": "ready"}
    lines = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    assert lines == [
        {"job": "weekly_summaries", **counts},
        # The tokens feed the same metric filters as recommendations.
        {
            "weekly_summary_id": str(summary_id),
            "status": "ready",
            "input_tokens": 1200,
            "output_tokens": 250,
        },
    ]


def test_the_job_starts_this_function_again_without_waiting(monkeypatch):
    calls = []
    fake_boto3 = SimpleNamespace(
        client=lambda service: SimpleNamespace(invoke=lambda **kwargs: calls.append(kwargs))
    )
    monkeypatch.setitem(sys.modules, "boto3", fake_boto3)
    monkeypatch.setenv("AWS_LAMBDA_FUNCTION_NAME", "trainwise-coach-prod")
    summary_id = uuid.uuid4()
    coach_handler.invoke_self(summary_id)
    ((kwargs),) = calls
    assert kwargs["FunctionName"] == "trainwise-coach-prod"
    assert kwargs["InvocationType"] == "Event"
    assert json.loads(kwargs["Payload"]) == {"weekly_summary_id": str(summary_id)}


def test_a_summary_is_cancelled_when_the_coach_was_turned_off_meanwhile(client, started):
    log(client, "2026-10-20T18:00:00-04:00", [(60, 8)])
    turn_on(client)
    start_job(started)
    off = {"enabled": False, "language": "en"}
    client.put("/v1/coach/settings", json=off, headers=auth_headers(EMAIL))

    model = FakeWeeklyModel()
    assert run(started[0], model) == "cancelled"
    assert model.requests == []  # nothing was sent
    ((cancelled),) = client.get("/v1/sync", headers=auth_headers(EMAIL)).json()["weekly_summaries"]
    assert (cancelled["status"], cancelled["error"]) == ("failed", "cancelled")


def test_a_summary_left_pending_is_started_again(client, started):
    log(client, "2026-10-20T18:00:00-04:00", [(60, 8)])
    turn_on(client)
    start_job(started)
    with TestingSessionLocal() as db:
        db.get(WeeklySummary, started[0]).updated_at = utcnow() - timedelta(minutes=10)
        db.commit()
    assert start_job(started)["started"] == 1
    assert started == [started[0], started[0]]


def test_the_job_hands_over_to_a_new_run_before_its_time_runs_out(client, monkeypatch, capsys):
    for email in (EMAIL, "second@example.com"):
        log(client, "2026-10-20T18:00:00-04:00", [(60, 8)], email=email)
        turn_on(client, email)
    with TestingSessionLocal() as db:
        first, second = db.scalars(select(User.id).order_by(User.id)).all()

    budget = iter([60_000, 1_000])
    started = []
    with TestingSessionLocal() as db:
        counts = coach_handler.start_weekly_summaries(
            db, NOW, started.append, time_left_ms=lambda: next(budget)
        )
    assert counts == {
        "started": 1,
        "existing": 0,
        "no_training": 0,
        "no_access": 0,
        "failed": 0,
        "next_user_id": second,
    }

    invoked = []
    monkeypatch.setattr(coach_handler, "load_ssm_parameters", lambda *args: None)
    monkeypatch.setattr(
        coach_handler, "invoke_self", lambda *args, **kwargs: invoked.append((args, kwargs))
    )
    monkeypatch.setattr("database.SessionLocal", TestingSessionLocal)
    monkeypatch.setattr("models.utcnow", lambda: NOW)
    context = SimpleNamespace(get_remaining_time_in_millis=lambda: 1_000)
    coach_handler.handler({"job": "weekly_summaries"}, context)
    assert invoked == [((None,), {"after_user_id": first - 1})]
    # The new run goes on from there and only starts the second user.
    context = SimpleNamespace(get_remaining_time_in_millis=lambda: 60_000)
    result = coach_handler.handler({"job": "weekly_summaries", "after_user_id": first}, context)
    assert result["started"] == 1 and "next_user_id" not in result


def test_the_job_continues_by_starting_this_function_again(monkeypatch):
    calls = []
    fake_boto3 = SimpleNamespace(
        client=lambda service: SimpleNamespace(invoke=lambda **kwargs: calls.append(kwargs))
    )
    monkeypatch.setitem(sys.modules, "boto3", fake_boto3)
    monkeypatch.setenv("AWS_LAMBDA_FUNCTION_NAME", "trainwise-coach-prod")
    coach_handler.invoke_self(None, after_user_id=41)
    assert json.loads(calls[0]["Payload"]) == {"job": "weekly_summaries", "after_user_id": 41}
