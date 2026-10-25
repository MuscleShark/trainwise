import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "export_openapi.py"


def load_exporter():
    spec = importlib.util.spec_from_file_location("export_openapi", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_committed_openapi_document_is_current():
    exporter = load_exporter()
    committed = exporter.OUTPUT.read_text(encoding="utf-8")
    assert committed == exporter.render(), (
        "api/openapi.json is out of date. Run: python scripts/export_openapi.py"
    )


def test_operation_ids_are_readable_and_unique():
    exporter = load_exporter()
    ids = [
        operation["operationId"]
        for path in exporter.app.openapi()["paths"].values()
        for operation in path.values()
    ]
    assert len(ids) == len(set(ids))
    assert "listWorkouts" in ids and "putWorkout" in ids and "sync" in ids
    assert all("_" not in operation_id for operation_id in ids)


def exporter_output() -> str:
    return load_exporter().render()


def test_optional_fields_survive_swift_generation():
    # swift-openapi-generator drops fields written as anyOf [X, null].
    schemas = load_exporter().app.openapi()["components"]["schemas"]
    weight = schemas["SetRead"]["properties"]["weight_kg"]
    assert weight["type"] == ["number", "null"] and "anyOf" not in weight
    goal = schemas["ProfileWrite"]["properties"]["goal"]
    assert goal["type"] == ["string", "null"] and goal["enum"][-1] is None
    sync = schemas["SyncResponse"]
    assert sync["properties"]["profile"] == {"$ref": "#/components/schemas/ProfileRead"}
    assert "profile" not in sync["required"]
    assert "nullable_reference" not in exporter_output()


def test_decimals_are_documented_as_numbers():
    schemas = load_exporter().app.openapi()["components"]["schemas"]
    assert schemas["SetWrite"]["properties"]["weight_kg"]["type"] == ["number", "null"]
    assert schemas["BodyMeasurementRead"]["properties"]["value"]["type"] == "number"
