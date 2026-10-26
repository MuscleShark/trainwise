"""The iPhone app's whole journey through the API, end to end.

The other test files check each feature on its own. These walk one account through all
of them the way the app does (sign in, log, sync, subscribe, ask the coach, get the
weekly summary, delete the account), so a feature that breaks another shows up here.
CI runs them on SQLite and on PostgreSQL; the concurrency tests need PostgreSQL's row
locks and only run there.
"""

import uuid
from concurrent.futures import ThreadPoolExecutor

from conftest import TestingSessionLocal, auth_headers, postgres_only
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from test_coach import FakeModel
from test_coach_api import BODY
from test_profiles import PROFILE
from test_subscription import put as subscribe
from test_subscription import store  # noqa: F401 (fixture)
from test_weekly import NOW, FakeWeeklyModel, log, night

import coach_handler
from main import app
from models import (
    DailyReadiness,
    Profile,
    Recommendation,
    Subscription,
    User,
    WeeklySummary,
    Workout,
)
from routers import coach as coach_router

EMAIL = "journey@example.com"


def headers():
    return auth_headers(EMAIL, "user_journey")


def sync_all(client, since=0, limit=2):
    """Every change after `since`, read in small pages as the app does."""
    pages = []
    while True:
        response = client.get(f"/v1/sync?since={since}&limit={limit}", headers=headers())
        assert response.status_code == 200, response.text
        page = response.json()
        pages.append(page)
        assert page["change_seq"] >= since
        since = page["change_seq"]
        if not page["has_more"]:
            return since, pages


def rows(page_list, key):
    return [item for page in page_list for item in page[key]]


def test_one_account_from_sign_in_to_deletion(client, store):  # noqa: F811
    started = []
    app.dependency_overrides[coach_router.get_coach_starter] = lambda: started.append
    try:
        # Sign in, set up the profile, log a week of training and two nights.
        assert client.get("/v1/me", headers=headers()).status_code == 200
        assert client.put("/v1/profile", json=PROFILE, headers=headers()).status_code == 200
        log(client, "2026-10-20T18:00:00-04:00", [(60, 8), (60, 8)], email=EMAIL)
        log(client, "2026-10-23T18:00:00-04:00", [(62.5, 6), (62.5, 6)], email=EMAIL)
        night(client, "2026-10-21", 410, hrv=48, email=EMAIL)
        night(client, "2026-10-22", 455, hrv=52, email=EMAIL)

        # A second phone syncs from zero in small pages and gets each change once.
        cursor, pages = sync_all(client)
        assert sum(1 for page in pages if page["profile"]) == 1
        assert len(rows(pages, "workouts")) == 2
        assert sorted(day["date"] for day in rows(pages, "readiness")) == [
            "2026-10-21",
            "2026-10-22",
        ]
        assert rows(pages, "recommendations") == [] and rows(pages, "weekly_summaries") == []

        # Without a subscription the coach is refused; a trial purchase opens it.
        ask = f"/v1/recommendations/{uuid.uuid4()}"
        assert client.put(ask, json=BODY, headers=headers()).status_code == 402
        assert subscribe(client, store.transaction(), email=EMAIL).json()["coach_access"]
        settings = {"enabled": True, "language": "en"}
        assert client.put("/v1/coach/settings", json=settings, headers=headers()).status_code == 200

        # Ask the coach; the worker answers; the answer arrives through sync.
        pending = client.put(ask, json=BODY, headers=headers()).json()
        assert pending["status"] == "pending" and started == [uuid.UUID(pending["id"])]
        with TestingSessionLocal() as db:
            assert coach_handler.run(db, uuid.UUID(pending["id"]), FakeModel()) == "ready"
        cursor, pages = sync_all(client, cursor)
        (advice,) = rows(pages, "recommendations")
        assert advice["status"] == "ready" and advice["output"]["exercises"]

        # Monday: the weekly job writes last week's summary, which arrives the same way.
        weekly_started = []
        with TestingSessionLocal() as db:
            counts = coach_handler.start_weekly_summaries(db, NOW, weekly_started.append)
        assert counts["started"] == 1
        with TestingSessionLocal() as db:
            assert (
                coach_handler.run_weekly_summary(db, weekly_started[0], FakeWeeklyModel())
                == "ready"
            )
        cursor, pages = sync_all(client, cursor)
        (summary,) = rows(pages, "weekly_summaries")
        assert summary["status"] == "ready" and "trained 2 times" in summary["output"]["summary"]

        # Deleting the account removes every row it had. The subscription is only
        # unlinked (no personal data in it), so its purchase can't be claimed again.
        assert client.delete("/v1/me", headers=headers()).status_code == 204
        with TestingSessionLocal() as db:
            assert db.scalar(select(User).where(User.email == EMAIL)) is None
            for model in (Profile, Workout, DailyReadiness, Recommendation, WeeklySummary):
                assert db.scalar(select(func.count()).select_from(model)) == 0, model.__name__
            (subscription,) = db.scalars(select(Subscription))
            assert subscription.user_id is None

        # Signing in again starts an empty account.
        assert client.get("/v1/me", headers=headers()).status_code == 200
        _, pages = sync_all(client)
        assert not any(page["workouts"] or page["profile"] for page in pages)
    finally:
        app.dependency_overrides.pop(coach_router.get_coach_starter, None)


# PostgreSQL only: these rely on the users-row lock described in sync.py.


def parallel(count, call):
    with ThreadPoolExecutor(max_workers=count) as pool:
        return list(pool.map(lambda _: call(), range(count)))


@postgres_only
def test_concurrent_writes_each_take_their_own_change_seq(client):
    client.get("/v1/me", headers=headers())
    with TestClient(app) as other:
        parallel(8, lambda: log(other, "2026-10-20T18:00:00-04:00", [(60, 8)], email=EMAIL))
    _, pages = sync_all(client, limit=3)
    workouts = rows(pages, "workouts")
    seqs = [w["change_seq"] for w in workouts]
    assert len(workouts) == 8 and len(set(seqs)) == 8


@postgres_only
def test_concurrent_coach_requests_stay_within_the_daily_limit(client, store):  # noqa: F811
    app.dependency_overrides[coach_router.get_coach_starter] = lambda: lambda _id: None
    try:
        client.get("/v1/me", headers=headers())
        assert subscribe(client, store.transaction(), email=EMAIL).status_code == 200
        with TestClient(app) as other:
            statuses = parallel(
                coach_router.DAILY_LIMIT + 4,
                lambda: (
                    other.put(
                        f"/v1/recommendations/{uuid.uuid4()}", json=BODY, headers=headers()
                    ).status_code
                ),
            )
    finally:
        app.dependency_overrides.pop(coach_router.get_coach_starter, None)
    assert statuses.count(200) == coach_router.DAILY_LIMIT
    assert statuses.count(429) == 4
    with TestingSessionLocal() as db:
        assert (
            db.scalar(select(func.count()).select_from(Recommendation)) == coach_router.DAILY_LIMIT
        )
