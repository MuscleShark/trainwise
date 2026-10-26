import json
import sys
import uuid
from datetime import timedelta
from types import SimpleNamespace

import pytest
from conftest import TestingSessionLocal, auth_headers
from helpers import new_id
from sqlalchemy import select
from test_coach import FakeModel

import coach_handler
from coach.eval_cases import bench_increase, sleep
from coach.providers import RefusedError
from coach.schemas import CoachInput
from main import app
from models import Recommendation, User, utcnow
from routers import coach as coach_router

EMAIL = "lifter@example.com"
PLAN = CoachInput(readiness=sleep(300, 450), exercises=[bench_increase()]).model_dump(mode="json")
BODY = {"for_date": "2026-10-26", "input": PLAN}


def enable_coach(client, email=EMAIL):
    client.get("/v1/me", headers=auth_headers(email))
    with TestingSessionLocal() as db:
        db.scalar(select(User).where(User.email == email)).coach_enabled = True
        db.commit()


def request(client, recommendation_id=None, email=EMAIL):
    return client.put(
        f"/v1/recommendations/{recommendation_id or new_id()}",
        json=BODY,
        headers=auth_headers(email),
    )


def test_the_coach_needs_access(client, started):
    response = request(client)
    assert response.status_code == 402
    assert started == []


def test_a_request_is_saved_as_pending_and_starts_the_worker_once(client, started):
    enable_coach(client)
    recommendation_id = new_id()
    first = request(client, recommendation_id)
    assert first.status_code == 200
    assert first.json()["status"] == "pending" and first.json()["output"] is None
    assert started == [uuid.UUID(recommendation_id)]

    # A retry returns the same record without asking again.
    assert request(client, recommendation_id).json()["change_seq"] == first.json()["change_seq"]
    assert len(started) == 1
    # Another account can't take the id.
    enable_coach(client, "other@example.com")
    assert request(client, recommendation_id, email="other@example.com").status_code == 409


def test_requests_are_limited_per_day(client, started):
    enable_coach(client)
    for _ in range(coach_router.DAILY_LIMIT):
        assert request(client).status_code == 200
    assert request(client).status_code == 429


def test_the_input_is_validated(client, started):
    enable_coach(client)
    bad = {"for_date": "2026-10-26", "input": {**PLAN, "exercises": []}}
    response = client.put(f"/v1/recommendations/{new_id()}", json=bad, headers=auth_headers(EMAIL))
    assert response.status_code == 422


def run_worker(recommendation_id, model):
    with TestingSessionLocal() as db:
        return coach_handler.run(db, uuid.UUID(recommendation_id), model)


def test_the_worker_stores_the_advice_and_sync_delivers_it(client, started):
    enable_coach(client)
    recommendation_id = new_id()
    pending_seq = request(client, recommendation_id).json()["change_seq"]

    assert run_worker(recommendation_id, FakeModel({"bench": "hold_weight"})) == "ready"
    # Done once: a second run changes nothing.
    assert run_worker(recommendation_id, FakeModel()) == "skipped"

    changes = client.get(f"/v1/sync?since={pending_seq}", headers=auth_headers(EMAIL)).json()
    (advice,) = changes["recommendations"]
    assert advice["status"] == "ready" and advice["error"] is None
    assert advice["output"]["model"] == "fake:model"
    (bench,) = advice["output"]["exercises"]
    assert bench["action"] == "hold_weight"
    assert [s["weight_kg"] for s in bench["sets"]] == [60, 60, 60]
    with TestingSessionLocal() as db:
        stored = db.get(Recommendation, uuid.UUID(recommendation_id))
        assert (stored.input_tokens, stored.output_tokens) == (1000, 200)


@pytest.mark.parametrize(
    ("model", "error"),
    [
        (FakeModel(answer=lambda _: "not json"), "invalid_answer"),
        (SimpleNamespace(name="broken", complete=lambda *_: 1 / 0), "unavailable"),
    ],
)
def test_a_failed_request_says_why_and_keeps_the_rule_plan(client, started, model, error, capsys):
    enable_coach(client)
    recommendation_id = new_id()
    request(client, recommendation_id)
    assert run_worker(recommendation_id, model) == "failed"
    (failed,) = client.get("/v1/sync", headers=auth_headers(EMAIL)).json()["recommendations"]
    assert failed["status"] == "failed" and failed["output"] is None
    # The phone gets a fixed reason; the details only go to the logs.
    assert failed["error"] == error
    assert recommendation_id in capsys.readouterr().out


def test_a_refused_request_is_reported_as_declined(client, started):
    class Refusing(FakeModel):
        def complete(self, system, user, schema):
            raise RefusedError(self.name)

    enable_coach(client)
    recommendation_id = new_id()
    request(client, recommendation_id)
    assert run_worker(recommendation_id, Refusing()) == "failed"
    (failed,) = client.get("/v1/sync", headers=auth_headers(EMAIL)).json()["recommendations"]
    assert failed["error"] == "declined"


def test_only_one_run_works_on_a_request(client, started):
    enable_coach(client)
    recommendation_id = new_id()
    request(client, recommendation_id)
    with TestingSessionLocal() as db:
        db.get(Recommendation, uuid.UUID(recommendation_id)).status = "running"
        db.commit()
    # A duplicate invoke finds it already claimed and leaves it alone.
    assert run_worker(recommendation_id, FakeModel()) == "skipped"


def test_a_lost_request_is_marked_failed_when_asked_again(client, started):
    enable_coach(client)
    recommendation_id = new_id()
    request(client, recommendation_id)
    # Fresh: still pending.
    assert request(client, recommendation_id).json()["status"] == "pending"
    with TestingSessionLocal() as db:
        stale = db.get(Recommendation, uuid.UUID(recommendation_id))
        stale.status = "running"
        stale.updated_at = utcnow() - timedelta(minutes=3)
        db.commit()
    again = request(client, recommendation_id).json()
    assert (again["status"], again["error"]) == ("failed", "timed_out")


def test_a_worker_that_doesnt_start_fails_the_request(client):
    def broken(recommendation_id):
        raise RuntimeError("throttled")

    app.dependency_overrides[coach_router.get_coach_starter] = lambda: broken
    try:
        enable_coach(client)
        response = request(client)
    finally:
        app.dependency_overrides.pop(coach_router.get_coach_starter)
    assert response.status_code == 200
    assert (response.json()["status"], response.json()["error"]) == ("failed", "unavailable")


def test_an_account_deleted_during_the_run_is_skipped(client, started):
    enable_coach(client)
    recommendation_id = new_id()
    request(client, recommendation_id)

    class DeletesTheAccount(FakeModel):
        def complete(self, system, user, schema):
            client.delete("/v1/me", headers=auth_headers(EMAIL))
            return super().complete(system, user, schema)

    assert run_worker(recommendation_id, DeletesTheAccount()) == "skipped"


def test_deleting_the_account_deletes_its_recommendations(client, started):
    enable_coach(client)
    request(client)
    assert client.delete("/v1/me", headers=auth_headers(EMAIL)).status_code == 204
    with TestingSessionLocal() as db:
        assert db.scalars(select(Recommendation)).all() == []


def test_the_lambda_handler_reads_its_secrets_and_runs_the_default_model(
    client, started, monkeypatch, capsys
):
    enable_coach(client)
    recommendation_id = new_id()
    request(client, recommendation_id)
    loaded = []
    monkeypatch.setattr(coach_handler, "load_ssm_parameters", lambda *args: loaded.append(args))
    monkeypatch.setattr("database.SessionLocal", TestingSessionLocal)
    monkeypatch.setattr("coach.providers.model", lambda spec: FakeModel())
    monkeypatch.setenv("SSM_PARAMETER_PREFIX", "/trainwise/prod")

    result = coach_handler.handler({"recommendation_id": recommendation_id}, None)
    assert result == {"status": "ready"}
    assert loaded == [("/trainwise/prod", ("DATABASE_URL", "ANTHROPIC_API_KEY"))]
    # The log line the CloudWatch metric filters read.
    line = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert line["status"] == "ready"
    assert (line["input_tokens"], line["output_tokens"]) == (1000, 200)


def test_the_api_starts_the_worker_lambda_without_waiting(monkeypatch):
    calls = []
    fake_boto3 = SimpleNamespace(
        client=lambda service: SimpleNamespace(
            invoke=lambda **kwargs: calls.append((service, kwargs))
        )
    )
    monkeypatch.setitem(sys.modules, "boto3", fake_boto3)
    recommendation_id = uuid.uuid4()

    monkeypatch.delenv("COACH_FUNCTION_NAME", raising=False)
    coach_router.invoke_coach_worker(recommendation_id)
    assert calls == []

    monkeypatch.setenv("COACH_FUNCTION_NAME", "trainwise-coach-prod")
    coach_router.invoke_coach_worker(recommendation_id)
    ((service, kwargs),) = calls
    assert service == "lambda"
    assert kwargs["FunctionName"] == "trainwise-coach-prod"
    assert kwargs["InvocationType"] == "Event"
    assert json.loads(kwargs["Payload"]) == {"recommendation_id": str(recommendation_id)}
