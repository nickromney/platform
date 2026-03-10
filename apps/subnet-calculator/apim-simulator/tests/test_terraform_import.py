from __future__ import annotations

import httpx
from fastapi.testclient import TestClient

from app.config import GatewayConfig, RouteConfig, TenantAccessConfig
from app.main import create_app
from app.terraform_import import config_from_tofu_show_json


def _tf_json(resources: list[dict]) -> dict:
    return {"values": {"root_module": {"resources": resources}}}


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
                "values": {"name": "api", "path": "app-a", "service_url": "http://upstream"},
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
    assert cfg.apis["api"].upstream_base_url == "http://upstream"
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
                "values": {"name": "api", "path": "app-a", "service_url": "http://upstream"},
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
        assert req.url == httpx.URL("http://upstream/health/")
        return httpx.Response(200, json={"ok": True})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            tenant_access=TenantAccessConfig(enabled=True, primary_key="t1"),
            routes=[RouteConfig(name="bootstrap", path_prefix="/", upstream_base_url="http://bootstrap")],
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
