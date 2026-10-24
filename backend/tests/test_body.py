from conftest import auth_headers
from helpers import new_id

WEIGHT = {"measured_at": "2026-10-20T07:30:00Z", "kind": "weight", "value": "81.4"}
NIGHT = {
    "sleep_minutes": 340,
    "deep_minutes": 55,
    "rem_minutes": 70,
    "core_minutes": 200,
    "awake_minutes": 15,
    "hrv_sdnn_ms": 41.5,
    "resting_hr_bpm": 56,
}


def test_body_measurements_can_be_saved_listed_and_deleted(client):
    headers = auth_headers("me@example.com")
    weight_id = new_id()
    client.put(f"/v1/body-measurements/{weight_id}", json=WEIGHT, headers=headers)
    client.put(
        f"/v1/body-measurements/{new_id()}",
        json={**WEIGHT, "kind": "body_fat", "value": "17.5", "source": "healthkit"},
        headers=headers,
    )

    weights = client.get("/v1/body-measurements?kind=weight", headers=headers).json()
    assert [m["value"] for m in weights] == [81.4]

    assert client.delete(f"/v1/body-measurements/{weight_id}", headers=headers).status_code == 204
    assert client.get("/v1/body-measurements?kind=weight", headers=headers).json() == []


def test_body_measurements_are_private(client):
    measurement_id = new_id()
    client.put(
        f"/v1/body-measurements/{measurement_id}", json=WEIGHT, headers=auth_headers("a@x.com")
    )
    other = auth_headers("b@x.com")
    assert client.get("/v1/body-measurements", headers=other).json() == []
    assert (
        client.delete(f"/v1/body-measurements/{measurement_id}", headers=other).status_code == 404
    )
    response = client.put(f"/v1/body-measurements/{measurement_id}", json=WEIGHT, headers=other)
    assert response.status_code == 409


def test_invalid_measurements_are_rejected(client):
    headers = auth_headers("me@example.com")
    for body in ({**WEIGHT, "kind": "bicep_peak"}, {**WEIGHT, "value": "0"}):
        response = client.put(f"/v1/body-measurements/{new_id()}", json=body, headers=headers)
        assert response.status_code == 422


def test_readiness_is_one_row_per_day(client):
    headers = auth_headers("me@example.com")
    client.put("/v1/readiness/2026-10-20", json=NIGHT, headers=headers)
    client.put("/v1/readiness/2026-10-20", json={**NIGHT, "sleep_minutes": 400}, headers=headers)
    client.put("/v1/readiness/2026-10-21", json=NIGHT, headers=headers)

    days = client.get("/v1/readiness", headers=headers).json()
    assert [(d["date"], d["sleep_minutes"]) for d in days] == [
        ("2026-10-20", 400),
        ("2026-10-21", 340),
    ]
    in_range = client.get("/v1/readiness?from=2026-10-21&to=2026-10-22", headers=headers).json()
    assert [d["date"] for d in in_range] == ["2026-10-21"]


def test_readiness_is_private_and_validated(client):
    client.put("/v1/readiness/2026-10-20", json=NIGHT, headers=auth_headers("a@x.com"))
    assert client.get("/v1/readiness", headers=auth_headers("b@x.com")).json() == []

    response = client.put(
        "/v1/readiness/2026-10-20",
        json={**NIGHT, "sleep_minutes": 2000},
        headers=auth_headers("a@x.com"),
    )
    assert response.status_code == 422


def test_body_and_readiness_require_sign_in(client):
    assert client.get("/v1/body-measurements").status_code == 401
    assert client.get("/v1/readiness").status_code == 401
