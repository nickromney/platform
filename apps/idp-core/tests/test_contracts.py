from app.contracts import openapi_contract_summary, runtime_adapter_contract
from app.main import create_app


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
