from conftest import auth_headers

PROFILE_DATA = {
    "birthday": "1995-04-12",
    "gender": "female",
    "height_cm": 168.5,
    "weight_kg": 60,
    "body_fat_percentage": 22.5,
    "fitness_goal": "build muscle",
    "training_frequency": 4,
    "training_location": "gym",
    "sleep_hours": 7.5,
}


def test_profile_is_missing_until_created(client):
    response = client.get("/v1/profile", headers=auth_headers("new@example.com"))
    assert response.status_code == 404
    assert response.json()["detail"] == "Profile not found"


def test_create_and_read_profile(client):
    headers = auth_headers("owner@example.com")

    create_response = client.post("/v1/profile", json=PROFILE_DATA, headers=headers)
    assert create_response.status_code == 201
    created = create_response.json()
    for field, value in PROFILE_DATA.items():
        assert created[field] == value

    get_response = client.get("/v1/profile", headers=headers)
    assert get_response.status_code == 200
    assert get_response.json() == created


def test_profile_fields_are_optional(client):
    response = client.post("/v1/profile", json={}, headers=auth_headers("empty@example.com"))
    assert response.status_code == 201
    assert response.json()["height_cm"] is None


def test_second_profile_is_rejected(client):
    headers = auth_headers("twice@example.com")
    client.post("/v1/profile", json=PROFILE_DATA, headers=headers)

    response = client.post("/v1/profile", json=PROFILE_DATA, headers=headers)
    assert response.status_code == 400
    assert response.json()["detail"] == "Profile already exists"


def test_update_changes_only_sent_fields(client):
    headers = auth_headers("update@example.com")
    client.post("/v1/profile", json=PROFILE_DATA, headers=headers)

    response = client.put(
        "/v1/profile",
        json={"weight_kg": 58.5, "fitness_goal": None},
        headers=headers,
    )

    assert response.status_code == 200
    updated = response.json()
    assert updated["weight_kg"] == 58.5
    assert updated["fitness_goal"] is None
    assert updated["height_cm"] == PROFILE_DATA["height_cm"]
    assert client.get("/v1/profile", headers=headers).json() == updated


def test_update_without_profile_is_not_found(client):
    response = client.put(
        "/v1/profile", json={"weight_kg": 70}, headers=auth_headers("nobody@example.com")
    )
    assert response.status_code == 404


def test_invalid_field_type_is_rejected(client):
    response = client.post(
        "/v1/profile",
        json={"training_frequency": "often"},
        headers=auth_headers("invalid@example.com"),
    )
    assert response.status_code == 422


def test_profiles_are_private_to_their_user(client):
    client.post("/v1/profile", json=PROFILE_DATA, headers=auth_headers("alice@example.com"))

    bob = auth_headers("bob@example.com")
    assert client.get("/v1/profile", headers=bob).status_code == 404
    assert client.put("/v1/profile", json={"weight_kg": 90}, headers=bob).status_code == 404


def test_profile_requires_sign_in(client):
    assert client.get("/v1/profile").status_code == 401
    assert client.post("/v1/profile", json=PROFILE_DATA).status_code == 401
    assert client.put("/v1/profile", json=PROFILE_DATA).status_code == 401
