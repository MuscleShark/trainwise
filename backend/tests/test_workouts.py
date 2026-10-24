from conftest import auth_headers


def test_workout_crud(client):
    headers = auth_headers("workout-owner@example.com")
    workout_data = {
        "workout_date": "2026-09-23",
        "workout_type": "Strength",
        "duration_minutes": 60,
        "notes": "Upper-body session",
    }

    create_response = client.post(
        "/v1/workouts",
        json=workout_data,
        headers=headers,
    )
    assert create_response.status_code == 200
    workout = create_response.json()
    workout_id = workout["id"]
    assert workout["workout_type"] == "Strength"

    list_response = client.get("/v1/workouts", headers=headers)
    assert list_response.status_code == 200
    assert len(list_response.json()) == 1

    update_response = client.put(
        f"/v1/workouts/{workout_id}",
        json={
            **workout_data,
            "duration_minutes": 75,
            "notes": "Added accessory work",
        },
        headers=headers,
    )
    assert update_response.status_code == 200
    assert update_response.json()["duration_minutes"] == 75

    delete_response = client.delete(
        f"/v1/workouts/{workout_id}",
        headers=headers,
    )
    assert delete_response.status_code == 200
    assert client.get("/v1/workouts", headers=headers).json() == []


def test_workouts_require_authentication(client):
    response = client.get("/v1/workouts")
    assert response.status_code == 401


def test_users_cannot_access_each_others_workouts(client):
    owner_headers = auth_headers("owner@example.com")
    other_headers = auth_headers("other@example.com")

    create_response = client.post(
        "/v1/workouts",
        json={
            "workout_date": "2026-09-23",
            "workout_type": "Cardio",
            "duration_minutes": 30,
            "notes": None,
        },
        headers=owner_headers,
    )
    workout_id = create_response.json()["id"]

    assert client.get("/v1/workouts", headers=other_headers).json() == []
    assert (
        client.get(f"/v1/workouts/{workout_id}", headers=other_headers).status_code
        == 404
    )
    assert (
        client.delete(f"/v1/workouts/{workout_id}", headers=other_headers).status_code
        == 404
    )


def test_missing_workout_returns_not_found(client):
    headers = auth_headers("missing@example.com")
    response = client.get("/v1/workouts/999", headers=headers)
    assert response.status_code == 404
    assert response.json()["detail"] == "Workout not found"
