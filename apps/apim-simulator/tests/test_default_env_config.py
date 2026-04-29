import asyncio

import httpx
from fastapi.testclient import TestClient

from app.config import _default_config_from_env
from app.main import create_app


def test_default_env_config_is_provider_neutral_without_oidc_env(monkeypatch):
    monkeypatch.delenv("OIDC_ISSUER", raising=False)
    monkeypatch.delenv("OIDC_AUDIENCE", raising=False)
    monkeypatch.delenv("OIDC_JWKS_URI", raising=False)

    config = _default_config_from_env()

    assert config.allow_anonymous is True
    assert config.oidc is None


def test_default_env_config_requires_complete_oidc_when_auth_is_enabled(monkeypatch):
    monkeypatch.setenv("ALLOW_ANONYMOUS", "false")
    monkeypatch.setenv("OIDC_ISSUER", "https://issuer.example.test")
    monkeypatch.setenv("OIDC_AUDIENCE", "api")
    monkeypatch.delenv("OIDC_JWKS_URI", raising=False)

    try:
        _default_config_from_env()
    except ValueError as exc:
        assert "OIDC_JWKS_URI" in str(exc)
    else:
        raise AssertionError("expected incomplete OIDC configuration to fail")


def test_default_env_config_requires_oidc_when_anonymous_access_is_disabled(monkeypatch):
    monkeypatch.setenv("ALLOW_ANONYMOUS", "false")
    monkeypatch.delenv("OIDC_ISSUER", raising=False)
    monkeypatch.delenv("OIDC_AUDIENCE", raising=False)
    monkeypatch.delenv("OIDC_JWKS_URI", raising=False)

    try:
        _default_config_from_env()
    except ValueError as exc:
        assert "required when ALLOW_ANONYMOUS=false" in str(exc)
    else:
        raise AssertionError("expected disabled anonymous access without OIDC to fail")


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
