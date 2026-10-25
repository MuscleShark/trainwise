from conftest import auth_headers
from helpers import BENCH, SQUAT, new_id

from template_catalog import BUILTIN_TEMPLATES


def template_body(**overrides):
    body = {
        "name_en": "Upper / lower",
        "name_zh": "上下肢分化",
        "level": "intermediate",
        "days_per_week": 4,
        "days": [
            {
                "id": new_id(),
                "name": "Upper A",
                "exercises": [
                    {
                        "id": new_id(),
                        "exercise_id": BENCH,
                        "rest_seconds": 180,
                        "sets": [
                            {"id": new_id(), "rep_min": 6, "rep_max": 10, "target_rir": 2}
                            for _ in range(3)
                        ],
                    }
                ],
            },
            {
                "id": new_id(),
                "name": "Lower A",
                "exercises": [{"id": new_id(), "exercise_id": SQUAT, "sets": []}],
            },
        ],
    }
    body.update(overrides)
    return body


def test_put_creates_and_get_returns_a_template(client):
    headers = auth_headers("me@example.com")
    template_id = new_id()

    saved = client.put(f"/v1/templates/{template_id}", json=template_body(), headers=headers)

    assert saved.status_code == 200
    template = saved.json()
    assert template["is_custom"] is True
    assert [d["name"] for d in template["days"]] == ["Upper A", "Lower A"]
    assert template["days"][0]["exercises"][0]["sets"][0]["rep_max"] == 10
    assert client.get(f"/v1/templates/{template_id}", headers=headers).json() == template


def test_put_replaces_days(client):
    headers = auth_headers("me@example.com")
    template_id = new_id()
    client.put(f"/v1/templates/{template_id}", json=template_body(), headers=headers)

    body = template_body()
    body["days"] = body["days"][:1]
    template = client.put(f"/v1/templates/{template_id}", json=body, headers=headers).json()

    assert len(template["days"]) == 1


def test_list_includes_built_in_templates(client):
    headers = auth_headers("me@example.com")
    own_id = new_id()
    client.put(f"/v1/templates/{own_id}", json=template_body(), headers=headers)

    templates = client.get("/v1/templates", headers=headers).json()

    assert len([t for t in templates if not t["is_custom"]]) == len(BUILTIN_TEMPLATES)
    assert [t["id"] for t in templates if t["is_custom"]] == [own_id]


def test_templates_are_private_and_deletable(client):
    template_id = new_id()
    owner = auth_headers("a@example.com")
    client.put(f"/v1/templates/{template_id}", json=template_body(), headers=owner)
    other = auth_headers("b@example.com")

    assert client.get(f"/v1/templates/{template_id}", headers=other).status_code == 404
    assert client.delete(f"/v1/templates/{template_id}", headers=other).status_code == 404
    assert (
        client.put(f"/v1/templates/{template_id}", json=template_body(), headers=other).status_code
        == 409
    )

    assert client.delete(f"/v1/templates/{template_id}", headers=owner).status_code == 204
    assert client.get(f"/v1/templates/{template_id}", headers=owner).status_code == 404
    assert [t for t in client.get("/v1/templates", headers=owner).json() if t["is_custom"]] == []


def test_invalid_templates_are_rejected(client):
    headers = auth_headers("me@example.com")
    duplicate = template_body()
    duplicate["days"][1]["id"] = duplicate["days"][0]["id"]
    reversed_range = template_body()
    reversed_range["days"][0]["exercises"][0]["sets"][0].update(rep_min=12, rep_max=8)
    for body in (template_body(days=[]), template_body(level="pro"), duplicate, reversed_range):
        assert (
            client.put(f"/v1/templates/{new_id()}", json=body, headers=headers).status_code == 422
        )

    unknown = template_body()
    unknown["days"][0]["exercises"][0]["exercise_id"] = new_id()
    assert client.put(f"/v1/templates/{new_id()}", json=unknown, headers=headers).status_code == 422
