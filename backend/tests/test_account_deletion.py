from conftest import TestingSessionLocal, auth_headers

from models import Profile, User, Workout

WORKOUT = {"workout_date": "2026-10-01", "workout_type": "Run", "duration_minutes": 30}


def test_delete_account_removes_user_and_all_their_data(client):
    headers = auth_headers("leaving@example.com", "user_leaving")
    client.post("/v1/profile", json={"weight_kg": 70}, headers=headers)
    client.post("/v1/workouts", json=WORKOUT, headers=headers)
    client.post("/v1/workouts", json=WORKOUT, headers=headers)

    response = client.delete("/v1/me", headers=headers)

    assert response.status_code == 204
    assert response.content == b""
    with TestingSessionLocal() as db:
        assert db.query(User).count() == 0
        assert db.query(Profile).count() == 0
        assert db.query(Workout).count() == 0


def test_delete_account_keeps_other_users_data(client):
    staying = auth_headers("staying@example.com", "user_staying")
    client.post("/v1/profile", json={"weight_kg": 80}, headers=staying)
    client.post("/v1/workouts", json=WORKOUT, headers=staying)
    leaving = auth_headers("leaving@example.com", "user_leaving")
    client.post("/v1/workouts", json=WORKOUT, headers=leaving)

    assert client.delete("/v1/me", headers=leaving).status_code == 204

    assert client.get("/v1/profile", headers=staying).json()["weight_kg"] == 80
    assert len(client.get("/v1/workouts", headers=staying).json()) == 1


def test_signing_in_after_deletion_starts_an_empty_account(client):
    # If the client could not delete the Clerk user, the same Clerk user may sign in
    # again. They get a fresh account with none of the deleted data.
    headers = auth_headers("again@example.com", "user_again")
    client.post("/v1/workouts", json=WORKOUT, headers=headers)
    client.delete("/v1/me", headers=headers)

    response = client.get("/v1/me", headers=auth_headers("again@example.com", "user_again"))

    assert response.status_code == 200
    assert client.get("/v1/workouts", headers=headers).json() == []


def test_delete_account_requires_sign_in(client):
    assert client.delete("/v1/me").status_code == 401
