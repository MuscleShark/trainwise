from conftest import TestingSessionLocal, auth_headers
from sqlalchemy import select

import template_catalog
from catalog import BUILTIN_EXERCISES
from models import Template
from template_catalog import BUILTIN_TEMPLATES, template_id


def test_templates_only_use_catalog_exercises_and_sensible_ranges():
    slugs = {entry.slug for entry in BUILTIN_EXERCISES}
    for template in BUILTIN_TEMPLATES:
        assert 1 <= len(template.days) <= template.days_per_week
        for day in template.days:
            for item in day.items:
                assert item.exercise in slugs, item.exercise
                assert 1 <= item.rep_min <= item.rep_max <= 20
                assert 0 <= item.rir <= 3
                assert 1 <= item.sets <= 5


def test_built_in_templates_are_served_in_both_languages(client):
    templates = client.get("/v1/templates", headers=auth_headers("a@example.com")).json()

    built_in = {t["id"]: t for t in templates if not t["is_custom"]}
    assert len(built_in) == len(BUILTIN_TEMPLATES)
    ppl = built_in[str(template_id("push_pull_legs"))]
    assert ppl["name_zh"] == "推拉腿"
    assert [(d["name"], d["name_zh"]) for d in ppl["days"]] == [
        ("Push", "推"),
        ("Pull", "拉"),
        ("Legs", "腿"),
    ]
    bench = ppl["days"][0]["exercises"][0]
    assert bench["rest_seconds"] == 180
    assert [(s["rep_min"], s["rep_max"], s["target_rir"]) for s in bench["sets"]] == [(5, 8, 2)] * 4


def test_built_in_templates_cannot_be_changed(client):
    response = client.put(
        f"/v1/templates/{template_id('upper_lower')}",
        json={"name_en": "Mine", "days": [{"id": str(template_id("x")), "name": "Day"}]},
        headers=auth_headers("a@example.com"),
    )
    assert response.status_code == 403


def test_sync_is_idempotent_and_updates_changes(client, monkeypatch):
    with TestingSessionLocal() as db:
        assert template_catalog.sync_builtin_templates(db) == {
            "added": 0,
            "updated": 0,
            "removed": 0,
        }

    first, *rest = BUILTIN_TEMPLATES
    renamed = first._replace(name_zh="新手全身")
    monkeypatch.setattr(template_catalog, "BUILTIN_TEMPLATES", (renamed, *rest[1:]))
    with TestingSessionLocal() as db:
        assert template_catalog.sync_builtin_templates(db) == {
            "added": 0,
            "updated": 1,
            "removed": 1,
        }
        assert db.get(Template, template_id(first.slug)).name_zh == "新手全身"
        removed = db.scalar(select(Template).where(Template.id == template_id(rest[0].slug)))
        assert removed.deleted_at is not None

    templates = client.get("/v1/templates", headers=auth_headers("a@example.com")).json()
    assert str(template_id(rest[0].slug)) not in {t["id"] for t in templates}
