from pathlib import Path

from app.adapters import PlatformStatusScriptProvider, get_adapter, list_adapters
from app.models import DeploymentRequest, EnvironmentRequest, SecretRequest


def test_all_adapters_implement_dry_run_contract() -> None:
    adapters = list_adapters()

    assert [adapter.name for adapter in adapters] == ["generic_kubernetes", "kind", "lima"]

    for adapter in adapters:
        environment = adapter.plan_environment(
            EnvironmentRequest(runtime=adapter.name, action="create", app="hello-platform", environment="preview")
        )
        deployment = adapter.plan_deployment(
            DeploymentRequest(
                runtime=adapter.name,
                app="hello-platform",
                environment="preview",
                image="registry.local/hello-platform:test",
            )
        )
        secret = adapter.plan_secret(
            SecretRequest(
                runtime=adapter.name,
                app="hello-platform",
                environment="preview",
                secret="api-token",
                keys=["token"],
            )
        )

        assert environment.dry_run is True
        assert deployment.dry_run is True
        assert secret.dry_run is True
        assert environment.runtime == adapter.name
        assert deployment.runtime == adapter.name
        assert secret.runtime == adapter.name
        assert environment.commands
        assert deployment.commands
        assert secret.commands


def test_get_adapter_returns_named_adapter() -> None:
    assert get_adapter("kind").name == "kind"
    assert get_adapter("lima").name == "lima"
    assert get_adapter("generic_kubernetes").name == "generic_kubernetes"
    assert get_adapter("missing") is None


def test_status_projection_is_unavailable_without_injected_provider() -> None:
    status = get_adapter("kind").status_projection()

    assert status["runtime"] == "kind"
    assert status["overall_state"] == "unknown"
    assert status["source"] == "unavailable"
    assert status["source_status"] == "unconfigured"
    assert status["actions"] == []


def test_platform_status_script_provider_is_injectable(tmp_path: Path) -> None:
    status_script = tmp_path / "platform-status.sh"
    status_script.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != "--execute --output json" ]]; then
  exit 42
fi
printf '%s\n' '{"overall_state":"running","active_variant_path":"kubernetes/kind","actions":[]}'
""",
        encoding="utf-8",
    )
    status_script.chmod(0o755)

    provider = PlatformStatusScriptProvider(command=[str(status_script), "--execute", "--output", "json"])
    status = get_adapter("kind").status_projection(provider)

    assert status["runtime"] == "kind"
    assert status["overall_state"] == "running"
    assert status["active_variant_path"] == "kubernetes/kind"
    assert status["source"] == "platform-status-script"
    assert status["source_status"] == "available"
