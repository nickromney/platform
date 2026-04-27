from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient

from app.main import DEFAULT_AUDIT_PATH, create_app


REPO_ROOT = Path(__file__).resolve().parents[3]


def test_default_audit_path_is_writable_under_tmp_for_read_only_container_root() -> None:
    assert DEFAULT_AUDIT_PATH.is_absolute()
    assert DEFAULT_AUDIT_PATH.is_relative_to(Path("/tmp"))


class FixtureStatusProvider:
    def collect_status(self) -> dict[str, object]:
        return {
            "overall_state": "running",
            "active_variant_path": "kubernetes/kind",
            "actions": [
                {
                    "id": "kind-status",
                    "label": "Kind status",
                    "command": "make -C kubernetes/kind status",
                    "enabled": True,
                }
            ],
            "source": "fixture",
            "source_status": "available",
        }


def assert_schema_shaped(record: dict[str, Any], schema_name: str) -> None:
    schema = json_load(REPO_ROOT / "schemas/idp" / schema_name)

    for field in schema.get("required", []):
        assert field in record

    for field, spec in schema.get("properties", {}).items():
        if field not in record:
            continue
        assert_value_matches_schema_type(record[field], spec["type"], f"{schema_name}:{field}")


def assert_value_matches_schema_type(value: Any, expected: str | list[str], field: str) -> None:
    expected_types = [expected] if isinstance(expected, str) else expected
    type_checks = {
        "array": lambda candidate: isinstance(candidate, list),
        "boolean": lambda candidate: isinstance(candidate, bool),
        "null": lambda candidate: candidate is None,
        "object": lambda candidate: isinstance(candidate, dict),
        "string": lambda candidate: isinstance(candidate, str),
    }
    assert any(type_checks[schema_type](value) for schema_type in expected_types), field


def json_load(path: Path) -> dict[str, Any]:
    import json

    return json.loads(path.read_text(encoding="utf-8"))


def test_health_and_runtime_catalog(tmp_path: Path) -> None:
    client = TestClient(create_app(audit_path=tmp_path / "audit.jsonl"))

    health = client.get("/health")
    assert health.status_code == 200
    assert health.json() == {"status": "healthy", "service": "idp-core"}

    runtimes = client.get("/api/v1/runtimes")
    assert runtimes.status_code == 200
    assert runtimes.json() == {
        "runtimes": [
            {"name": "generic_kubernetes", "description": "Generic Kubernetes workflow adapter"},
            {"name": "kind", "description": "Local kind workflow adapter"},
            {"name": "lima", "description": "Local Lima workflow adapter"},
        ]
    }


def test_public_portal_origins_can_call_api_with_cors(tmp_path: Path) -> None:
    client = TestClient(create_app(audit_path=tmp_path / "audit.jsonl"))

    for origin in ("https://portal.127.0.0.1.sslip.io", "https://portal-api.127.0.0.1.sslip.io"):
        response = client.options(
            "/api/v1/catalog/apps",
            headers={
                "origin": origin,
                "access-control-request-method": "GET",
            },
        )

        assert response.status_code == 200
        assert response.headers["access-control-allow-origin"] == origin
        assert response.headers["access-control-allow-credentials"] == "true"


def test_portal_contract_read_endpoints(tmp_path: Path) -> None:
    client = TestClient(create_app(audit_path=tmp_path / "audit.jsonl"))

    runtime = client.get("/api/v1/runtime")
    assert runtime.status_code == 200
    assert runtime.json()["active_runtime"]["name"] == "kind"

    status = client.get("/api/v1/status")
    assert status.status_code == 200
    assert status.json()["runtime"] == "kind"

    apps = client.get("/api/v1/catalog/apps")
    assert apps.status_code == 200
    assert any(app["name"] == "hello-platform" for app in apps.json()["applications"])

    app = client.get("/api/v1/catalog/apps/hello-platform")
    assert app.status_code == 200
    assert app.json()["name"] == "hello-platform"

    assert client.get("/api/v1/deployments").status_code == 200
    assert client.get("/api/v1/secrets").status_code == 200
    assert client.get("/api/v1/scorecards").status_code == 200
    assert client.get("/api/v1/actions").status_code == 200


def test_status_projection_uses_injected_status_provider(tmp_path: Path) -> None:
    client = TestClient(
        create_app(
            audit_path=tmp_path / "audit.jsonl",
            status_provider=FixtureStatusProvider(),
        )
    )

    response = client.get("/api/v1/status")

    assert response.status_code == 200
    body = response.json()
    assert body["runtime"] == "kind"
    assert body["overall_state"] == "running"
    assert body["overall_state"] != "unknown"
    assert body["active_variant_path"] == "kubernetes/kind"
    assert body["actions"][0]["id"] == "kind-status"
    assert body["source"] == "fixture"
    assert body["source_status"] == "available"
    assert_schema_shaped(body, "status.schema.json")


def test_catalog_derived_read_models_are_schema_shaped(tmp_path: Path) -> None:
    client = TestClient(create_app(audit_path=tmp_path / "audit.jsonl"))

    deployments = client.get("/api/v1/deployments")
    assert deployments.status_code == 200
    deployment_records = deployments.json()["deployments"]
    assert deployment_records
    assert all({"app", "environment", "image", "health", "sync"} <= record.keys() for record in deployment_records)
    for record in deployment_records:
        assert_schema_shaped(record, "deployment.schema.json")

    secrets = client.get("/api/v1/secrets")
    assert secrets.status_code == 200
    secret_records = secrets.json()["secrets"]
    assert secret_records
    for record in secret_records:
        assert_schema_shaped(record, "secret-binding.schema.json")

    scorecards = client.get("/api/v1/scorecards")
    assert scorecards.status_code == 200
    scorecard_records = scorecards.json()["scorecards"]
    assert scorecard_records
    assert all({"app", "runtime_profile", "has_health_endpoint", "has_network_policy", "has_owner"} <= record.keys() for record in scorecard_records)
    for record in scorecard_records:
        assert_schema_shaped(record, "scorecard.schema.json")


def test_catalog_path_can_be_configured_with_environment(tmp_path: Path, monkeypatch) -> None:
    catalog_path = tmp_path / "platform-apps.json"
    catalog_path.write_text(
        """
{
  "applications": [
    {
      "name": "fixture-service",
      "owner": "team-platform",
      "environments": [{"name": "test", "route": "https://fixture.example.test"}],
      "deployment": {"controller": "fixture"},
      "secrets": [{"name": "fixture-secret", "scope": "runtime"}],
      "scorecard": {"tier": "gold"}
    }
  ]
}
""".strip(),
        encoding="utf-8",
    )
    monkeypatch.setenv("IDP_CATALOG_PATH", str(catalog_path))
    client = TestClient(create_app(audit_path=tmp_path / "audit.jsonl"))

    apps = client.get("/api/v1/catalog/apps")
    assert apps.status_code == 200
    assert [app["name"] for app in apps.json()["applications"]] == ["fixture-service"]

    deployment = client.get("/api/v1/deployments")
    assert deployment.status_code == 200
    assert deployment.json()["deployments"] == [
        {
            "app": "fixture-service",
            "environment": "test",
            "route": "https://fixture.example.test",
            "controller": "fixture",
            "image": None,
            "health": None,
            "sync": None,
        }
    ]


def test_portal_contract_workflows_are_dry_run_first(tmp_path: Path) -> None:
    audit_path = tmp_path / "audit.jsonl"
    client = TestClient(create_app(audit_path=audit_path))

    create = client.post(
        "/api/v1/environments?dry_run=true",
        json={"runtime": "kind", "app": "hello-platform", "environment": "preview-nr", "environment_type": "development"},
    )
    assert create.status_code == 200
    assert create.json()["dry_run"] is True
    assert create.json()["action"] == "environment.create"

    delete = client.delete("/api/v1/environments/hello-platform/preview-nr?runtime=kind&dry_run=true")
    assert delete.status_code == 200
    assert delete.json()["action"] == "environment.delete"

    promote = client.post(
        "/api/v1/deployments/promote?dry_run=true",
        json={"runtime": "kind", "app": "hello-platform", "environment": "uat", "image": "registry.local/hello-platform:test"},
    )
    assert promote.status_code == 200
    assert promote.json()["action"] == "deployment.promote"

    rollback = client.post(
        "/api/v1/deployments/rollback?dry_run=true",
        json={"runtime": "kind", "app": "hello-platform", "environment": "uat"},
    )
    assert rollback.status_code == 200
    assert rollback.json()["action"] == "deployment.rollback"

    scaffold = client.post(
        "/api/v1/apps/scaffold?dry_run=true",
        json={"runtime": "kind", "app": "new-service", "owner": "team-dolphin"},
    )
    assert scaffold.status_code == 200
    assert scaffold.json()["action"] == "app.scaffold"

    apply_mode = client.post(
        "/api/v1/environments?dry_run=false",
        json={"runtime": "kind", "app": "hello-platform", "environment": "preview-nr"},
    )
    assert apply_mode.status_code == 501

    apply_delete = client.delete("/api/v1/environments/hello-platform/preview-nr?runtime=kind&dry_run=false")
    assert apply_delete.status_code == 501

    apply_promote = client.post(
        "/api/v1/deployments/promote?dry_run=false",
        json={"runtime": "kind", "app": "hello-platform", "environment": "uat", "image": "registry.local/hello-platform:test"},
    )
    assert apply_promote.status_code == 501

    apply_rollback = client.post(
        "/api/v1/deployments/rollback?dry_run=false",
        json={"runtime": "kind", "app": "hello-platform", "environment": "uat"},
    )
    assert apply_rollback.status_code == 501

    apply_scaffold = client.post(
        "/api/v1/apps/scaffold?dry_run=false",
        json={"runtime": "kind", "app": "new-service", "owner": "team-dolphin"},
    )
    assert apply_scaffold.status_code == 501

    audit_lines = audit_path.read_text(encoding="utf-8").splitlines()
    assert audit_lines
    assert '"action":"environment.create"' in audit_lines[0]
    assert '"dry_run":true' in audit_lines[0]


def test_environment_dry_run_uses_selected_adapter_and_writes_audit(tmp_path: Path) -> None:
    audit_path = tmp_path / "audit.jsonl"
    client = TestClient(create_app(audit_path=audit_path))

    response = client.post(
        "/api/v1/workflows/environments/dry-run",
        json={
            "runtime": "kind",
            "action": "create",
            "app": "hello-platform",
            "environment": "preview-nr",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["dry_run"] is True
    assert body["runtime"] == "kind"
    assert body["workflow"] == "environment"
    assert body["plan"]["summary"] == "would create environment preview-nr for hello-platform on kind"
    assert body["plan"]["commands"] == [
        "make -C kubernetes/kind idp-env ACTION=create APP=hello-platform ENV=preview-nr DRY_RUN=1"
    ]
    assert body["audit"]["event"] == "environment.dry_run"

    audit_lines = audit_path.read_text(encoding="utf-8").splitlines()
    assert len(audit_lines) == 1
    assert '"event":"environment.dry_run"' in audit_lines[0]
    assert '"runtime":"kind"' in audit_lines[0]


def test_deployment_and_secret_dry_runs_are_adapter_backed(tmp_path: Path) -> None:
    client = TestClient(create_app(audit_path=tmp_path / "audit.jsonl"))

    deployment = client.post(
        "/api/v1/workflows/deployments/dry-run",
        json={
            "runtime": "lima",
            "app": "sentiment",
            "environment": "uat",
            "image": "registry.local/sentiment:2026-04-27",
        },
    )
    assert deployment.status_code == 200
    deployment_body = deployment.json()
    assert deployment_body["runtime"] == "lima"
    assert deployment_body["workflow"] == "deployment"
    assert deployment_body["plan"]["commands"] == [
        "make -C kubernetes/lima idp-deployments APP=sentiment ENV=uat IMAGE=registry.local/sentiment:2026-04-27 DRY_RUN=1"
    ]

    secret = client.post(
        "/api/v1/workflows/secrets/dry-run",
        json={
            "runtime": "generic_kubernetes",
            "app": "hello-platform",
            "environment": "dev",
            "secret": "database-url",
            "keys": ["url", "username"],
        },
    )
    assert secret.status_code == 200
    secret_body = secret.json()
    assert secret_body["runtime"] == "generic_kubernetes"
    assert secret_body["workflow"] == "secret"
    assert secret_body["plan"]["commands"] == [
        "kubectl create secret generic database-url --namespace hello-platform-dev --from-literal=url=<redacted> --from-literal=username=<redacted> --dry-run=client -o yaml"
    ]


def test_unknown_runtime_is_rejected(tmp_path: Path) -> None:
    client = TestClient(create_app(audit_path=tmp_path / "audit.jsonl"))

    response = client.post(
        "/api/v1/workflows/environments/dry-run",
        json={
            "runtime": "docker-compose",
            "action": "create",
            "app": "hello-platform",
            "environment": "preview-nr",
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "unknown runtime: docker-compose"
