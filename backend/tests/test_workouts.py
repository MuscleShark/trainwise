from decimal import Decimal

from conftest import TestingSessionLocal, auth_headers
from helpers import BENCH, SQUAT, new_id, workout_body

from models import WorkoutSet


def test_put_creates_a_workout_with_exercises_and_sets(client):
    headers = auth_headers("lifter@example.com")
    workout_id = new_id()

    response = client.put(f"/v1/workouts/{workout_id}", json=workout_body(), headers=headers)

    assert response.status_code == 200
    workout = response.json()
    assert workout["id"] == workout_id
    assert workout["exercises"][0]["exercise_id"] == BENCH
    assert [s["reps"] for s in workout["exercises"][0]["sets"]] == [8, 8, 8]
    assert workout["deleted_at"] is None
    assert workout["change_seq"] == 1
    assert client.get(f"/v1/workouts/{workout_id}", headers=headers).json() == workout


def test_put_replaces_the_whole_workout(client):
    headers = auth_headers("lifter@example.com")
    workout_id = new_id()
    client.put(f"/v1/workouts/{workout_id}", json=workout_body(sets=3), headers=headers)

    response = client.put(
        f"/v1/workouts/{workout_id}",
        json=workout_body(exercise=SQUAT, sets=1, title="Leg day"),
        headers=headers,
    )

    workout = response.json()
    assert workout["title"] == "Leg day"
    assert len(workout["exercises"]) == 1
    assert workout["exercises"][0]["exercise_id"] == SQUAT
    assert len(workout["exercises"][0]["sets"]) == 1


def test_sending_the_same_workout_twice_gives_the_same_result(client):
    headers = auth_headers("retry@example.com")
    workout_id = new_id()
    body = workout_body()

    first = client.put(f"/v1/workouts/{workout_id}", json=body, headers=headers).json()
    second = client.put(f"/v1/workouts/{workout_id}", json=body, headers=headers).json()

    assert first["exercises"] == second["exercises"]
    assert second["change_seq"] == first["change_seq"] + 1


def test_pounds_round_trip_exactly(client):
    # 45 lb = 20.412 kg; the app converts back to 45.0 lb.
    headers = auth_headers("imperial@example.com")
    workout_id = new_id()
    client.put(f"/v1/workouts/{workout_id}", json=workout_body(weight="20.412"), headers=headers)

    weight = client.get(f"/v1/workouts/{workout_id}", headers=headers).json()["exercises"][0][
        "sets"
    ][0]["weight_kg"]
    assert weight == 20.412


def test_weights_sent_as_json_numbers_are_stored_exactly(client):
    # The iPhone app sends weights as doubles.
    headers = auth_headers("numbers@example.com")
    workout_id = new_id()
    response = client.put(
        f"/v1/workouts/{workout_id}", json=workout_body(weight=61.235), headers=headers
    )
    assert response.status_code == 200, response.text

    with TestingSessionLocal() as db:
        stored = {row.weight_kg for row in db.query(WorkoutSet)}
    assert stored == {Decimal("61.235")}
    assert response.json()["exercises"][0]["sets"][0]["weight_kg"] == 61.235


def test_unknown_exercise_is_rejected(client):
    response = client.put(
        f"/v1/workouts/{new_id()}",
        json=workout_body(exercise=new_id()),
        headers=auth_headers("a@example.com"),
    )
    assert response.status_code == 422
    assert response.json()["detail"].startswith("Unknown exercise")


def test_another_users_custom_exercise_cannot_be_used(client):
    exercise_id = new_id()
    client.put(
        f"/v1/exercises/{exercise_id}",
        json={
            "name_en": "My machine",
            "equipment": "machine",
            "load_type": "total",
            "primary_muscles": ["chest"],
        },
        headers=auth_headers("owner@example.com"),
    )

    response = client.put(
        f"/v1/workouts/{new_id()}",
        json=workout_body(exercise=exercise_id),
        headers=auth_headers("other@example.com"),
    )
    assert response.status_code == 422


def test_workouts_are_private(client):
    workout_id = new_id()
    client.put(
        f"/v1/workouts/{workout_id}", json=workout_body(), headers=auth_headers("a@example.com")
    )
    other = auth_headers("b@example.com")

    assert client.get(f"/v1/workouts/{workout_id}", headers=other).status_code == 404
    assert client.delete(f"/v1/workouts/{workout_id}", headers=other).status_code == 404
    assert client.get("/v1/workouts", headers=other).json()["items"] == []
    # The id belongs to someone else, so it cannot be taken over.
    response = client.put(f"/v1/workouts/{workout_id}", json=workout_body(), headers=other)
    assert response.status_code == 409


def test_a_set_id_used_by_another_workout_is_a_conflict(client):
    headers = auth_headers("a@example.com")
    body = workout_body()
    client.put(f"/v1/workouts/{new_id()}", json=body, headers=headers)

    response = client.put(f"/v1/workouts/{new_id()}", json=body, headers=headers)
    assert response.status_code == 409


def test_deleted_workouts_are_hidden(client):
    headers = auth_headers("a@example.com")
    workout_id = new_id()
    client.put(f"/v1/workouts/{workout_id}", json=workout_body(), headers=headers)

    assert client.delete(f"/v1/workouts/{workout_id}", headers=headers).status_code == 204

    assert client.get(f"/v1/workouts/{workout_id}", headers=headers).status_code == 404
    assert client.get("/v1/workouts", headers=headers).json()["items"] == []


def test_list_is_newest_first_and_paginated(client):
    headers = auth_headers("a@example.com")
    for day in range(1, 6):
        client.put(
            f"/v1/workouts/{new_id()}",
            json=workout_body(started_at=f"2026-10-0{day}T10:00:00Z", ended_at=None),
            headers=headers,
        )

    first = client.get("/v1/workouts?limit=2", headers=headers).json()
    assert [w["started_at"][:10] for w in first["items"]] == ["2026-10-05", "2026-10-04"]

    second = client.get(
        "/v1/workouts", params={"limit": 2, "before": first["next_before"]}, headers=headers
    ).json()
    assert [w["started_at"][:10] for w in second["items"]] == ["2026-10-03", "2026-10-02"]

    last = client.get(
        "/v1/workouts", params={"limit": 2, "before": second["next_before"]}, headers=headers
    ).json()
    assert [w["started_at"][:10] for w in last["items"]] == ["2026-10-01"]
    assert last["next_before"] is None

    in_range = client.get(
        "/v1/workouts",
        params={"from": "2026-10-02T00:00:00Z", "to": "2026-10-04T00:00:00Z"},
        headers=headers,
    ).json()
    assert len(in_range["items"]) == 2


def test_invalid_workouts_are_rejected(client):
    headers = auth_headers("a@example.com")
    cases = [
        workout_body(time_zone="Mars/Olympus"),
        workout_body(started_at="2026-10-20T18:00:00"),  # no time zone offset
        workout_body(weight="-5"),
        workout_body(title=""),
        workout_body(ended_at="2026-10-20T17:00:00+02:00"),  # ends before it starts
    ]
    duplicate_ids = workout_body()
    duplicate_ids["exercises"][0]["sets"][1]["id"] = duplicate_ids["exercises"][0]["sets"][0]["id"]
    cases.append(duplicate_ids)

    for body in cases:
        assert client.put(f"/v1/workouts/{new_id()}", json=body, headers=headers).status_code == 422


def test_workouts_require_sign_in(client):
    workout_id = new_id()
    assert client.get("/v1/workouts").status_code == 401
    assert client.put(f"/v1/workouts/{workout_id}", json=workout_body()).status_code == 401
    assert client.delete(f"/v1/workouts/{workout_id}").status_code == 401
