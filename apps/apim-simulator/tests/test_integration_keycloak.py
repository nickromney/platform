from __future__ import annotations

import os

import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import GatewayConfig, OIDCConfig, RouteConfig, Subscription, SubscriptionConfig, SubscriptionKeyPair
from app.main import create_app
from app.urls import http_url


@pytest.mark.integration
def test_keycloak_password_grant_token_validates_via_jwks_uri() -> None:
    if os.getenv("RUN_INTEGRATION") != "1":
        pytest.skip("Set RUN_INTEGRATION=1 to run Keycloak integration tests")

    base_url = os.getenv("APIM_SIM_KEYCLOAK_BASE_URL", http_url("localhost:8180"))
    realm = os.getenv("APIM_SIM_KEYCLOAK_REALM", "subnet-calculator")
    client_id = os.getenv("APIM_SIM_KEYCLOAK_CLIENT_ID", "frontend-app")
    audience = os.getenv("APIM_SIM_KEYCLOAK_AUDIENCE", "api-app")
    client_secret = os.getenv("APIM_SIM_KEYCLOAK_CLIENT_SECRET")
    username = os.getenv("APIM_SIM_KEYCLOAK_USERNAME", "demo@dev.test")
    password = os.getenv("APIM_SIM_KEYCLOAK_PASSWORD", "demo-password")

    issuer = f"{base_url}/realms/{realm}"
    jwks_uri = f"{issuer}/protocol/openid-connect/certs"
    token_url = f"{issuer}/protocol/openid-connect/token"

    try:
        with httpx.Client(timeout=5.0) as client:
            form = {
                "grant_type": "password",
                "client_id": client_id,
                "username": username,
                "password": password,
            }
            if client_secret:
                form["client_secret"] = client_secret
            resp = client.post(token_url, data=form)
    except httpx.HTTPError as exc:
        pytest.skip(f"Keycloak not reachable: {exc}")

    if resp.status_code != 200:
        pytest.skip(f"Keycloak token endpoint not usable (status {resp.status_code}): {resp.text}")

    access_token = resp.json().get("access_token")
    if not access_token:
        pytest.skip("No access_token returned from Keycloak")

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks_uri=jwks_uri),
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                )
            },
        ),
        routes=[
            RouteConfig(
                name="r1", path_prefix="/api", upstream_base_url=http_url("upstream"), upstream_path_prefix="/api"
            )
        ],
    )

    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        res = client.get(
            "/api/health",
            headers={
                "Authorization": f"Bearer {access_token}",
                "Ocp-Apim-Subscription-Key": "good",
            },
        )
        assert res.status_code == 200
