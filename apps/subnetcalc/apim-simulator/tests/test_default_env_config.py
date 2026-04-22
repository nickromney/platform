import asyncio

import httpx
from fastapi.testclient import TestClient

from app.config import _default_config_from_env
from app.main import create_app


def test_default_env_subscription_key_binds_default_product(monkeypatch):
    monkeypatch.setenv("APIM_SUBSCRIPTION_KEY", "dev-subscription-key")

    config = _default_config_from_env()

    subscription = config.subscription.lookup_subscription_by_key("dev-subscription-key")

    assert subscription is not None
    assert subscription.products == ["default"]


def test_default_env_gateway_allows_default_product_subscription(monkeypatch):
    monkeypatch.setenv("APIM_SUBSCRIPTION_KEY", "dev-subscription-key")

    def upstream_handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"status": "healthy"})

    http_client = httpx.AsyncClient(transport=httpx.MockTransport(upstream_handler))
    app = create_app(config=_default_config_from_env(), http_client=http_client)

    with TestClient(app) as client:
        response = client.get(
            "/api/v1/health",
            headers={"Ocp-Apim-Subscription-Key": "dev-subscription-key"},
        )

    asyncio.run(http_client.aclose())

    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}
