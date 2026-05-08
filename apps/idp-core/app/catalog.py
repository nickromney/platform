import json
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class CatalogModel(BaseModel):
    model_config = ConfigDict(extra="allow")


class EnvironmentSpec(CatalogModel):
    name: str | None = None
    type: str | None = None
    namespace: str | None = None
    route: str | None = None
    rbac: dict[str, Any] = Field(default_factory=dict)
    deployment: dict[str, Any] = Field(default_factory=dict)
    health: Any = None
    sync: Any = None


class SecretSpec(CatalogModel):
    name: str | None = None
    binding: str = "unknown"
    rotation: str = "unknown"


class ScorecardSpec(CatalogModel):
    runtime_profile: str = "unknown"
    has_health_endpoint: bool = False
    has_network_policy: bool = False
    has_owner: bool = False


class ApplicationSpec(CatalogModel):
    name: str | None = None
    display_name: str | None = None
    owner: str | None = None
    lifecycle: str | None = None
    source: dict[str, Any] = Field(default_factory=dict)
    deployment: dict[str, Any] = Field(default_factory=dict)
    environments: list[EnvironmentSpec] = Field(default_factory=list)
    secrets: list[SecretSpec] = Field(default_factory=list)
    scorecard: ScorecardSpec = Field(default_factory=ScorecardSpec)
    health: Any = None


class CatalogDocument(CatalogModel):
    schema_version: str | None = None
    core_components: dict[str, Any] = Field(default_factory=dict)
    applications: list[ApplicationSpec] = Field(default_factory=list)


class DeploymentRecord(CatalogModel):
    app: str | None = None
    environment: str | None = None
    route: str | None = None
    controller: Any = None
    image: str | None = None
    health: str | None = None
    sync: str | None = None


class SecretBinding(CatalogModel):
    app: str | None = None
    name: str | None = None
    binding: str = "unknown"
    rotation: str = "unknown"


class ScorecardRecord(CatalogModel):
    app: str | None = None
    runtime_profile: str = "unknown"
    has_health_endpoint: bool = False
    has_network_policy: bool = False
    has_owner: bool = False


class ApplicationSurfaceRecord(CatalogModel):
    app: str | None = None
    display_name: str | None = None
    owner: str | None = None
    lifecycle: str | None = None
    environment: str | None = None
    environment_type: str | None = None
    namespace: str | None = None
    route: str | None = None
    rbac_group: str | None = None
    source_path: str | None = None
    kubernetes_label_selector: str | None = None


def load_catalog(path: Path) -> CatalogDocument:
    return CatalogDocument.model_validate(json.loads(path.read_text(encoding="utf-8")))


def application_specs(catalog: CatalogDocument) -> list[ApplicationSpec]:
    return catalog.applications


def find_application(catalog: CatalogDocument, app_name: str) -> ApplicationSpec | None:
    for app_spec in application_specs(catalog):
        if app_spec.name == app_name:
            return app_spec
    return None


def deployment_records(catalog: CatalogDocument) -> list[DeploymentRecord]:
    records: list[DeploymentRecord] = []
    for app_spec in application_specs(catalog):
        deployment = app_spec.deployment
        for environment in app_spec.environments:
            environment_deployment = environment.deployment
            records.append(
                DeploymentRecord(
                    app=app_spec.name,
                    environment=environment.name,
                    route=environment.route,
                    controller=deployment.get("controller"),
                    image=_optional_string(environment_deployment.get("image") or deployment.get("image")),
                    health=_optional_string(environment.health or app_spec.health),
                    sync=_optional_string(environment.sync or deployment.get("sync")),
                )
            )
    return records


def secret_bindings(catalog: CatalogDocument) -> list[SecretBinding]:
    records: list[SecretBinding] = []
    for app_spec in application_specs(catalog):
        for secret in app_spec.secrets:
            records.append(SecretBinding.model_validate({"app": app_spec.name, **secret.model_dump()}))
    return records


def scorecard_records(catalog: CatalogDocument) -> list[ScorecardRecord]:
    records: list[ScorecardRecord] = []
    for app_spec in application_specs(catalog):
        scorecard = app_spec.scorecard
        scorecard_payload = scorecard.model_dump()
        if "has_owner" not in scorecard.model_fields_set:
            scorecard_payload["has_owner"] = bool(app_spec.owner)
        records.append(
            ScorecardRecord.model_validate(
                {
                    "app": app_spec.name,
                    **scorecard_payload,
                }
            )
        )
    return records


def application_surface_records(catalog: CatalogDocument) -> list[ApplicationSurfaceRecord]:
    records: list[ApplicationSurfaceRecord] = []
    for app_spec in application_specs(catalog):
        for environment in app_spec.environments:
            if not environment.route:
                continue
            records.append(
                ApplicationSurfaceRecord(
                    app=app_spec.name,
                    display_name=app_spec.display_name,
                    owner=app_spec.owner,
                    lifecycle=app_spec.lifecycle,
                    environment=environment.name,
                    environment_type=environment.type,
                    namespace=environment.namespace,
                    route=environment.route,
                    rbac_group=_optional_string(environment.rbac.get("group")),
                    source_path=_optional_string(app_spec.source.get("path")),
                    kubernetes_label_selector=f"app={app_spec.name}" if app_spec.name else None,
                )
            )
    return records


def _optional_string(value: Any) -> str | None:
    return value if isinstance(value, str) else None
