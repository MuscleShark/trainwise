import uuid

from conftest import auth_headers

PROFILE = {
    "birthday": "1995-04-12",
    "height_cm": 178.5,
    "gender": "male",
    "training_location": "gym",
    "unit_system": "imperial",
    "experience_level": "intermediate",
    "goal": "strength",
    "training_days_per_week": 4,
}


def test_profile_is_missing_until_saved(client):
    response = client.get("/v1/profile", headers=auth_headers("new@example.com"))
    assert response.status_code == 404


def test_put_creates_and_get_returns_the_profile(client):
    headers = auth_headers("me@example.com")

    saved = client.put("/v1/profile", json=PROFILE, headers=headers)

    assert saved.status_code == 200
    for field, value in PROFILE.items():
        assert saved.json()[field] == value
    assert client.get("/v1/profile", headers=headers).json() == saved.json()


def test_put_replaces_every_field(client):
    headers = auth_headers("me@example.com")
    client.put("/v1/profile", json=PROFILE, headers=headers)

    profile = client.put("/v1/profile", json={"goal": "hypertrophy"}, headers=headers).json()

    assert profile["goal"] == "hypertrophy"
    assert profile["height_cm"] is None
    assert profile["unit_system"] == "metric"


def test_hidden_templates_are_kept_once_each(client):
    headers = auth_headers("me@example.com")
    first, second = str(uuid.uuid4()), str(uuid.uuid4())

    saved = client.put(
        "/v1/profile",
        json={**PROFILE, "hidden_template_ids": [first, second, first]},
        headers=headers,
    ).json()

    assert saved["hidden_template_ids"] == [first, second]
    fetched = client.get("/v1/profile", headers=headers).json()
    assert fetched["hidden_template_ids"] == [first, second]
    # Like every field, left out means the default.
    replaced = client.put("/v1/profile", json=PROFILE, headers=headers).json()
    assert replaced["hidden_template_ids"] == []


def test_hidden_templates_reach_other_devices_through_sync(client):
    headers = auth_headers("me@example.com")
    hidden = str(uuid.uuid4())
    client.put("/v1/profile", json={**PROFILE, "hidden_template_ids": [hidden]}, headers=headers)

    changes = client.get("/v1/sync?since=0", headers=headers).json()

    assert changes["profile"]["hidden_template_ids"] == [hidden]


def test_invalid_profiles_are_rejected(client):
    headers = auth_headers("me@example.com")
    for body in (
        {"training_days_per_week": 8},
        {"unit_system": "stone"},
        {"goal": "get huge"},
        {"height_cm": 0},
        {"hidden_template_ids": ["not-a-uuid"]},
        {"hidden_template_ids": [str(uuid.uuid4()) for _ in range(101)]},
    ):
        assert client.put("/v1/profile", json=body, headers=headers).status_code == 422


def test_profiles_are_private(client):
    client.put("/v1/profile", json=PROFILE, headers=auth_headers("alice@example.com"))
    response = client.get("/v1/profile", headers=auth_headers("bob@example.com"))
    assert response.status_code == 404


def test_profile_requires_sign_in(client):
    assert client.get("/v1/profile").status_code == 401
    assert client.put("/v1/profile", json=PROFILE).status_code == 401
