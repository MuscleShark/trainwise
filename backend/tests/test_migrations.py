from pathlib import Path

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect, text

import migrate_handler
from catalog import BUILTIN_EXERCISES
from database import Base

BACKEND_DIR = Path(__file__).resolve().parent.parent


def alembic_config(url: str) -> Config:
    config = Config(str(BACKEND_DIR / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", url)
    config.attributes["configure_logger"] = False
    return config


@pytest.fixture
def database_url(tmp_path) -> str:
    return f"sqlite:///{tmp_path / 'migrations.db'}"


def schema_differences(url: str) -> list:
    engine = create_engine(url)
    with engine.connect() as connection:
        diff = compare_metadata(MigrationContext.configure(connection), Base.metadata)
    engine.dispose()
    return diff


def test_migrations_create_the_schema_of_the_models(database_url):
    command.upgrade(alembic_config(database_url), "head")

    assert schema_differences(database_url) == []


def test_baseline_adopts_a_database_created_before_alembic(database_url):
    # Production had the 0001 tables before Alembic existed: simulate that by creating
    # them and then dropping Alembic's version table.
    config = alembic_config(database_url)
    command.upgrade(config, "0001")
    engine = create_engine(database_url)
    with engine.begin() as connection:
        connection.execute(text("DROP TABLE alembic_version"))

    command.upgrade(config, "head")

    with engine.connect() as connection:
        revision = connection.execute(text("SELECT version_num FROM alembic_version")).scalar()
    engine.dispose()
    assert revision == command.ScriptDirectory.from_config(config).get_current_head()
    assert schema_differences(database_url) == []


def test_upgrade_twice_is_a_no_op(database_url):
    config = alembic_config(database_url)
    command.upgrade(config, "head")
    command.upgrade(config, "head")

    engine = create_engine(database_url)
    tables = set(inspect(engine).get_table_names())
    engine.dispose()
    assert {"users", "profiles", "workouts", "alembic_version"} <= tables


def test_migration_lambda_uses_the_direct_url(monkeypatch, database_url):
    monkeypatch.delenv("SSM_PARAMETER_PREFIX", raising=False)
    monkeypatch.setenv("DATABASE_URL_DIRECT", database_url)
    monkeypatch.setenv("DATABASE_URL", "sqlite://")

    result = migrate_handler.handler({}, None)

    assert result["status"] == "migrated"
    assert result["catalog"]["added"] == len(BUILTIN_EXERCISES)
    engine = create_engine(database_url)
    with engine.connect() as connection:
        assert connection.execute(text("SELECT count(*) FROM exercises")).scalar() == len(
            BUILTIN_EXERCISES
        )
    engine.dispose()

    # A second deploy changes nothing.
    assert migrate_handler.handler({}, None)["catalog"] == {"added": 0, "updated": 0, "removed": 0}
