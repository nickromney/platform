import json
import subprocess
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Protocol, Sequence

from app.models import DeploymentRequest, DryRunPlan, EnvironmentRequest, RuntimeInfo, SecretRequest
from app.paths import discover_repo_root

REPO_ROOT = discover_repo_root(Path(__file__))


def _namespace(app: str, environment: str) -> str:
    return f"{app}-{environment}"


class StatusProvider(Protocol):
    def collect_status(self) -> dict[str, object]:
        ...


class UnavailableStatusProvider(StatusProvider):
    def collect_status(self) -> dict[str, object]:
        return {
            "overall_state": "unknown",
            "active_variant_path": None,
            "actions": [],
            "source": "unavailable",
            "source_status": "unconfigured",
            "detail": "no status provider configured",
        }


class PlatformStatusScriptProvider(StatusProvider):
    def __init__(
        self,
        command: Sequence[str] | None = None,
        *,
        cwd: Path = REPO_ROOT,
        timeout_seconds: float = 15,
    ) -> None:
        self.command = list(command or [str(REPO_ROOT / "scripts/platform-status.sh"), "--execute", "--output", "json"])
        self.cwd = cwd
        self.timeout_seconds = timeout_seconds

    def collect_status(self) -> dict[str, object]:
        try:
            result = subprocess.run(
                self.command,
                cwd=self.cwd,
                capture_output=True,
                check=False,
                text=True,
                timeout=self.timeout_seconds,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            return self._unavailable(str(exc))

        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip() or f"exit code {result.returncode}"
            return self._unavailable(detail)

        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            return self._unavailable(f"invalid json: {exc}")

        if not isinstance(payload, dict):
            return self._unavailable("status script did not return a JSON object")

        payload.setdefault("source", "platform-status-script")
        payload.setdefault("source_status", "available")
        return payload

    def _unavailable(self, detail: str) -> dict[str, object]:
        return {
            "overall_state": "unknown",
            "active_variant_path": None,
            "actions": [],
            "source": "platform-status-script",
            "source_status": "unavailable",
            "detail": detail,
        }


class RuntimeAdapter(ABC):
    name: str
    description: str

    def info(self) -> RuntimeInfo:
        return RuntimeInfo(name=self.name, description=self.description)

    def status_projection(self, status_provider: StatusProvider | None = None) -> dict[str, object]:
        payload = dict((status_provider or UnavailableStatusProvider()).collect_status())
        payload["runtime"] = self.name
        payload.setdefault("overall_state", "unknown")
        payload.setdefault("active_variant_path", None)
        payload.setdefault("actions", [])
        payload.setdefault("source", "status-provider")
        payload.setdefault("source_status", "available")
        return payload

    @abstractmethod
    def plan_environment(self, request: EnvironmentRequest) -> DryRunPlan:
        raise NotImplementedError

    @abstractmethod
    def plan_deployment(self, request: DeploymentRequest) -> DryRunPlan:
        raise NotImplementedError

    @abstractmethod
    def plan_secret(self, request: SecretRequest) -> DryRunPlan:
        raise NotImplementedError


class GenericKubernetesAdapter(RuntimeAdapter):
    name = "generic_kubernetes"
    description = "Generic Kubernetes workflow adapter"

    def plan_environment(self, request: EnvironmentRequest) -> DryRunPlan:
        namespace = _namespace(request.app, request.environment)
        return DryRunPlan(
            runtime=self.name,
            summary=f"would {request.action} environment {request.environment} for {request.app} on generic Kubernetes",
            commands=[
                f"kubectl {'create namespace' if request.action == 'create' else 'delete namespace'} {namespace} --dry-run=client -o yaml"
            ],
            manifests=[f"Namespace/{namespace}"],
        )

    def plan_deployment(self, request: DeploymentRequest) -> DryRunPlan:
        namespace = _namespace(request.app, request.environment)
        return DryRunPlan(
            runtime=self.name,
            summary=f"would deploy {request.image} to {request.app}/{request.environment} on generic Kubernetes",
            commands=[
                f"kubectl set image deployment/{request.app} {request.app}={request.image} --namespace {namespace} --dry-run=server"
            ],
            manifests=[f"Deployment/{namespace}/{request.app}"],
        )

    def plan_secret(self, request: SecretRequest) -> DryRunPlan:
        namespace = _namespace(request.app, request.environment)
        literals = " ".join(f"--from-literal={key}=<redacted>" for key in request.keys)
        return DryRunPlan(
            runtime=self.name,
            summary=f"would reconcile secret {request.secret} for {request.app}/{request.environment} on generic Kubernetes",
            commands=[
                f"kubectl create secret generic {request.secret} --namespace {namespace} {literals} --dry-run=client -o yaml"
            ],
            manifests=[f"Secret/{namespace}/{request.secret}"],
        )


class MakefileRuntimeAdapter(RuntimeAdapter):
    make_dir: str
    display_name: str

    def plan_environment(self, request: EnvironmentRequest) -> DryRunPlan:
        return DryRunPlan(
            runtime=self.name,
            summary=f"would {request.action} environment {request.environment} for {request.app} on {self.display_name}",
            commands=[
                f"make -C {self.make_dir} idp-env ACTION={request.action} APP={request.app} ENV={request.environment} DRY_RUN=1"
            ],
            manifests=[f"EnvironmentRequest/{request.app}/{request.environment}"],
        )

    def plan_deployment(self, request: DeploymentRequest) -> DryRunPlan:
        return DryRunPlan(
            runtime=self.name,
            summary=f"would deploy {request.image} to {request.app}/{request.environment} on {self.display_name}",
            commands=[
                f"make -C {self.make_dir} idp-deployments APP={request.app} ENV={request.environment} IMAGE={request.image} DRY_RUN=1"
            ],
            manifests=[f"Deployment/{request.app}/{request.environment}"],
        )

    def plan_secret(self, request: SecretRequest) -> DryRunPlan:
        keys = ",".join(request.keys)
        return DryRunPlan(
            runtime=self.name,
            summary=f"would reconcile secret {request.secret} for {request.app}/{request.environment} on {self.display_name}",
            commands=[
                f"make -C {self.make_dir} idp-secrets APP={request.app} ENV={request.environment} SECRET={request.secret} KEYS={keys} DRY_RUN=1"
            ],
            manifests=[f"Secret/{request.app}/{request.environment}/{request.secret}"],
        )


class KindAdapter(MakefileRuntimeAdapter):
    name = "kind"
    description = "Local kind workflow adapter"
    make_dir = "kubernetes/kind"
    display_name = "kind"


class LimaAdapter(MakefileRuntimeAdapter):
    name = "lima"
    description = "Local Lima workflow adapter"
    make_dir = "kubernetes/lima"
    display_name = "lima"


_ADAPTERS: tuple[RuntimeAdapter, ...] = (GenericKubernetesAdapter(), KindAdapter(), LimaAdapter())


def list_adapters() -> list[RuntimeAdapter]:
    return list(_ADAPTERS)


def get_adapter(name: str) -> RuntimeAdapter | None:
    return next((adapter for adapter in _ADAPTERS if adapter.name == name), None)
