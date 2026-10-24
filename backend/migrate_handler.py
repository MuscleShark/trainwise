"""Lambda that applies database migrations (function handler: "migrate_handler.handler").

After the migrations it updates the built-in exercise catalog (see catalog.py).

CDK runs it as a trigger during each deploy, before the API function is updated. If a
migration fails, the deploy fails and the API keeps running the previous code.

It uses DATABASE_URL_DIRECT, Neon's direct (non-pooled) connection string, because
schema changes should not go through the pooled endpoint.
"""

import os
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import NullPool

from catalog import sync_builtin_exercises
from ssm_parameters import load_ssm_parameters

ALEMBIC_INI = Path(__file__).resolve().parent / "alembic.ini"


def handler(event, context):
    load_ssm_parameters(os.getenv("SSM_PARAMETER_PREFIX"), ("DATABASE_URL_DIRECT",))
    os.environ["DATABASE_URL"] = os.environ["DATABASE_URL_DIRECT"]

    config = Config(str(ALEMBIC_INI))
    command.upgrade(config, "head")

    engine = create_engine(os.environ["DATABASE_URL"], poolclass=NullPool)
    with Session(engine) as db:
        catalog = sync_builtin_exercises(db)
    engine.dispose()
    return {"status": "migrated", "catalog": catalog}
