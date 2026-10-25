import os

from fastapi import APIRouter, Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.utils import get_openapi
from fastapi.routing import APIRoute
from mangum import Mangum
from sqlalchemy import text
from sqlalchemy.orm import Session

from database import get_db
from routers import auth, body, exercises, profiles, sync, templates, workouts


def operation_id(route: APIRoute) -> str:
    """listWorkouts instead of list_workouts_v1_workouts_get.

    The Swift and TypeScript clients are generated from the OpenAPI document
    (api/openapi.json), and these ids become their method names.
    """
    first, *rest = route.name.split("_")
    return first + "".join(word.title() for word in rest)


NULL = {"type": "null"}


def nullable_as_type_list(node):
    """Rewrites FastAPI's optional fields so swift-openapi-generator keeps them.

    FastAPI writes `X | None` as anyOf [X, {"type": "null"}]. The Swift generator
    skips the null branch and drops the field with it, so a plain type becomes
    type [X, "null"] (which openapi-typescript also reads as `X | null`). An optional
    reference becomes the reference itself and is no longer required, which Swift
    decodes as nil when the value is null.
    """
    if isinstance(node, list):
        for item in node:
            nullable_as_type_list(item)
        return
    if not isinstance(node, dict):
        return
    for value in node.values():
        nullable_as_type_list(value)

    branches = node.get("anyOf", [])
    others = [branch for branch in branches if branch != NULL]
    if len(branches) == 2 and len(others) == 1:
        (other,) = others
        if isinstance(other.get("type"), str):
            del node["anyOf"]
            node.update(other, type=[other["type"], "null"])
            if "enum" in node:
                node["enum"] = [*node["enum"], None]
        elif "$ref" in other:
            del node["anyOf"]
            node.update(other, nullable_reference=True)

    for name, prop in node.get("properties", {}).items():
        if prop.pop("nullable_reference", False) and name in node.get("required", []):
            node["required"].remove(name)


app = FastAPI(
    title="IronSage API",
    version="1.0.0",
    generate_unique_id_function=operation_id,
)


def openapi_document():
    if app.openapi_schema is None:
        schema = get_openapi(title=app.title, version=app.version, routes=app.routes)
        nullable_as_type_list(schema)
        app.openapi_schema = schema
    return app.openapi_schema


app.openapi = openapi_document

# Comma-separated, e.g. "https://trainwise.vercel.app,http://localhost:3000".
frontend_urls = [
    url.strip()
    for url in os.getenv("FRONTEND_URL", "http://localhost:3000").split(",")
    if url.strip()
]

# Every client-facing endpoint lives under /v1, so a later breaking change can ship as
# /v2 while installed iOS app versions keep calling /v1. /health stays unversioned
# because the deploy smoke test calls it.
v1 = APIRouter(prefix="/v1")
v1.include_router(auth.router)
v1.include_router(profiles.router)
v1.include_router(exercises.router)
v1.include_router(workouts.router)
v1.include_router(templates.router)
v1.include_router(body.router)
v1.include_router(sync.router)
app.include_router(v1)

app.add_middleware(
    CORSMiddleware,
    allow_origins=frontend_urls,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def get_health(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ok"}


# Entry point for AWS Lambda (configure the function handler as "main.handler").
handler = Mangum(app, lifespan="off")
