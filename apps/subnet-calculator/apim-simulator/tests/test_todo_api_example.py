from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from fastapi.testclient import TestClient

MODULE_PATH = Path(__file__).resolve().parents[1] / "examples" / "todo-app" / "api-fastapi-container-app" / "main.py"


def load_module():
    spec = importlib.util.spec_from_file_location("todo_api_example_main", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load todo API example module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def make_client() -> TestClient:
    module = load_module()
    return TestClient(module.create_app())


def test_health_endpoint() -> None:
    client = make_client()

    response = client.get("/api/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "todo-api"}


def test_create_list_and_update_todo() -> None:
    client = make_client()

    created = client.post("/api/todos", json={"title": "Port this app to platform later"})
    assert created.status_code == 201
    payload = created.json()
    assert payload == {"id": 1, "title": "Port this app to platform later", "completed": False}

    listed = client.get("/api/todos")
    assert listed.status_code == 200
    assert listed.json() == {"items": [payload]}

    updated = client.patch("/api/todos/1", json={"completed": True})
    assert updated.status_code == 200
    assert updated.json() == {"id": 1, "title": "Port this app to platform later", "completed": True}

    relisted = client.get("/api/todos")
    assert relisted.status_code == 200
    assert relisted.json()["items"][0]["completed"] is True


def test_rejects_empty_titles() -> None:
    client = make_client()

    response = client.post("/api/todos", json={"title": "   "})

    assert response.status_code == 422


def test_returns_404_for_unknown_todo_id() -> None:
    client = make_client()

    response = client.patch("/api/todos/404", json={"completed": True})

    assert response.status_code == 404
    assert response.json() == {"detail": "Todo not found"}
