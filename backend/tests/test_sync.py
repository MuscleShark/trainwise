from conftest import auth_headers
from helpers import new_id, workout_body

MACHINE = {
    "name_en": "My machine",
    "equipment": "machine",
    "load_type": "total",
    "primary_muscles": ["chest"],
}


def test_first_sync_returns_everything(client):
    headers = auth_headers("me@example.com")
    client.put("/v1/profile", json={"goal": "strength"}, headers=headers)
    client.put(f"/v1/exercises/{new_id()}", json=MACHINE, headers=headers)
    client.put(f"/v1/workouts/{new_id()}", json=workout_body(), headers=headers)
    client.put(
        f"/v1/body-measurements/{new_id()}",
        json={"measured_at": "2026-10-20T07:30:00Z", "kind": "weight", "value": "80"},
        headers=headers,
    )
    client.put("/v1/readiness/2026-10-20", json={"sleep_minutes": 420}, headers=headers)

    data = client.get("/v1/sync", headers=headers).json()

    assert data["change_seq"] == 5
    assert data["profile"]["goal"] == "strength"
    assert len(data["exercises"]) == 1
    assert len(data["workouts"]) == 1
    assert len(data["body_measurements"]) == 1
    assert len(data["readiness"]) == 1
    assert data["templates"] == []


def test_later_syncs_return_only_changes_including_deletions(client):
    headers = auth_headers("me@example.com")
    kept, removed = new_id(), new_id()
    client.put(f"/v1/workouts/{kept}", json=workout_body(), headers=headers)
    client.put(f"/v1/workouts/{removed}", json=workout_body(), headers=headers)
    since = client.get("/v1/sync", headers=headers).json()["change_seq"]

    client.delete(f"/v1/workouts/{removed}", headers=headers)
    data = client.get("/v1/sync", params={"since": since}, headers=headers).json()

    assert [w["id"] for w in data["workouts"]] == [removed]
    assert data["workouts"][0]["deleted_at"] is not None
    assert data["profile"] is None
    assert data["change_seq"] == since + 1

    nothing_new = client.get("/v1/sync", params={"since": data["change_seq"]}, headers=headers)
    assert nothing_new.json()["workouts"] == []


def test_sync_only_returns_the_users_own_records(client):
    client.put(f"/v1/workouts/{new_id()}", json=workout_body(), headers=auth_headers("a@x.com"))

    data = client.get("/v1/sync", headers=auth_headers("b@x.com")).json()

    assert data["change_seq"] == 0
    assert data["workouts"] == []


def test_sync_requires_sign_in(client):
    assert client.get("/v1/sync").status_code == 401
