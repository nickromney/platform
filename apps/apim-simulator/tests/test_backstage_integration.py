from __future__ import annotations

import json
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]


def test_backstage_catalog_metadata_describes_gateway_and_management_apis() -> None:
    docs = list(yaml.safe_load_all((REPO_ROOT / "catalog-info.yaml").read_text(encoding="utf-8")))

    component = next(doc for doc in docs if doc["kind"] == "Component" and doc["metadata"]["name"] == "apim-simulator")
    api_names = {doc["metadata"]["name"] for doc in docs if doc["kind"] == "API"}

    assert component["spec"]["providesApis"] == [
        "apim-simulator-gateway-api",
        "apim-simulator-management-api",
    ]
    assert api_names == {"apim-simulator-gateway-api", "apim-simulator-management-api"}
    assert all("openapi: 3.0.3" in doc["spec"]["definition"] for doc in docs if doc["kind"] == "API")


def test_backstage_compose_overlay_is_opt_in_and_image_based() -> None:
    compose = yaml.safe_load((REPO_ROOT / "compose.backstage.yml").read_text(encoding="utf-8"))
    service = compose["services"]["backstage"]

    assert service["profiles"] == ["backstage"]
    assert service["build"] == {
        "context": "${BACKSTAGE_BUILD_CONTEXT:-./backstage/app}",
        "dockerfile": "${BACKSTAGE_DOCKERFILE:-Dockerfile}",
    }
    assert service["image"] == "${BACKSTAGE_IMAGE:-apim-simulator-backstage:local}"
    assert "${BACKSTAGE_PORT:-7007}:7007" in service["ports"]
    assert "./catalog-info.yaml:/app/catalog/apim-simulator-catalog-info.yaml:ro" in service["volumes"]
    assert service["depends_on"]["apim-simulator"]["condition"] == "service_started"


def test_backstage_app_is_standalone_and_not_platform_scoped() -> None:
    production = yaml.safe_load((REPO_ROOT / "backstage/app/app-config.production.yaml").read_text(encoding="utf-8"))
    app = (REPO_ROOT / "backstage/app/packages/app/src/App.tsx").read_text(encoding="utf-8")

    targets = [location["target"] for location in production["catalog"]["locations"]]
    assert targets == [
        "./catalog/apim-simulator-catalog-info.yaml",
        "./catalog/apim-simulator-org.yaml",
    ]
    assert "ProxiedSignInPage" not in app
    assert "subnetcalc" not in (REPO_ROOT / "backstage/app/app-config.production.yaml").read_text(encoding="utf-8")
    assert "platform" not in (REPO_ROOT / "backstage/app/app-config.production.yaml").read_text(encoding="utf-8")


def test_backstage_app_keeps_the_standalone_portal_minimal() -> None:
    frontend_package = json.loads((REPO_ROOT / "backstage/app/packages/app/package.json").read_text(encoding="utf-8"))
    backend_package = json.loads(
        (REPO_ROOT / "backstage/app/packages/backend/package.json").read_text(encoding="utf-8")
    )
    backend = (REPO_ROOT / "backstage/app/packages/backend/src/index.ts").read_text(encoding="utf-8")
    app = (REPO_ROOT / "backstage/app/packages/app/src/App.tsx").read_text(encoding="utf-8")

    assert "@backstage/plugin-api-docs" in frontend_package["dependencies"]
    assert "@backstage/plugin-catalog" in frontend_package["dependencies"]
    assert "@backstage/plugin-auth-backend" in backend_package["dependencies"]
    assert "@backstage/plugin-auth-backend-module-guest-provider" in backend_package["dependencies"]
    assert "@backstage/plugin-catalog-backend" in backend_package["dependencies"]
    assert "@backstage/plugin-auth-backend-module-guest-provider" in backend
    assert "@backstage/plugin-catalog-backend" in backend
    assert "@backstage/plugin-api-docs/alpha" in app
    assert "providers={['guest']}" in app

    excluded_plugins = {
        "@backstage/plugin-kubernetes",
        "@backstage/plugin-mcp-actions-backend",
        "@backstage/plugin-notifications",
        "@backstage/plugin-scaffolder",
        "@backstage/plugin-search",
        "@backstage/plugin-techdocs",
    }
    installed_plugins = set(frontend_package["dependencies"]) | set(backend_package["dependencies"])
    assert installed_plugins.isdisjoint(excluded_plugins)


def test_makefile_exposes_boolean_backstage_entrypoints() -> None:
    makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")

    assert "BACKSTAGE_ENABLED ?= false" in makefile
    assert "BACKSTAGE_BUILD_ENABLED ?= true" in makefile
    assert "BACKSTAGE_BUILD_CONTEXT ?= ./backstage/app" in makefile
    assert "COMPOSE_BACKSTAGE_OVERLAY := $(if $(filter true,$(BACKSTAGE_ENABLED))" in makefile
    assert "up-backstage: build-backstage" in makefile
    assert "smoke-backstage:" in makefile
