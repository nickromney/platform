import json
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.adapters import StatusProvider, get_adapter, list_adapters
from app.audit import AuditWriter
from app.models import DeploymentRequest, EnvironmentRequest, ScaffoldRequest, SecretRequest, WorkflowResponse
from app.paths import discover_repo_root

DEFAULT_AUDIT_PATH = Path("/tmp/idp-core/audit.jsonl")
DEFAULT_PUBLIC_PORTAL_URL = "https://portal.127.0.0.1.sslip.io"
DEFAULT_PUBLIC_API_URL = "https://portal-api.127.0.0.1.sslip.io"
DEFAULT_CORS_ORIGINS = [
    DEFAULT_PUBLIC_PORTAL_URL,
    DEFAULT_PUBLIC_API_URL,
    "http://127.0.0.1:5173",
    "http://localhost:5173",
]
REPO_ROOT = discover_repo_root(Path(__file__))
DEFAULT_CATALOG_PATH = REPO_ROOT / "catalog/platform-apps.json"


def catalog_path() -> Path:
    return Path(os.environ.get("IDP_CATALOG_PATH") or DEFAULT_CATALOG_PATH).expanduser()


def create_app(*, audit_path: Path = DEFAULT_AUDIT_PATH, status_provider: StatusProvider | None = None) -> FastAPI:
    audit = AuditWriter(audit_path)
    app = FastAPI(title="IDP Core", version="0.1.0")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=DEFAULT_CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    def adapter_for(runtime: str):
        adapter = get_adapter(runtime)
        if adapter is None:
            raise HTTPException(status_code=400, detail=f"unknown runtime: {runtime}")
        return adapter

    def active_adapter():
        return adapter_for(os.environ.get("IDP_RUNTIME", "kind"))

    def catalog() -> dict:
        return json.loads(catalog_path().read_text(encoding="utf-8"))

    def optional_string(value) -> str | None:
        return value if isinstance(value, str) else None

    def workflow_response(action: str, runtime: str, plan, request: dict[str, object]) -> dict[str, object]:
        audit_record = audit.write(
            event=action,
            runtime=runtime,
            workflow=action.split(".", 1)[0],
            request={"dry_run": True, **request},
        )
        return {
            "dry_run": True,
            "action": action,
            "runtime": runtime,
            "plan": plan.model_dump(),
            "audit": audit_record.model_dump(),
        }

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "healthy", "service": "idp-core"}

    @app.get("/api/v1/runtimes")
    def runtimes() -> dict[str, list[dict[str, str]]]:
        return {"runtimes": [adapter.info().model_dump() for adapter in list_adapters()]}

    @app.get("/api/v1/runtime")
    def runtime() -> dict[str, object]:
        return {
            "active_runtime": active_adapter().info().model_dump(),
            "runtimes": [adapter.info().model_dump() for adapter in list_adapters()],
        }

    @app.get("/api/v1/status")
    def status() -> dict[str, object]:
        return active_adapter().status_projection(status_provider)

    @app.get("/api/v1/catalog/apps")
    def catalog_apps() -> dict[str, object]:
        payload = catalog()
        return {"applications": payload.get("applications", [])}

    @app.get("/api/v1/catalog/apps/{app_name}")
    def catalog_app(app_name: str) -> dict[str, object]:
        for app_spec in catalog().get("applications", []):
            if app_spec.get("name") == app_name:
                return app_spec
        raise HTTPException(status_code=404, detail=f"app not found: {app_name}")

    @app.get("/api/v1/deployments")
    def deployments() -> dict[str, object]:
        records = []
        for app_spec in catalog().get("applications", []):
            deployment = app_spec.get("deployment", {})
            for environment in app_spec.get("environments", []):
                environment_deployment = environment.get("deployment", {})
                records.append(
                    {
                        "app": app_spec.get("name"),
                        "environment": environment.get("name"),
                        "route": environment.get("route"),
                        "controller": deployment.get("controller"),
                        "image": optional_string(environment_deployment.get("image") or deployment.get("image")),
                        "health": optional_string(environment.get("health") or app_spec.get("health")),
                        "sync": optional_string(environment.get("sync") or deployment.get("sync")),
                    }
                )
        return {"deployments": records}

    @app.get("/api/v1/secrets")
    def secrets() -> dict[str, object]:
        records = []
        for app_spec in catalog().get("applications", []):
            for secret in app_spec.get("secrets", []):
                records.append(
                    {
                        "app": app_spec.get("name"),
                        "name": secret.get("name"),
                        "binding": secret.get("binding", "unknown"),
                        "rotation": secret.get("rotation", "unknown"),
                        **secret,
                    }
                )
        return {"secrets": records}

    @app.get("/api/v1/scorecards")
    def scorecards() -> dict[str, object]:
        records = []
        for app_spec in catalog().get("applications", []):
            scorecard = app_spec.get("scorecard", {})
            records.append(
                {
                    "app": app_spec.get("name"),
                    "runtime_profile": scorecard.get("runtime_profile", "unknown"),
                    "has_health_endpoint": scorecard.get("has_health_endpoint", False),
                    "has_network_policy": scorecard.get("has_network_policy", False),
                    "has_owner": scorecard.get("has_owner", bool(app_spec.get("owner"))),
                    **scorecard,
                }
            )
        return {"scorecards": records}

    @app.get("/api/v1/actions")
    def actions() -> dict[str, object]:
        return {
            "actions": [
                {"id": "environment.create", "label": "Create environment", "runtime": active_adapter().name, "dry_run": True},
                {"id": "deployment.promote", "label": "Promote deployment", "runtime": active_adapter().name, "dry_run": True},
                {"id": "app.scaffold", "label": "Scaffold app", "runtime": active_adapter().name, "dry_run": True},
            ]
        }

    @app.post("/api/v1/environments")
    def create_environment(request: EnvironmentRequest, dry_run: bool = True) -> dict[str, object]:
        if not dry_run:
            raise HTTPException(status_code=501, detail="apply mode is not implemented")
        request.action = "create"
        adapter = adapter_for(request.runtime)
        return workflow_response("environment.create", adapter.name, adapter.plan_environment(request), request.model_dump())

    @app.delete("/api/v1/environments/{app_name}/{environment}")
    def delete_environment(app_name: str, environment: str, runtime: str = "kind", dry_run: bool = True) -> dict[str, object]:
        if not dry_run:
            raise HTTPException(status_code=501, detail="apply mode is not implemented")
        adapter = adapter_for(runtime)
        request = EnvironmentRequest(runtime=runtime, action="delete", app=app_name, environment=environment)
        return workflow_response("environment.delete", adapter.name, adapter.plan_environment(request), request.model_dump())

    @app.post("/api/v1/deployments/promote")
    def promote_deployment(request: DeploymentRequest, dry_run: bool = True) -> dict[str, object]:
        if not dry_run:
            raise HTTPException(status_code=501, detail="apply mode is not implemented")
        adapter = adapter_for(request.runtime)
        return workflow_response("deployment.promote", adapter.name, adapter.plan_deployment(request), request.model_dump())

    @app.post("/api/v1/deployments/rollback")
    def rollback_deployment(request: DeploymentRequest, dry_run: bool = True) -> dict[str, object]:
        if not dry_run:
            raise HTTPException(status_code=501, detail="apply mode is not implemented")
        adapter = adapter_for(request.runtime)
        plan = adapter.plan_deployment(request)
        plan.summary = f"would roll back {request.app}/{request.environment} on {adapter.name}"
        return workflow_response("deployment.rollback", adapter.name, plan, request.model_dump())

    @app.post("/api/v1/apps/scaffold")
    def scaffold_app(request: ScaffoldRequest, dry_run: bool = True) -> dict[str, object]:
        if not dry_run:
            raise HTTPException(status_code=501, detail="apply mode is not implemented")
        adapter = adapter_for(request.runtime)
        plan = adapter.plan_environment(
            EnvironmentRequest(runtime=request.runtime, action="create", app=request.app, environment="dev")
        )
        plan.summary = f"would scaffold app {request.app} for {request.owner} on {adapter.name}"
        return workflow_response("app.scaffold", adapter.name, plan, request.model_dump())

    @app.post("/api/v1/workflows/environments/dry-run")
    def environment_dry_run(request: EnvironmentRequest) -> WorkflowResponse:
        adapter = adapter_for(request.runtime)
        plan = adapter.plan_environment(request)
        audit_record = audit.write(
            event="environment.dry_run",
            runtime=adapter.name,
            workflow="environment",
            request=request.model_dump(),
        )
        return WorkflowResponse(runtime=adapter.name, workflow="environment", plan=plan, audit=audit_record)

    @app.post("/api/v1/workflows/deployments/dry-run")
    def deployment_dry_run(request: DeploymentRequest) -> WorkflowResponse:
        adapter = adapter_for(request.runtime)
        plan = adapter.plan_deployment(request)
        audit_record = audit.write(
            event="deployment.dry_run",
            runtime=adapter.name,
            workflow="deployment",
            request=request.model_dump(),
        )
        return WorkflowResponse(runtime=adapter.name, workflow="deployment", plan=plan, audit=audit_record)

    @app.post("/api/v1/workflows/secrets/dry-run")
    def secret_dry_run(request: SecretRequest) -> WorkflowResponse:
        adapter = adapter_for(request.runtime)
        plan = adapter.plan_secret(request)
        audit_record = audit.write(
            event="secret.dry_run",
            runtime=adapter.name,
            workflow="secret",
            request=request.model_dump(),
        )
        return WorkflowResponse(runtime=adapter.name, workflow="secret", plan=plan, audit=audit_record)

    return app


app = create_app()
