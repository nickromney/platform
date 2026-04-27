from pathlib import Path

from fastapi.testclient import TestClient

from app.main import create_app


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
