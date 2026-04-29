from __future__ import annotations

import json
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from app.compat_report import build_compat_report
from app.config import ClientCertificateMode, GatewayConfig, RouteConfig, TenantAccessConfig
from app.main import create_app
from app.terraform_import import config_from_tofu_show_json, import_from_tofu_show_json
from app.urls import http_url


def _tf_json(resources: list[dict]) -> dict:
    return {"values": {"root_module": {"resources": resources}}}


@pytest.mark.contract("TF-IMPORT-MVP")
def test_config_from_tofu_show_json_mvp() -> None:
    tf = _tf_json(
        [
            {
                "address": "azurerm_api_management_product.app_a",
                "type": "azurerm_api_management_product",
                "name": "app_a",
                "values": {"product_id": "app-a", "display_name": "App A", "subscription_required": True},
            },
            {
                "address": "azurerm_api_management_api.app_a",
                "type": "azurerm_api_management_api",
                "name": "app_a",
                "values": {"name": "api", "path": "app-a", "service_url": http_url("upstream")},
            },
            {
                "address": "azurerm_api_management_api_operation.health",
                "type": "azurerm_api_management_api_operation",
                "name": "health",
                "values": {"api_name": "api", "operation_id": "health", "method": "GET", "url_template": "/health"},
            },
            {
                "address": "azurerm_api_management_product_api.app_a",
                "type": "azurerm_api_management_product_api",
                "name": "app_a",
                "values": {"product_id": "app-a", "api_name": "api"},
            },
            {
                "address": "azurerm_api_management_subscription.sub",
                "type": "azurerm_api_management_subscription",
                "name": "sub",
                "values": {
                    "subscription_id": "sub1",
                    "display_name": "demo",
                    "primary_key": "good",
                    "secondary_key": "good2",
                    "product_id": "app-a",
                },
            },
            {
                "address": "azurerm_api_management_api_policy.api",
                "type": "azurerm_api_management_api_policy",
                "name": "api",
                "values": {
                    "api_name": "api",
                    "xml_content": "<policies><inbound><base/></inbound><backend/><outbound/><on-error/></policies>",
                },
            },
            {
                "address": "azurerm_api_management_api_operation_policy.op",
                "type": "azurerm_api_management_api_operation_policy",
                "name": "op",
                "values": {
                    "api_name": "api",
                    "operation_id": "health",
                    "xml_content": "<policies><inbound><base/></inbound><backend/><outbound/><on-error/></policies>",
                },
            },
        ]
    )

    cfg = config_from_tofu_show_json(tf)
    assert cfg.apis["api"].path == "app-a"
    assert cfg.apis["api"].upstream_base_url == http_url("upstream")
    assert cfg.apis["api"].products == ["app-a"]
    assert "health" in cfg.apis["api"].operations
    assert cfg.subscription.subscriptions["sub1"].keys.primary == "good"
    assert cfg.subscription.subscriptions["sub1"].products == ["app-a"]


def test_management_import_applies_routes() -> None:
    tf = _tf_json(
        [
            {
                "address": "azurerm_api_management_product.app_a",
                "type": "azurerm_api_management_product",
                "name": "app_a",
                "values": {"product_id": "app-a", "display_name": "App A", "subscription_required": True},
            },
            {
                "address": "azurerm_api_management_api.app_a",
                "type": "azurerm_api_management_api",
                "name": "app_a",
                "values": {"name": "api", "path": "app-a", "service_url": http_url("upstream")},
            },
            {
                "address": "azurerm_api_management_api_operation.health",
                "type": "azurerm_api_management_api_operation",
                "name": "health",
                "values": {"api_name": "api", "operation_id": "health", "method": "GET", "url_template": "/health"},
            },
            {
                "address": "azurerm_api_management_product_api.app_a",
                "type": "azurerm_api_management_product_api",
                "name": "app_a",
                "values": {"product_id": "app-a", "api_name": "api"},
            },
            {
                "address": "azurerm_api_management_subscription.sub",
                "type": "azurerm_api_management_subscription",
                "name": "sub",
                "values": {
                    "subscription_id": "sub1",
                    "display_name": "demo",
                    "primary_key": "good",
                    "secondary_key": "good2",
                    "product_id": "app-a",
                },
            },
        ]
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.url == httpx.URL(http_url("upstream/health"))
        return httpx.Response(200, json={"ok": True})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            tenant_access=TenantAccessConfig(enabled=True, primary_key="t1"),
            routes=[RouteConfig(name="bootstrap", path_prefix="/", upstream_base_url=http_url("bootstrap"))],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        imported = client.post(
            "/apim/management/import/tofu-show",
            headers={"X-Apim-Tenant-Key": "t1"},
            json=tf,
        )
        assert imported.status_code == 200
        assert imported.json()["routes"] >= 1

        ok = client.get("/app-a/health", headers={"Ocp-Apim-Subscription-Key": "good"})
        assert ok.status_code == 200


def test_import_from_tofu_show_json_supports_openapi_version_sets_and_backend_credentials() -> None:
    fixture = Path(__file__).parent / "fixtures" / "tofu_show" / "sample.json"
    payload = json.loads(fixture.read_text(encoding="utf-8"))

    result = import_from_tofu_show_json(payload)
    cfg = result.config

    assert cfg.api_version_sets["sample-version-set"].version_header_name == "x-api-version"
    assert cfg.apis["sample-api"].api_version_set == "sample-version-set"
    assert cfg.apis["sample-api"].subscription_header_names == ["X-Sample-Key"]
    assert cfg.apis["sample-api"].subscription_query_param_names == ["sample-key"]
    assert sorted(cfg.apis["sample-api"].operations) == ["createWidget", "health"]
    assert cfg.backends["sample-backend"].authorization_scheme == "Bearer"
    assert cfg.backends["sample-backend"].authorization_parameter == "{{backend-secret}}"
    assert cfg.named_values["backend-secret"].value_from_key_vault is not None
    assert any(item.status == "adapted" and item.feature == "value_from_key_vault" for item in result.diagnostics)


def test_config_from_tofu_show_json_imports_azurerm_service_subset() -> None:
    tf = _tf_json(
        [
            {
                "address": "azurerm_api_management.this",
                "type": "azurerm_api_management",
                "name": "this",
                "values": {
                    "name": "demo-apim",
                    "public_network_access_enabled": False,
                    "virtual_network_type": "Internal",
                    "hostname_configuration": [
                        {
                            "proxy": [
                                {
                                    "host_name": "api.example.test",
                                    "default_ssl_binding": True,
                                    "negotiate_client_certificate": True,
                                }
                            ],
                            "management": [{"host_name": "mgmt.example.test"}],
                        }
                    ],
                },
            }
        ]
    )

    cfg = config_from_tofu_show_json(tf)

    assert cfg.service.name == "demo-apim"
    assert cfg.service.display_name == "demo-apim"
    assert cfg.service.public_network_access_enabled is False
    assert cfg.service.virtual_network_type == "Internal"
    assert [item.host_name for item in cfg.service.hostname_configurations] == [
        "mgmt.example.test",
        "api.example.test",
    ]
    assert cfg.service.hostname_configurations[1].default_ssl_binding is True
    assert cfg.client_certificate.mode == ClientCertificateMode.Optional


def test_config_from_tofu_show_json_imports_api_schemas_and_operation_metadata() -> None:
    tf = _tf_json(
        [
            {
                "address": "azurerm_api_management_api.weather",
                "type": "azurerm_api_management_api",
                "name": "weather",
                "values": {"name": "weather", "path": "weather", "service_url": http_url("weather-upstream")},
            },
            {
                "address": "azurerm_api_management_api_schema.weather_response",
                "type": "azurerm_api_management_api_schema",
                "name": "weather_response",
                "values": {
                    "api_name": "weather",
                    "schema_id": "WeatherResponse",
                    "content_type": "application/json",
                    "value": '{"type":"object","properties":{"temperature":{"type":"number"}}}',
                },
            },
            {
                "address": "azurerm_api_management_api_operation.current",
                "type": "azurerm_api_management_api_operation",
                "name": "current",
                "values": {
                    "api_name": "weather",
                    "operation_id": "current",
                    "method": "GET",
                    "url_template": "/current/{city}",
                    "description": "Get current weather",
                    "template_parameter": [
                        {
                            "name": "city",
                            "required": True,
                            "type": "string",
                            "description": "City slug",
                        }
                    ],
                    "request": [
                        {
                            "description": "Optional request metadata",
                            "header": [
                                {
                                    "name": "x-region",
                                    "required": False,
                                    "type": "string",
                                    "description": "Preferred region",
                                }
                            ],
                            "query_parameter": [
                                {
                                    "name": "units",
                                    "required": False,
                                    "type": "string",
                                    "values": ["metric", "imperial"],
                                }
                            ],
                        }
                    ],
                    "response": [
                        {
                            "status_code": 200,
                            "description": "Weather payload",
                            "representation": [
                                {
                                    "content_type": "application/json",
                                    "schema_id": "WeatherResponse",
                                    "type_name": "WeatherResponse",
                                    "example": [{"name": "ok", "value": {"temperature": 21}}],
                                }
                            ],
                        }
                    ],
                },
            },
        ]
    )

    cfg = config_from_tofu_show_json(tf)
    api = cfg.apis["weather"]
    operation = api.operations["current"]
    schema = api.schemas["WeatherResponse"]

    assert schema.content_type == "application/json"
    assert "temperature" in (schema.value or "")
    assert operation.description == "Get current weather"
    assert operation.template_parameters[0].name == "city"
    assert operation.request is not None
    assert operation.request.headers[0].name == "x-region"
    assert operation.request.query_parameters[0].values == ["metric", "imperial"]
    assert operation.responses[0].status_code == 200
    assert operation.responses[0].representations[0].schema_id == "WeatherResponse"
    assert operation.responses[0].representations[0].examples[0].name == "ok"


def test_config_from_tofu_show_json_imports_tags_and_tag_links() -> None:
    tf = _tf_json(
        [
            {
                "address": "azurerm_api_management_product.starter",
                "type": "azurerm_api_management_product",
                "name": "starter",
                "values": {"product_id": "starter", "display_name": "Starter", "subscription_required": True},
            },
            {
                "address": "azurerm_api_management_api.weather",
                "type": "azurerm_api_management_api",
                "name": "weather",
                "values": {"name": "weather", "path": "weather", "service_url": http_url("weather-upstream")},
            },
            {
                "address": "azurerm_api_management_api_operation.current",
                "type": "azurerm_api_management_api_operation",
                "name": "current",
                "values": {
                    "api_name": "weather",
                    "operation_id": "current",
                    "method": "GET",
                    "url_template": "/current",
                },
            },
            {
                "address": "azurerm_api_management_tag.starter",
                "type": "azurerm_api_management_tag",
                "name": "starter",
                "values": {"name": "starter", "display_name": "Starter"},
            },
            {
                "address": "azurerm_api_management_api_tag.weather",
                "type": "azurerm_api_management_api_tag",
                "name": "weather",
                "values": {"api_id": "/subscriptions/test/apis/weather", "name": "starter"},
            },
            {
                "address": "azurerm_api_management_product_tag.starter",
                "type": "azurerm_api_management_product_tag",
                "name": "starter",
                "values": {"api_management_product_id": "/subscriptions/test/products/starter", "name": "starter"},
            },
            {
                "address": "azurerm_api_management_api_operation_tag.current",
                "type": "azurerm_api_management_api_operation_tag",
                "name": "current",
                "values": {
                    "api_operation_id": "/subscriptions/test/apis/weather/operations/current",
                    "name": "featured",
                    "display_name": "Featured",
                },
            },
        ]
    )

    result = import_from_tofu_show_json(tf)
    cfg = result.config

    assert cfg.tags["starter"].display_name == "Starter"
    assert cfg.tags["featured"].display_name == "Featured"
    assert cfg.apis["weather"].tags == ["starter"]
    assert cfg.products["starter"].tags == ["starter"]
    assert cfg.apis["weather"].operations["current"].tags == ["featured"]

    report = build_compat_report(tf)
    assert report["config_summary"]["tags"] == 2
    supported_features = {item["feature"] for item in report["supported"]}
    assert "tag" in supported_features
    assert "tag:starter" in supported_features
    assert "tag:featured" in supported_features


def test_config_from_tofu_show_json_imports_groups_and_product_group_links() -> None:
    tf = _tf_json(
        [
            {
                "address": "azurerm_api_management_product.starter",
                "type": "azurerm_api_management_product",
                "name": "starter",
                "values": {"product_id": "starter", "display_name": "Starter", "subscription_required": True},
            },
            {
                "address": "azurerm_api_management_group.developers",
                "type": "azurerm_api_management_group",
                "name": "developers",
                "values": {
                    "name": "developers",
                    "display_name": "Developers",
                    "description": "Internal developers",
                    "type": "custom",
                },
            },
            {
                "address": "azurerm_api_management_product_group.starter",
                "type": "azurerm_api_management_product_group",
                "name": "starter",
                "values": {"product_id": "/subscriptions/test/products/starter", "group_name": "developers"},
            },
        ]
    )

    result = import_from_tofu_show_json(tf)
    cfg = result.config

    assert cfg.groups["developers"].name == "Developers"
    assert cfg.groups["developers"].description == "Internal developers"
    assert cfg.products["starter"].groups == ["developers"]

    report = build_compat_report(tf)
    assert report["config_summary"]["groups"] == 1
    supported_features = {item["feature"] for item in report["supported"]}
    assert "group" in supported_features
    assert "group:developers" in supported_features


def test_config_from_tofu_show_json_imports_api_revisions_and_releases_metadata() -> None:
    tf = _tf_json(
        [
            {
                "address": "azurerm_api_management_api.weather_rev1",
                "type": "azurerm_api_management_api",
                "name": "weather_rev1",
                "values": {
                    "name": "weather",
                    "revision": "1",
                    "path": "weather-v1",
                    "service_url": http_url("weather-upstream-v1"),
                    "revision_description": "Initial revision",
                    "is_current": False,
                    "is_online": False,
                },
            },
            {
                "address": "azurerm_api_management_api.weather_rev2",
                "type": "azurerm_api_management_api",
                "name": "weather_rev2",
                "values": {
                    "name": "weather",
                    "revision": "2",
                    "path": "weather",
                    "service_url": http_url("weather-upstream-v2"),
                    "revision_description": "Current revision",
                    "source_api_id": "/subscriptions/test/apis/weather;rev=1",
                    "is_current": True,
                    "is_online": True,
                },
            },
            {
                "address": "azurerm_api_management_api_release.public",
                "type": "azurerm_api_management_api_release",
                "name": "public",
                "values": {
                    "name": "public",
                    "api_id": "/subscriptions/test/apis/weather;rev=2",
                    "notes": "Shipped publicly",
                },
            },
        ]
    )

    result = import_from_tofu_show_json(tf)
    cfg = result.config
    api = cfg.apis["weather"]

    assert api.path == "weather"
    assert api.upstream_base_url == http_url("weather-upstream-v2")
    assert api.revision == "2"
    assert api.is_current is True
    assert api.is_online is True
    assert api.revisions["1"].description == "Initial revision"
    assert api.revisions["2"].source_api_id == "/subscriptions/test/apis/weather;rev=1"
    assert api.releases["public"].revision == "2"
    assert api.releases["public"].notes == "Shipped publicly"

    report = build_compat_report(tf)
    assert report["config_summary"]["api_revisions"] == 2
    assert report["config_summary"]["api_releases"] == 1
    supported_features = {item["feature"] for item in report["supported"]}
    adapted_features = {item["feature"] for item in report["adapted"]}
    assert "release:public" in supported_features
    assert "revisions" in adapted_features


def test_config_from_tofu_show_json_imports_users_and_group_user_links() -> None:
    tf = _tf_json(
        [
            {
                "address": "azurerm_api_management_group.developers",
                "type": "azurerm_api_management_group",
                "name": "developers",
                "values": {"name": "developers", "display_name": "Developers", "type": "custom"},
            },
            {
                "address": "azurerm_api_management_user.alice",
                "type": "azurerm_api_management_user",
                "name": "alice",
                "values": {
                    "user_id": "alice",
                    "email": "alice@example.com",
                    "first_name": "Alice",
                    "last_name": "Dev",
                    "note": "Internal developer",
                    "state": "active",
                    "confirmation": "invite",
                    "password": "ignored-locally",
                },
            },
            {
                "address": "azurerm_api_management_group_user.alice",
                "type": "azurerm_api_management_group_user",
                "name": "alice",
                "values": {"group_name": "developers", "user_id": "alice"},
            },
        ]
    )

    result = import_from_tofu_show_json(tf)
    cfg = result.config

    assert cfg.users["alice"].email == "alice@example.com"
    assert cfg.users["alice"].first_name == "Alice"
    assert cfg.users["alice"].last_name == "Dev"
    assert cfg.users["alice"].state == "active"
    assert cfg.groups["developers"].users == ["alice"]
    assert any(item.status == "adapted" and item.feature == "password" for item in result.diagnostics)

    report = build_compat_report(tf)
    assert report["config_summary"]["users"] == 1
    supported_features = {item["feature"] for item in report["supported"]}
    adapted_features = {item["feature"] for item in report["adapted"]}
    assert "user" in supported_features
    assert "user:alice" in supported_features
    assert "password" in adapted_features


def test_config_from_tofu_show_json_imports_loggers_and_diagnostics() -> None:
    tf = _tf_json(
        [
            {
                "address": "azurerm_api_management_logger.appinsights",
                "type": "azurerm_api_management_logger",
                "name": "appinsights",
                "values": {
                    "name": "appinsights",
                    "resource_id": "/subscriptions/test/resourceGroups/rg/providers/Microsoft.Insights/components/demo",
                    "description": "Primary telemetry sink",
                    "buffered": True,
                    "application_insights": [
                        {
                            "instrumentation_key": "ikey-secret",
                            "connection_string": "InstrumentationKey=ikey-secret;IngestionEndpoint=https://example.test/",
                        }
                    ],
                },
            },
            {
                "address": "azurerm_api_management_diagnostic.appinsights",
                "type": "azurerm_api_management_diagnostic",
                "name": "appinsights",
                "values": {
                    "identifier": "applicationinsights",
                    "api_management_logger_id": "/subscriptions/test/resourceGroups/rg/providers/Microsoft.ApiManagement/service/demo/loggers/appinsights",
                    "sampling_percentage": 5.0,
                    "always_log_errors": True,
                    "log_client_ip": True,
                    "verbosity": "verbose",
                    "http_correlation_protocol": "W3C",
                    "frontend_request": [
                        {
                            "body_bytes": 32,
                            "headers_to_log": ["content-type", "accept"],
                            "data_masking": [
                                {
                                    "headers": [{"mode": "Mask", "value": "authorization"}],
                                    "query_params": [{"mode": "Hide", "value": "sig"}],
                                }
                            ],
                        }
                    ],
                },
            },
        ]
    )

    result = import_from_tofu_show_json(tf)
    cfg = result.config

    assert cfg.loggers["appinsights"].logger_type == "application_insights"
    assert cfg.loggers["appinsights"].application_insights is not None
    assert cfg.loggers["appinsights"].application_insights.instrumentation_key == "ikey-secret"
    assert cfg.diagnostics["applicationinsights"].logger_id == "appinsights"
    assert cfg.diagnostics["applicationinsights"].sampling_percentage == 5.0
    assert cfg.diagnostics["applicationinsights"].frontend_request is not None
    assert cfg.diagnostics["applicationinsights"].frontend_request.headers_to_log == ["content-type", "accept"]
    assert cfg.diagnostics["applicationinsights"].frontend_request.data_masking is not None
    assert cfg.diagnostics["applicationinsights"].frontend_request.data_masking.headers[0].value == "authorization"
    assert cfg.diagnostics["applicationinsights"].frontend_request.data_masking.query_params[0].mode == "Hide"

    report = build_compat_report(tf)
    assert report["config_summary"]["loggers"] == 1
    assert report["config_summary"]["diagnostics"] == 1
    supported_features = {item["feature"] for item in report["supported"]}
    adapted_features = {item["feature"] for item in report["adapted"]}
    assert "logger" in supported_features
    assert "diagnostic" in supported_features
    assert "application_insights" in adapted_features
    assert "runtime_settings" in adapted_features


@pytest.mark.contract("TF-COMPAT-REPORT")
def test_compat_report_is_green_for_supported_fixture() -> None:
    fixture = Path(__file__).parent / "fixtures" / "tofu_show" / "sample.json"
    payload = json.loads(fixture.read_text(encoding="utf-8"))

    report = build_compat_report(payload)

    assert report["unsupported"] == []
    assert report["supported"]
    assert report["adapted"]


def test_compat_report_detects_azapi_service_and_child_resources() -> None:
    tf = _tf_json(
        [
            {
                "address": "azapi_resource.service",
                "type": "azapi_resource",
                "name": "service",
                "values": {
                    "name": "demo-apim",
                    "type": "Microsoft.ApiManagement/service@2025-03-01-preview",
                    "body": {
                        "properties": {
                            "publicNetworkAccess": "Disabled",
                            "virtualNetworkType": "Internal",
                            "enableClientCertificate": True,
                            "hostnameConfigurations": [
                                {
                                    "type": "Proxy",
                                    "hostName": "api.example.test",
                                    "defaultSslBinding": True,
                                    "negotiateClientCertificate": True,
                                }
                            ],
                            "customProperties": {
                                "Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2": "true"
                            },
                        },
                        "sku": {"name": "Developer", "capacity": 1},
                    },
                },
            },
            {
                "address": "azapi_resource.api",
                "type": "azapi_resource",
                "name": "weather",
                "values": {
                    "name": "weather",
                    "type": "Microsoft.ApiManagement/service/apis@2025-03-01-preview",
                    "body": {"properties": {"path": "weather"}},
                },
            },
            {
                "address": "azapi_resource.api_policy",
                "type": "azapi_resource",
                "name": "policy",
                "values": {
                    "name": "policy",
                    "parent_id": "/subscriptions/test/resourceGroups/rg/providers/Microsoft.ApiManagement/service/demo-apim/apis/weather",
                    "type": "Microsoft.ApiManagement/service/apis/policies@2025-03-01-preview",
                    "body": {
                        "properties": {
                            "format": "xml",
                            "value": '<policies><inbound><set-header name="x-demo" exists-action="override"><value>ok</value></set-header></inbound><backend /><outbound /><on-error /></policies>',
                        }
                    },
                },
            },
        ]
    )

    report = build_compat_report(tf)
    adapted_features = {item["feature"] for item in report["adapted"]}
    unsupported_features = {item["feature"] for item in report["unsupported"]}
    supported_features = {item["feature"] for item in report["supported"]}

    assert {
        "properties.publicNetworkAccess",
        "properties.virtualNetworkType",
        "properties.enableClientCertificate",
        "properties.hostnameConfigurations",
    }.issubset(adapted_features)
    assert {"properties.customProperties", "sku", "azapi_import"}.issubset(unsupported_features)
    assert "set-header" in supported_features
    assert "value" in supported_features


def test_imported_subscription_key_parameter_names_are_honored_by_gateway() -> None:
    fixture = Path(__file__).parent / "fixtures" / "tofu_show" / "sample.json"
    payload = json.loads(fixture.read_text(encoding="utf-8"))
    cfg = config_from_tofu_show_json(payload)
    cfg.apis["sample-api"].policies_xml = None
    cfg.apis["sample-api"].operations["health"].policies_xml = None
    cfg.routes = cfg.materialize_routes()

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.url == httpx.URL("https://backend.example.test/api/health")
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=cfg, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))

    with TestClient(app) as client:
        resp = client.get("/sample/health", headers={"X-Sample-Key": "sample-primary", "x-api-version": "v1"})

    assert resp.status_code == 200


def test_management_import_keeps_imported_service_metadata() -> None:
    tf = _tf_json(
        [
            {
                "address": "azapi_resource.service",
                "type": "azapi_resource",
                "name": "service",
                "values": {
                    "name": "demo-apim",
                    "type": "Microsoft.ApiManagement/service@2025-03-01-preview",
                    "body": {
                        "properties": {
                            "publicNetworkAccess": "Disabled",
                            "virtualNetworkType": "Internal",
                            "hostnameConfigurations": [{"type": "Proxy", "hostName": "api.example.test"}],
                        }
                    },
                },
            }
        ]
    )

    app = create_app(
        config=GatewayConfig(
            service={"name": "current-sim", "display_name": "Current Simulator"},
            allow_anonymous=True,
            tenant_access=TenantAccessConfig(enabled=True, primary_key="t1"),
            routes=[RouteConfig(name="bootstrap", path_prefix="/", upstream_base_url=http_url("bootstrap"))],
        )
    )

    with TestClient(app) as client:
        imported = client.post(
            "/apim/management/import/tofu-show",
            headers={"X-Apim-Tenant-Key": "t1"},
            json=tf,
        )
        assert imported.status_code == 200

        service = client.get("/apim/management/service", headers={"X-Apim-Tenant-Key": "t1"})

    assert service.status_code == 200
    assert service.json()["name"] == "demo-apim"
    assert service.json()["display_name"] == "demo-apim"
    assert service.json()["public_network_access_enabled"] is False
    assert service.json()["virtual_network_type"] == "Internal"
    assert service.json()["hostname_configurations"] == [
        {
            "type": "Proxy",
            "host_name": "api.example.test",
            "negotiate_client_certificate": False,
            "default_ssl_binding": False,
        }
    ]


def test_compat_report_classifies_policy_parity_v2_cache_modes() -> None:
    tf = _tf_json(
        [
            {
                "address": "azurerm_api_management_api_policy.cachey",
                "type": "azurerm_api_management_api_policy",
                "name": "cachey",
                "values": {
                    "api_name": "sample",
                    "xml_content": """\
<policies>
  <inbound>
    <cache-lookup vary-by-developer="false" vary-by-developer-groups="false" caching-type="prefer-external">
      <vary-by-query-parameter>version</vary-by-query-parameter>
    </cache-lookup>
    <cache-lookup-value key="demo" variable-name="value" caching-type="external" />
    <rate-limit-by-key calls="10" renewal-period="60" counter-key="demo" />
    <quota-by-key calls="100" bandwidth="4000" renewal-period="300" counter-key="demo" />
  </inbound>
  <backend />
  <outbound>
    <cache-store duration="60" />
    <cache-store-value key="demo" value="x" duration="60" />
  </outbound>
  <on-error>
    <cache-remove-value key="demo" />
  </on-error>
</policies>
""",
                },
            }
        ]
    )

    report = build_compat_report(tf)
    adapted_features = {item["feature"] for item in report["adapted"]}
    unsupported_features = {item["feature"] for item in report["unsupported"]}
    supported_features = {item["feature"] for item in report["supported"]}

    assert "cache-lookup.caching-type" in adapted_features
    assert "cache-lookup-value.caching-type" in unsupported_features
    assert "quota-by-key.bandwidth" in unsupported_features
    assert {"rate-limit-by-key", "cache-store", "cache-store-value", "cache-remove-value"}.issubset(supported_features)
