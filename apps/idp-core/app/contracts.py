from __future__ import annotations

from typing import Any, Final

from app.adapters import MakefileRuntimeAdapter, RuntimeAdapter, list_adapters
from app.environment_requests import environment_request_capabilities

RUNTIME_CAPABILITY_FLAGS: Final[dict[str, bool]] = {
    "environment_request": True,
    "deployment_plan": True,
    "secret_plan": True,
    "status_projection": True,
}


def runtime_capabilities() -> dict[str, bool]:
    return dict(RUNTIME_CAPABILITY_FLAGS)


def runtime_adapter_contract(adapters: list[RuntimeAdapter] | None = None) -> dict[str, object]:
    adapter_list = adapters if adapters is not None else list_adapters()
    runtimes = []
    supported_runtime_names = {adapter.name for adapter in adapter_list}

    for adapter in adapter_list:
        runtime: dict[str, object] = {
            "name": adapter.name,
            "description": adapter.description,
            "capabilities": runtime_capabilities(),
        }
        if isinstance(adapter, MakefileRuntimeAdapter):
            runtime["execution_adapter"] = {
                "type": "make",
                "make_dir": adapter.make_dir,
            }
        else:
            runtime["execution_adapter"] = {
                "type": "generic-kubernetes",
            }
        runtimes.append(runtime)

    gaps = []
    if "slicer" not in supported_runtime_names:
        gaps.append(
            {
                "runtime": "slicer",
                "reason": "kubernetes/slicer exists, but the portal runtime adapter has not been implemented",
                "needed_adapter": "MakefileRuntimeAdapter",
            }
        )

    return {
        "schema_version": "platform.portal_runtime_contract/v1",
        "capabilities": runtime_capabilities(),
        "environment_request": environment_request_capabilities(),
        "runtimes": runtimes,
        "gaps": gaps,
    }


def openapi_contract_summary(openapi_schema: dict[str, Any]) -> dict[str, object]:
    paths = openapi_schema.get("paths", {})
    operations = []

    if isinstance(paths, dict):
        for path, methods in sorted(paths.items()):
            if not isinstance(methods, dict):
                continue
            for method, operation in sorted(methods.items()):
                if not isinstance(operation, dict):
                    continue
                operations.append(
                    {
                        "method": method.upper(),
                        "path": path,
                        "operation_id": operation.get("operationId", ""),
                    }
                )

    return {
        "schema_version": "platform.portal_api_contract/v1",
        "title": openapi_schema.get("info", {}).get("title", ""),
        "operation_count": len(operations),
        "operations": operations,
    }
