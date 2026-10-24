from conftest import TestingSessionLocal, auth_headers
from helpers import new_id, workout_body
from sqlalchemy import func, select

from catalog import BUILTIN_EXERCISES
from models import (
    BodyMeasurement,
    DailyReadiness,
    Exercise,
    Profile,
    Template,
    User,
    Workout,
    WorkoutSet,
)

MACHINE = {
    "name_en": "My machine",
    "equipment": "machine",
    "load_type": "total",
    "primary_muscles": ["chest"],
}


def fill_account(client, headers):
    exercise_id = new_id()
    client.put("/v1/profile", json={"goal": "strength"}, headers=headers)
    client.put(f"/v1/exercises/{exercise_id}", json=MACHINE, headers=headers)
    client.put(f"/v1/workouts/{new_id()}", json=workout_body(exercise=exercise_id), headers=headers)
    client.put(
        f"/v1/templates/{new_id()}",
        json={
            "name_en": "Mine",
            "days": [
                {
                    "id": new_id(),
                    "name": "A",
                    "exercises": [{"id": new_id(), "exercise_id": exercise_id, "sets": []}],
                }
            ],
        },
        headers=headers,
    )
    client.put(
        f"/v1/body-measurements/{new_id()}",
        json={"measured_at": "2026-10-20T07:30:00Z", "kind": "weight", "value": "80"},
        headers=headers,
    )
    client.put("/v1/readiness/2026-10-20", json={"sleep_minutes": 420}, headers=headers)


def count(db, model) -> int:
    return db.scalar(select(func.count()).select_from(model))


def test_delete_account_removes_user_and_all_their_data(client):
    headers = auth_headers("leaving@example.com", "user_leaving")
    fill_account(client, headers)

    response = client.delete("/v1/me", headers=headers)

    assert response.status_code == 204
    assert response.content == b""
    with TestingSessionLocal() as db:
        for model in (
            User,
            Profile,
            Workout,
            WorkoutSet,
            Template,
            BodyMeasurement,
            DailyReadiness,
        ):
            assert count(db, model) == 0, model.__name__
        # Only the built-in catalog is left.
        assert count(db, Exercise) == len(BUILTIN_EXERCISES)


def test_delete_account_keeps_other_users_data(client):
    staying = auth_headers("staying@example.com", "user_staying")
    fill_account(client, staying)
    leaving = auth_headers("leaving@example.com", "user_leaving")
    fill_account(client, leaving)

    assert client.delete("/v1/me", headers=leaving).status_code == 204

    data = client.get("/v1/sync", headers=staying).json()
    assert len(data["workouts"]) == 1
    assert len(data["exercises"]) == 1
    assert data["profile"]["goal"] == "strength"


def test_signing_in_after_deletion_starts_an_empty_account(client):
    # If the client could not delete the Clerk user, the same Clerk user may sign in
    # again. They get a fresh account with none of the deleted data.
    headers = auth_headers("again@example.com", "user_again")
    fill_account(client, headers)
    client.delete("/v1/me", headers=headers)

    headers = auth_headers("again@example.com", "user_again")
    assert client.get("/v1/me", headers=headers).status_code == 200
    data = client.get("/v1/sync", headers=headers).json()
    assert data["workouts"] == [] and data["profile"] is None


def test_delete_account_requires_sign_in(client):
    assert client.delete("/v1/me").status_code == 401
