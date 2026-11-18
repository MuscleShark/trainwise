from conftest import auth_headers
from helpers import BENCH, SQUAT, new_id
from test_exercises import MACHINE
from test_templates import template_body


def own_template(client, headers, **overrides) -> str:
    template_id = new_id()
    saved = client.put(
        f"/v1/templates/{template_id}", json=template_body(**overrides), headers=headers
    )
    assert saved.status_code == 200
    return template_id


def test_a_shared_template_is_read_without_signing_in(client):
    owner = auth_headers("owner@example.com")
    template_id = own_template(client, owner)

    share = client.put(f"/v1/templates/{template_id}/share", headers=owner)

    assert share.status_code == 200
    code = share.json()["code"]
    assert len(code) == 10
    shared = client.get(f"/v1/shared-templates/{code}")
    assert shared.status_code == 200
    body = shared.json()
    assert body["name_en"] == "Upper / lower"
    assert [d["name"] for d in body["days"]] == ["Upper A", "Lower A"]
    assert body["days"][0]["exercises"][0]["sets"][0]["rep_max"] == 10
    assert {e["id"] for e in body["exercises"]} == {BENCH, SQUAT}
    assert all(not e["is_custom"] for e in body["exercises"])
    # Nothing says who shared it.
    assert "owner" not in str(body) and "@" not in str(body)


def test_the_link_shows_the_template_as_it_was_shared(client):
    owner = auth_headers("owner@example.com")
    template_id = own_template(client, owner)
    code = client.put(f"/v1/templates/{template_id}/share", headers=owner).json()["code"]

    client.put(f"/v1/templates/{template_id}", json=template_body(name_en="Renamed"), headers=owner)
    assert client.get(f"/v1/shared-templates/{code}").json()["name_en"] == "Upper / lower"

    # Sharing again takes a new snapshot under the same code.
    again = client.put(f"/v1/templates/{template_id}/share", headers=owner).json()
    assert again["code"] == code
    assert client.get(f"/v1/shared-templates/{code}").json()["name_en"] == "Renamed"


def test_only_the_owner_shares_and_built_ins_are_not_shared(client):
    owner = auth_headers("owner@example.com")
    template_id = own_template(client, owner)
    other = auth_headers("other@example.com")

    assert client.put(f"/v1/templates/{template_id}/share", headers=other).status_code == 404
    assert client.get(f"/v1/templates/{template_id}/share", headers=other).status_code == 404
    built_in = next(
        t for t in client.get("/v1/templates", headers=owner).json() if not t["is_custom"]
    )
    assert client.put(f"/v1/templates/{built_in['id']}/share", headers=owner).status_code == 404
    assert client.put(f"/v1/templates/{template_id}/share").status_code == 401


def test_stopping_the_share_ends_the_link(client):
    owner = auth_headers("owner@example.com")
    template_id = own_template(client, owner)
    code = client.put(f"/v1/templates/{template_id}/share", headers=owner).json()["code"]
    assert client.get(f"/v1/templates/{template_id}/share", headers=owner).json()["code"] == code

    assert client.delete(f"/v1/templates/{template_id}/share", headers=owner).status_code == 204

    assert client.get(f"/v1/shared-templates/{code}").status_code == 404
    assert client.get(f"/v1/templates/{template_id}/share", headers=owner).status_code == 404
    reader = auth_headers("reader@example.com")
    assert client.post(f"/v1/shared-templates/{code}/copy", headers=reader).status_code == 404
    # Sharing again brings the same link back.
    assert client.put(f"/v1/templates/{template_id}/share", headers=owner).json()["code"] == code
    assert client.get(f"/v1/shared-templates/{code}").status_code == 200


def test_deleting_the_template_ends_the_link(client):
    owner = auth_headers("owner@example.com")
    template_id = own_template(client, owner)
    code = client.put(f"/v1/templates/{template_id}/share", headers=owner).json()["code"]

    client.delete(f"/v1/templates/{template_id}", headers=owner)

    assert client.get(f"/v1/shared-templates/{code}").status_code == 404


def test_an_unknown_code_is_not_found(client):
    assert client.get("/v1/shared-templates/nothing123").status_code == 404


def test_a_copy_is_the_readers_own_template_with_new_ids(client):
    owner = auth_headers("owner@example.com")
    template_id = own_template(client, owner)
    code = client.put(f"/v1/templates/{template_id}/share", headers=owner).json()["code"]
    original = client.get(f"/v1/templates/{template_id}", headers=owner).json()
    reader = auth_headers("reader@example.com")

    copied = client.post(f"/v1/shared-templates/{code}/copy", headers=reader)

    assert copied.status_code == 201
    copy = copied.json()
    assert copy["is_custom"] is True
    assert copy["id"] != template_id
    assert copy["name_en"] == original["name_en"]
    assert [d["name"] for d in copy["days"]] == ["Upper A", "Lower A"]
    original_ids = {original["id"]} | {
        i
        for d in original["days"]
        for i in [d["id"]]
        + [e["id"] for e in d["exercises"]]
        + [s["id"] for e in d["exercises"] for s in e["sets"]]
    }
    copy_ids = {copy["id"]} | {
        i
        for d in copy["days"]
        for i in [d["id"]]
        + [e["id"] for e in d["exercises"]]
        + [s["id"] for e in d["exercises"] for s in e["sets"]]
    }
    assert not original_ids & copy_ids
    assert copy["days"][0]["exercises"][0]["exercise_id"] == BENCH
    assert copy["days"][0]["exercises"][0]["rest_seconds"] == 180
    # The reader has it, in the list and with the next sync; the owner's is unchanged.
    assert copy["id"] in {t["id"] for t in client.get("/v1/templates", headers=reader).json()}
    synced = client.get("/v1/sync", params={"since": 0}, headers=reader).json()
    assert [t["id"] for t in synced["templates"]] == [copy["id"]]
    assert client.get(f"/v1/templates/{template_id}", headers=owner).json() == original
    assert client.get(f"/v1/templates/{template_id}/share", headers=owner).json()["copy_count"] == 1


def test_copying_needs_a_signed_in_user(client):
    owner = auth_headers("owner@example.com")
    template_id = own_template(client, owner)
    code = client.put(f"/v1/templates/{template_id}/share", headers=owner).json()["code"]

    assert client.post(f"/v1/shared-templates/{code}/copy").status_code == 401


def test_a_custom_exercise_comes_along_as_the_readers_own(client):
    owner = auth_headers("owner@example.com")
    machine_id = new_id()
    client.put(f"/v1/exercises/{machine_id}", json=MACHINE, headers=owner)
    body = template_body()
    body["days"][0]["exercises"][0]["exercise_id"] = machine_id
    template_id = new_id()
    client.put(f"/v1/templates/{template_id}", json=body, headers=owner)
    code = client.put(f"/v1/templates/{template_id}/share", headers=owner).json()["code"]
    shared = client.get(f"/v1/shared-templates/{code}").json()
    machine = next(e for e in shared["exercises"] if e["id"] == machine_id)
    assert machine["is_custom"] is True
    assert machine["name_en"] == MACHINE["name_en"]
    reader = auth_headers("reader@example.com")

    copy = client.post(f"/v1/shared-templates/{code}/copy", headers=reader).json()

    copied_exercise_id = copy["days"][0]["exercises"][0]["exercise_id"]
    assert copied_exercise_id != machine_id
    synced = client.get("/v1/sync", params={"since": 0}, headers=reader).json()
    exercise = next(e for e in synced["exercises"] if e["id"] == copied_exercise_id)
    assert exercise["is_custom"] is True
    assert exercise["name_en"] == MACHINE["name_en"]
    assert exercise["base_exercise_id"] == BENCH
    assert exercise["aliases"] == []

    # A second copy uses the reader's exercise of that name instead of another one.
    again = client.post(f"/v1/shared-templates/{code}/copy", headers=reader).json()
    assert again["days"][0]["exercises"][0]["exercise_id"] == copied_exercise_id


def test_the_owner_copying_keeps_their_own_exercises(client):
    owner = auth_headers("owner@example.com")
    machine_id = new_id()
    client.put(f"/v1/exercises/{machine_id}", json=MACHINE, headers=owner)
    body = template_body()
    body["days"][0]["exercises"][0]["exercise_id"] = machine_id
    template_id = new_id()
    client.put(f"/v1/templates/{template_id}", json=body, headers=owner)
    code = client.put(f"/v1/templates/{template_id}/share", headers=owner).json()["code"]

    copy = client.post(f"/v1/shared-templates/{code}/copy", headers=owner).json()

    assert copy["days"][0]["exercises"][0]["exercise_id"] == machine_id


def test_deleting_the_account_deletes_its_shares(client):
    owner = auth_headers("owner@example.com")
    template_id = own_template(client, owner)
    code = client.put(f"/v1/templates/{template_id}/share", headers=owner).json()["code"]

    assert client.delete("/v1/me", headers=owner).status_code == 204

    assert client.get(f"/v1/shared-templates/{code}").status_code == 404
