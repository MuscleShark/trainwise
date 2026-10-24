"""One-off migration for the move to Clerk sign-in (safe to run more than once).

- adds users.clerk_user_id (unique)
- makes users.password_hash optional

Run against the database's *direct* (non-pooled) connection string:

    read -rs "NEON_DIRECT_URL?Neon direct URL: " && echo
    DATABASE_URL="$NEON_DIRECT_URL" .venv/bin/python scripts/migrate_add_clerk.py
    unset NEON_DIRECT_URL
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text  # noqa: E402

from database import engine  # noqa: E402

STATEMENTS = [
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS clerk_user_id VARCHAR(255)",
    "CREATE UNIQUE INDEX IF NOT EXISTS ix_users_clerk_user_id ON users (clerk_user_id)",
    "ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL",
]

with engine.begin() as connection:
    for statement in STATEMENTS:
        connection.execute(text(statement))
        print(f"OK  {statement}")

print("Migration complete.")
