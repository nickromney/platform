from app.adapters import get_adapter, list_adapters
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
