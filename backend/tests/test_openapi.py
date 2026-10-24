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
