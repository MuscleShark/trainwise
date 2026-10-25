from conftest import auth_headers
from helpers import BENCH, new_id

from catalog import BUILTIN_EXERCISES

MACHINE = {
    "name_en": "Hammer Strength chest press",
    "name_zh": "Hammer Strength 推胸机",
    "equipment": "machine",
    "load_type": "per_side",
    "primary_muscles": ["chest"],
    "secondary_muscles": ["triceps"],
    "base_exercise_id": BENCH,
    "aliases": ["HS press"],
}


def test_list_contains_the_catalog_and_own_exercises(client):
    headers = auth_headers("me@example.com")
    exercise_id = new_id()
    client.put(f"/v1/exercises/{exercise_id}", json=MACHINE, headers=headers)

    exercises = client.get("/v1/exercises", headers=headers).json()

    assert len(exercises) == len(BUILTIN_EXERCISES) + 1
    custom = [e for e in exercises if e["is_custom"]]
    assert [e["id"] for e in custom] == [exercise_id]
    assert custom[0]["aliases"] == ["HS press"]
    bench = next(e for e in exercises if e["id"] == BENCH)
    assert bench["name_zh"] == "杠铃卧推"
    assert bench["is_custom"] is False


def test_custom_exercises_are_private(client):
    client.put(f"/v1/exercises/{new_id()}", json=MACHINE, headers=auth_headers("a@example.com"))
    exercises = client.get("/v1/exercises", headers=auth_headers("b@example.com")).json()
    assert not any(e["is_custom"] for e in exercises)


def test_built_in_exercises_cannot_be_changed(client):
    headers = auth_headers("me@example.com")
    assert client.put(f"/v1/exercises/{BENCH}", json=MACHINE, headers=headers).status_code == 403
    assert client.delete(f"/v1/exercises/{BENCH}", headers=headers).status_code == 404


def test_another_users_id_is_a_conflict(client):
    exercise_id = new_id()
    client.put(f"/v1/exercises/{exercise_id}", json=MACHINE, headers=auth_headers("a@example.com"))
    response = client.put(
        f"/v1/exercises/{exercise_id}", json=MACHINE, headers=auth_headers("b@example.com")
    )
    assert response.status_code == 409


def test_base_exercise_must_be_built_in(client):
    headers = auth_headers("me@example.com")
    first = new_id()
    client.put(f"/v1/exercises/{first}", json=MACHINE, headers=headers)

    response = client.put(
        f"/v1/exercises/{new_id()}", json={**MACHINE, "base_exercise_id": first}, headers=headers
    )
    assert response.status_code == 422


def test_invalid_exercises_are_rejected(client):
    headers = auth_headers("me@example.com")
    for body in (
        {**MACHINE, "primary_muscles": []},
        {**MACHINE, "primary_muscles": ["pecs"]},
        {**MACHINE, "equipment": "rock"},
        {**MACHINE, "load_type": "half"},
        {**MACHINE, "aliases": [""]},
        {**MACHINE, "aliases": ["x"] * 11},
    ):
        assert (
            client.put(f"/v1/exercises/{new_id()}", json=body, headers=headers).status_code == 422
        )


def test_deleted_exercise_leaves_the_list(client):
    headers = auth_headers("me@example.com")
    exercise_id = new_id()
    client.put(f"/v1/exercises/{exercise_id}", json=MACHINE, headers=headers)

    assert client.delete(f"/v1/exercises/{exercise_id}", headers=headers).status_code == 204

    exercises = client.get("/v1/exercises", headers=headers).json()
    assert exercise_id not in [e["id"] for e in exercises]


def test_exercises_require_sign_in(client):
    assert client.get("/v1/exercises").status_code == 401
