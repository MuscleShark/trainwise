import typing

from conftest import TestingSessionLocal
from sqlalchemy import select

import catalog
from catalog import BUILTIN_EXERCISES, EQUIPMENT, LOAD_TYPES, MUSCLES, exercise_id
from models import Exercise
from schemas import Equipment, LoadType, Muscle


def test_catalog_matches_the_api_vocabulary():
    assert set(MUSCLES) == set(typing.get_args(Muscle))
    assert set(EQUIPMENT) == set(typing.get_args(Equipment))
    assert set(LOAD_TYPES) == set(typing.get_args(LoadType))


def test_catalog_entries_are_valid():
    slugs = [entry.slug for entry in BUILTIN_EXERCISES]
    assert len(slugs) == len(set(slugs))
    assert len({entry.name_en for entry in BUILTIN_EXERCISES}) == len(slugs)
    assert len({entry.name_zh for entry in BUILTIN_EXERCISES}) == len(slugs)
    for entry in BUILTIN_EXERCISES:
        assert entry.equipment in EQUIPMENT
        assert entry.load_type in LOAD_TYPES
        assert entry.primary
        assert set(entry.primary + entry.secondary) <= set(MUSCLES)


def test_sync_is_idempotent(client):
    # The client fixture already synced the catalog once.
    with TestingSessionLocal() as db:
        assert catalog.sync_builtin_exercises(db) == {"added": 0, "updated": 0, "removed": 0}
        assert db.scalar(select(Exercise).where(Exercise.id == exercise_id("deadlift")))


def test_sync_updates_changed_and_retires_removed_entries(client, monkeypatch):
    first, *rest = BUILTIN_EXERCISES
    renamed = first._replace(name_zh="杠铃平板卧推")
    monkeypatch.setattr(catalog, "BUILTIN_EXERCISES", (renamed, *rest[1:]))

    with TestingSessionLocal() as db:
        counts = catalog.sync_builtin_exercises(db)
        assert counts == {"added": 0, "updated": 1, "removed": 1}
        assert db.get(Exercise, exercise_id(first.slug)).name_zh == "杠铃平板卧推"
        assert db.get(Exercise, exercise_id(rest[0].slug)).deleted_at is not None
