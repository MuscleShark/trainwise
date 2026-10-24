from pathlib import Path

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect, text

import migrate_handler
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
    # Production: tables already exist, so the baseline only records its revision.
    engine = create_engine(database_url)
    Base.metadata.create_all(engine)

    command.upgrade(alembic_config(database_url), "head")

    with engine.connect() as connection:
        revision = connection.execute(text("SELECT version_num FROM alembic_version")).scalar()
    engine.dispose()
    assert revision == command.ScriptDirectory.from_config(
        alembic_config(database_url)
    ).get_current_head()
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

    assert migrate_handler.handler({}, None) == {"status": "migrated"}

    engine = create_engine(database_url)
    assert "alembic_version" in inspect(engine).get_table_names()
    engine.dispose()
