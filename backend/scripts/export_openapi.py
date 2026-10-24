"""Writes the API's OpenAPI document to api/openapi.json.

The iPhone app (swift-openapi-generator) and the web app (openapi-typescript)
generate their API code from that file. Run this after changing an endpoint or a
schema, and commit the result; tests/test_openapi.py fails while it is out of date.

    python scripts/export_openapi.py
"""

import json
import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
OUTPUT = BACKEND_DIR.parent / "api" / "openapi.json"

# Building the document needs no database or Clerk connection, only these to be set.
os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("CLERK_ISSUER", "https://example.clerk.accounts.dev")
sys.path.insert(0, str(BACKEND_DIR))

from main import app  # noqa: E402


def render() -> str:
    return json.dumps(app.openapi(), indent=2, ensure_ascii=False, sort_keys=True) + "\n"


if __name__ == "__main__":
    OUTPUT.write_text(render(), encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(BACKEND_DIR.parent)}")
