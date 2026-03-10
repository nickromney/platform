from __future__ import annotations

import json

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from jwt.algorithms import RSAAlgorithm

from app.config import (
    ApiConfig,
    GatewayConfig,
    OIDCConfig,
    OperationConfig,
    ProductConfig,
    RouteAuthzConfig,
    Subscription,
    SubscriptionConfig,
    SubscriptionKeyPair,
)
from app.main import create_app


def _make_rsa_jwks() -> tuple[dict, rsa.RSAPrivateKey]:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public_jwk = json.loads(RSAAlgorithm.to_jwk(private_key.public_key()))
    public_jwk["kid"] = "test-kid"
    public_jwk["use"] = "sig"
    return {"keys": [public_jwk]}, private_key


def _make_token(*, private_key: rsa.RSAPrivateKey, issuer: str, audience: str, scope: str = "") -> str:
    claims = {
        "sub": "user-123",
        "preferred_username": "demo",
        "iss": issuer,
        "aud": audience,
    }
    if scope:
        claims["scope"] = scope
    return jwt.encode(claims, private_key, algorithm="RS256", headers={"kid": "test-kid"})


def test_scenario_multi_app_products_and_scopes() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience, scope="read")

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        products={
            "app-a": ProductConfig(name="app-a", require_subscription=True),
            "app-b": ProductConfig(name="app-b", require_subscription=True),
        },
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "sub": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["app-a"],
                )
            },
        ),
        apis={
            "a": ApiConfig(
                name="a",
                path="app-a",
                upstream_base_url="http://upstream-a",
                products=["app-a"],
                operations={
                    "health": OperationConfig(
                        name="health",
                        method="GET",
                        url_template="/health",
                        authz=RouteAuthzConfig(required_scopes=["read"]),
                    )
                },
            ),
            "b": ApiConfig(
                name="b",
                path="app-b",
                upstream_base_url="http://upstream-b",
                products=["app-b"],
                operations={"health": OperationConfig(name="health", method="GET", url_template="/health")},
            ),
        },
    )

    def handler(req: httpx.Request) -> httpx.Response:
        if req.url.host == "upstream-a":
            return httpx.Response(200, json={"app": "a"})
        if req.url.host == "upstream-b":
            return httpx.Response(200, json={"app": "b"})
        raise AssertionError("Unexpected upstream")

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        ok = client.get(
            "/app-a/health",
            headers={"Authorization": f"Bearer {token}", "Ocp-Apim-Subscription-Key": "good"},
        )
        assert ok.status_code == 200
        assert ok.json() == {"app": "a"}

        denied = client.get(
            "/app-b/health",
            headers={"Authorization": f"Bearer {token}", "Ocp-Apim-Subscription-Key": "good"},
        )
        assert denied.status_code == 403
        assert denied.json()["detail"] == "Subscription not authorized for product"
