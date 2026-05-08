from pathlib import Path

from fastapi.testclient import TestClient

from app.contracts import (
    environment_request_capabilities,
    openapi_contract_summary,
    runtime_adapter_contract,
    runtime_capabilities,
)
from app.main import create_app


def test_runtime_and_environment_request_capabilities_are_public_contracts(tmp_path: Path) -> None:
    runtime = runtime_capabilities()
    environment_request = environment_request_capabilities()
    contract = runtime_adapter_contract()

    assert runtime == {
        "environment_request": True,
        "deployment_plan": True,
        "secret_plan": True,
        "status_projection": True,
    }
    assert environment_request == {
        "schema_version": "platform.environment_request_capabilities/v1",
        "workflow": "environment",
        "dry_run": True,
        "supported_actions": ["create", "delete"],
        "default_action": "create",
        "default_environment_type": "development",
        "required_fields": ["runtime", "app", "environment"],
        "optional_fields": ["action", "environment_type"],
    }
    assert contract["capabilities"] == runtime
    assert contract["environment_request"] == environment_request

    client = TestClient(create_app(audit_path=tmp_path / "audit.jsonl"))
    response = client.get("/api/v1/actions")

    assert response.status_code == 200
    environment_action = next(action for action in response.json()["actions"] if action["id"] == "environment.create")
    assert environment_action == {
        "id": "environment.create",
        "label": "Create environment",
        "runtime": "kind",
        "dry_run": environment_request["dry_run"],
    }


def test_runtime_adapter_contract_lists_supported_runtimes_and_slicer_gap() -> None:
    contract = runtime_adapter_contract()

    assert contract["schema_version"] == "platform.portal_runtime_contract/v1"
    runtimes = {runtime["name"]: runtime for runtime in contract["runtimes"]}
    assert set(runtimes) == {"generic_kubernetes", "kind", "lima"}

    assert runtimes["kind"]["execution_adapter"] == {"type": "make", "make_dir": "kubernetes/kind"}
    assert runtimes["lima"]["execution_adapter"] == {"type": "make", "make_dir": "kubernetes/lima"}
    assert runtimes["generic_kubernetes"]["execution_adapter"] == {"type": "generic-kubernetes"}

    for runtime in runtimes.values():
        assert runtime["capabilities"] == {
            "environment_request": True,
            "deployment_plan": True,
            "secret_plan": True,
            "status_projection": True,
        }

    assert contract["gaps"] == [
        {
            "runtime": "slicer",
            "reason": "kubernetes/slicer exists, but the portal runtime adapter has not been implemented",
            "needed_adapter": "MakefileRuntimeAdapter",
        }
    ]


def test_openapi_contract_summary_covers_runtime_workflow_routes() -> None:
    app = create_app()
    summary = openapi_contract_summary(app.openapi())

    assert summary["schema_version"] == "platform.portal_api_contract/v1"
    operations = {(operation["method"], operation["path"]) for operation in summary["operations"]}

    assert ("GET", "/api/v1/runtimes") in operations
    assert ("GET", "/api/v1/status") in operations
    assert ("POST", "/api/v1/environments") in operations
    assert ("DELETE", "/api/v1/environments/{app_name}/{environment}") in operations
    assert ("POST", "/api/v1/deployments/promote") in operations
    assert ("POST", "/api/v1/deployments/rollback") in operations
    assert ("POST", "/api/v1/workflows/secrets/dry-run") in operations
    assert summary["operation_count"] >= 10
