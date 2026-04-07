from __future__ import annotations

import base64
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from jwt.algorithms import RSAAlgorithm

from app.config import (
    ApiConfig,
    ApiReleaseConfig,
    ApiRevisionConfig,
    ApiSchemaConfig,
    ApiVersioningScheme,
    ApiVersionSetConfig,
    BackendConfig,
    ClientCertificateConfig,
    ClientCertificateMode,
    DiagnosticConfig,
    DiagnosticDataMaskingConfig,
    DiagnosticHttpMessageConfig,
    DiagnosticMaskingRuleConfig,
    GatewayConfig,
    GroupConfig,
    LoggerApplicationInsightsConfig,
    LoggerConfig,
    NamedValueConfig,
    OIDCConfig,
    OperationConfig,
    OperationParameterConfig,
    OperationRepresentationConfig,
    OperationRequestMetadataConfig,
    OperationResponseMetadataConfig,
    ProductConfig,
    RouteAuthzConfig,
    RouteConfig,
    Subscription,
    SubscriptionConfig,
    SubscriptionKeyPair,
    SubscriptionState,
    TagConfig,
    TenantAccessConfig,
    TrustedClientCertificateConfig,
    UserConfig,
)
from app.main import create_app


def _make_rsa_jwks() -> tuple[dict, rsa.RSAPrivateKey]:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public_jwk = json.loads(RSAAlgorithm.to_jwk(private_key.public_key()))
    public_jwk["kid"] = "test-kid"
    public_jwk["use"] = "sig"
    return {"keys": [public_jwk]}, private_key


def _make_token(
    *, private_key: rsa.RSAPrivateKey, issuer: str, audience: str, extra_claims: dict[str, Any] | None = None
) -> str:
    claims = {
        "sub": "user-123",
        "email": "demo@dev.test",
        "name": "Demo User",
        "preferred_username": "demo@dev.test",
        "iss": issuer,
        "aud": audience,
    }
    if extra_claims:
        claims.update(extra_claims)
    return jwt.encode(claims, private_key, algorithm="RS256", headers={"kid": "test-kid"})


def test_health() -> None:
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            routes=[
                RouteConfig(
                    name="r1", path_prefix="/api", upstream_base_url="http://upstream", upstream_path_prefix="/api"
                )
            ],
        )
    )
    with TestClient(app) as client:
        resp = client.get("/apim/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "healthy"}


def test_root_hint_lists_builtin_entrypoints() -> None:
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            tenant_access=TenantAccessConfig(enabled=True, primary_key="local-dev-tenant-key"),
            routes=[
                RouteConfig(
                    name="r1", path_prefix="/api", upstream_base_url="http://upstream", upstream_path_prefix="/api"
                )
            ],
        )
    )

    with TestClient(app) as client:
        resp = client.get("/")

    assert resp.status_code == 200
    assert resp.json() == {
        "service": "Local APIM Simulator",
        "message": "This is an API gateway. Try /apim/health, /apim/startup, or one of the configured route prefixes.",
        "gateway_endpoints": ["/apim/health", "/apim/startup"],
        "route_prefixes": ["/api"],
        "management": {
            "enabled": True,
            "status_path": "/apim/management/status",
            "required_header": "X-Apim-Tenant-Key",
        },
        "operator_console": {
            "url": "http://localhost:3007",
            "note": "Run make up-ui to start the operator console.",
        },
    }


def test_route_host_match_selects_expected_upstream() -> None:
    seen_urls: list[str] = []

    def handler(req: httpx.Request) -> httpx.Response:
        seen_urls.append(str(req.url))
        return httpx.Response(200, json={"ok": True})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            routes=[
                RouteConfig(
                    name="dev",
                    path_prefix="/api",
                    host_match=["subnetcalc.dev.127.0.0.1.sslip.io"],
                    upstream_base_url="http://upstream-dev",
                    upstream_path_prefix="/api",
                ),
                RouteConfig(
                    name="uat",
                    path_prefix="/api",
                    host_match=["subnetcalc.uat.127.0.0.1.sslip.io"],
                    upstream_base_url="http://upstream-uat",
                    upstream_path_prefix="/api",
                ),
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        resp = client.get("/api/v1/health", headers={"Host": "subnetcalc.uat.127.0.0.1.sslip.io:443"})

    assert resp.status_code == 200
    assert seen_urls == ["http://upstream-uat/api/v1/health"]


def test_route_host_match_prefers_x_forwarded_host() -> None:
    seen_urls: list[str] = []

    def handler(req: httpx.Request) -> httpx.Response:
        seen_urls.append(str(req.url))
        return httpx.Response(200, json={"ok": True})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            routes=[
                RouteConfig(
                    name="dev",
                    path_prefix="/api",
                    host_match=["subnetcalc.dev.127.0.0.1.sslip.io"],
                    upstream_base_url="http://upstream-dev",
                    upstream_path_prefix="/api",
                ),
                RouteConfig(
                    name="uat",
                    path_prefix="/api",
                    host_match=["subnetcalc.uat.127.0.0.1.sslip.io"],
                    upstream_base_url="http://upstream-uat",
                    upstream_path_prefix="/api",
                ),
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Host": "subnetcalc.dev.127.0.0.1.sslip.io",
                "X-Forwarded-Host": "subnetcalc.uat.127.0.0.1.sslip.io",
            },
        )

    assert resp.status_code == 200
    assert seen_urls == ["http://upstream-uat/api/v1/health"]


def test_trace_headers_and_trace_lookup_work() -> None:
    config = GatewayConfig(
        allow_anonymous=True,
        trace_enabled=True,
        proxy_streaming=False,
        routes=[
            RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", upstream_path_prefix="/api")
        ],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get("/api/health", headers={"x-apim-trace": "true"})
        trace_id = resp.headers.get("x-apim-trace-id")
        corr_id = resp.headers.get("x-correlation-id")
        assert trace_id
        assert corr_id

        trace = client.get(f"/apim/trace/{trace_id}")

    assert resp.status_code == 200
    assert trace.status_code == 200
    payload = trace.json()
    assert payload["route"] == "r1"
    assert payload["correlation_id"] == corr_id


def test_missing_subscription_key_returns_401() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1", name="demo", keys=SubscriptionKeyPair(primary="good", secondary="good2")
                )
            },
        ),
        routes=[
            RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", upstream_path_prefix="/api")
        ],
    )
    app = create_app(
        config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200)))
    )

    with TestClient(app) as client:
        resp = client.get("/api/v1/health", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401
    assert resp.json()["detail"] == "Missing subscription key"


def test_bearer_only_mode_works_when_subscriptions_are_disabled() -> None:
    issuer = "http://issuer.example"
    audience = "frontend-app"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=False,
            oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
            subscription=SubscriptionConfig(required=False),
            routes=[
                RouteConfig(
                    name="r1",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                    upstream_path_prefix="/api",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json={"ok": True}))),
    )

    with TestClient(app) as client:
        resp = client.get("/api/v1/health", headers={"Authorization": f"Bearer {token}"})

    assert resp.status_code == 200


def test_anonymous_mode_can_still_require_subscription_key_for_product() -> None:
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            products={"p1": ProductConfig(name="p1", require_subscription=True)},
            subscription=SubscriptionConfig(
                required=True,
                subscriptions={
                    "demo": Subscription(
                        id="sub1",
                        name="demo",
                        keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                        products=["p1"],
                    )
                },
            ),
            routes=[
                RouteConfig(
                    name="r1",
                    path_prefix="/mcp",
                    upstream_base_url="http://upstream",
                    upstream_path_prefix="/mcp",
                    product="p1",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json={"ok": True}))),
    )

    with TestClient(app) as client:
        missing = client.post("/mcp")
        allowed = client.post("/mcp", headers={"Ocp-Apim-Subscription-Key": "good"})

    assert missing.status_code == 401
    assert missing.json()["detail"] == "Missing subscription key"
    assert allowed.status_code == 200


def test_multi_oidc_provider_selection_by_issuer() -> None:
    issuer1 = "http://issuer1.example"
    audience1 = "api1"
    issuer2 = "http://issuer2.example"
    audience2 = "api2"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer2, audience=audience2)

    config = GatewayConfig(
        allow_anonymous=False,
        oidc_providers={
            "p1": OIDCConfig(issuer=issuer1, audience=audience1, jwks=jwks),
            "p2": OIDCConfig(issuer=issuer2, audience=audience2, jwks=jwks),
        },
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
            RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", upstream_path_prefix="/api")
        ],
    )

    app = create_app(
        config=config,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "good",
            },
        )
    assert resp.status_code == 200


def test_subscription_bypass_allows_missing_key() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    config = GatewayConfig.model_validate(
        {
            "allow_anonymous": False,
            "allowed_origins": ["*"],
            "products": {"p1": {"name": "p1", "require_subscription": True}},
            "oidc": {"issuer": issuer, "audience": audience, "jwks": jwks},
            "subscription": {
                "required": True,
                "subscriptions": {
                    "demo": {
                        "id": "sub1",
                        "name": "demo",
                        "keys": {"primary": "good", "secondary": "good2"},
                        "products": ["p1"],
                    }
                },
                "bypass": [{"header": "X-Forwarded-For", "starts_with": "10.100.0"}],
            },
            "routes": [
                {
                    "name": "r1",
                    "path_prefix": "/api",
                    "upstream_base_url": "http://upstream",
                    "upstream_path_prefix": "/api",
                    "product": "p1",
                }
            ],
        }
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.url == httpx.URL("http://upstream/api/v1/health")
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={"Authorization": f"Bearer {token}", "X-Forwarded-For": "10.100.0.9"},
        )
    assert resp.status_code == 200


def test_subscription_key_query_param_works() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"ok": True})

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
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
            RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", upstream_path_prefix="/api")
        ],
    )

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health?subscription-key=good",
            headers={"Authorization": f"Bearer {token}"},
        )
    assert resp.status_code == 200


def test_suspended_subscription_returns_403() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    state=SubscriptionState.Suspended,
                )
            },
        ),
        routes=[
            RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", upstream_path_prefix="/api")
        ],
    )
    app = create_app(config=config)
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "good",
            },
        )
    assert resp.status_code == 403
    assert resp.json()["detail"] == "Subscription is not active"


def test_backend_basic_auth_is_applied_and_url_is_used() -> None:
    encoded = base64.b64encode(b"u:p").decode("utf-8")

    config = GatewayConfig(
        allow_anonymous=True,
        backends={
            "b1": BackendConfig(
                url="http://upstream",
                auth_type="basic",
                basic_username="u",
                basic_password="p",
            )
        },
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://ignored",
                upstream_path_prefix="/api",
                backend="b1",
            )
        ],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.url == httpx.URL("http://upstream/api/health")
        assert req.headers.get("authorization") == f"Basic {encoded}"
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get("/api/health")
    assert resp.status_code == 200


def test_rate_limit_policy_returns_429_on_second_call() -> None:
    policy = """\
<policies>
  <inbound>
    <rate-limit calls="1" renewal-period="999999" scope="subscription" />
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    config = GatewayConfig(
        allow_anonymous=True,
        subscription=SubscriptionConfig(
            required=False,
            subscriptions={
                "s1": Subscription(id="sub1", name="sub1", keys=SubscriptionKeyPair(primary="k", secondary="k2"))
            },
        ),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                policies_xml=policy,
            )
        ],
    )

    calls = 0

    def handler(req: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        r1 = client.get("/api/health", headers={"Ocp-Apim-Subscription-Key": "k"})
        r2 = client.get("/api/health", headers={"Ocp-Apim-Subscription-Key": "k"})

    assert r1.status_code == 200
    assert r2.status_code == 429
    assert calls == 1


def test_proxy_injects_identity_headers_and_filters_hop_by_hop() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        products={"p1": ProductConfig(name="p1")},
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["p1"],
                )
            },
        ),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                product="p1",
            )
        ],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.headers.get("x-apim-user-email") == "demo@dev.test"
        assert req.headers.get("x-apim-user-object-id") == "user-123"
        assert req.headers.get("x-ms-client-principal")
        assert req.headers.get("x-user-id") == "sub1"
        assert req.headers.get("x-user-name") == "demo"
        assert req.headers.get("x-apim-products") == "p1"
        return httpx.Response(
            200,
            json={"ok": True},
            headers={
                "connection": "keep-alive",
                "x-upstream": "1",
            },
        )

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))

    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "good",
            },
        )
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}
    assert resp.headers.get("x-apim-simulator") == "apim-simulator"
    assert "connection" not in {k.lower() for k in resp.headers.keys()}


def test_api_version_set_header_routes_to_correct_version() -> None:
    config = GatewayConfig(
        allow_anonymous=True,
        api_version_sets={
            "vset": ApiVersionSetConfig(
                display_name="Subnet Calc",
                versioning_scheme=ApiVersioningScheme.Header,
                version_header_name="X-Api-Version",
            )
        },
        routes=[
            RouteConfig(
                name="api-v1",
                path_prefix="/api",
                upstream_base_url="http://upstream-v1",
                upstream_path_prefix="/api",
                api_version_set="vset",
                api_version="v1",
            ),
            RouteConfig(
                name="api-v2",
                path_prefix="/api",
                upstream_base_url="http://upstream-v2",
                upstream_path_prefix="/api",
                api_version_set="vset",
                api_version="v2",
            ),
        ],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.url == httpx.URL("http://upstream-v2/api/health")
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get("/api/health", headers={"X-Api-Version": "v2"})
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}


def test_api_version_set_query_routes_to_correct_version() -> None:
    config = GatewayConfig(
        allow_anonymous=True,
        api_version_sets={
            "vset": ApiVersionSetConfig(
                display_name="Subnet Calc",
                versioning_scheme=ApiVersioningScheme.Query,
                version_query_name="api-version",
            )
        },
        routes=[
            RouteConfig(
                name="api-v1",
                path_prefix="/api",
                upstream_base_url="http://upstream-v1",
                upstream_path_prefix="/api",
                api_version_set="vset",
                api_version="v1",
            ),
            RouteConfig(
                name="api-v2",
                path_prefix="/api",
                upstream_base_url="http://upstream-v2",
                upstream_path_prefix="/api",
                api_version_set="vset",
                api_version="v2",
            ),
        ],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.url == httpx.URL("http://upstream-v1/api/health?api-version=v1")
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get("/api/health?api-version=v1")
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}


def test_api_version_set_segment_routes_and_strips_version_segment_for_upstream() -> None:
    config = GatewayConfig(
        allow_anonymous=True,
        api_version_sets={
            "vset": ApiVersionSetConfig(
                display_name="Subnet Calc",
                versioning_scheme=ApiVersioningScheme.Segment,
            )
        },
        routes=[
            RouteConfig(
                name="api-v1",
                path_prefix="/api",
                upstream_base_url="http://upstream-v1",
                upstream_path_prefix="/api",
                api_version_set="vset",
                api_version="v1",
            ),
            RouteConfig(
                name="api-v2",
                path_prefix="/api",
                upstream_base_url="http://upstream-v2",
                upstream_path_prefix="/api",
                api_version_set="vset",
                api_version="v2",
            ),
        ],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        # External path includes version segment; simulator strips it for upstream stability.
        assert req.url == httpx.URL("http://upstream-v2/api/health")
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get("/api/v2/health")
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}


def test_policy_inbound_set_header_modifies_upstream_request() -> None:
    policy_xml = """\
<policies>
  <inbound>
    <set-header name="x-test" exists-action="override">
      <value>1</value>
    </set-header>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    config = GatewayConfig(
        allow_anonymous=True,
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                policies_xml=policy_xml,
            )
        ],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.headers.get("x-test") == "1"
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get("/api/health")
    assert resp.status_code == 200


def test_policy_inbound_rewrite_uri_modifies_upstream_path() -> None:
    policy_xml = """\
<policies>
  <inbound>
    <rewrite-uri template="/api/v1/other" />
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    config = GatewayConfig(
        allow_anonymous=True,
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                policies_xml=policy_xml,
            )
        ],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.url == httpx.URL("http://upstream/api/v1/other")
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get("/api/health")
    assert resp.status_code == 200


def test_policy_choose_when_selects_branch() -> None:
    policy_xml = """\
<policies>
  <inbound>
    <choose>
      <when condition="header('X-Debug') == '1'">
        <set-header name="x-mode" exists-action="override"><value>debug</value></set-header>
      </when>
      <otherwise>
        <set-header name="x-mode" exists-action="override"><value>normal</value></set-header>
      </otherwise>
    </choose>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    config = GatewayConfig(
        allow_anonymous=True,
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                policies_xml=policy_xml,
            )
        ],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.headers.get("x-mode") == "debug"
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get("/api/health", headers={"X-Debug": "1"})
    assert resp.status_code == 200


def test_policy_return_response_short_circuits_upstream() -> None:
    policy_xml = """\
<policies>
  <inbound>
    <return-response>
      <set-status code="418" reason="teapot" />
      <set-header name="content-type" exists-action="override"><value>text/plain</value></set-header>
      <body>nope</body>
    </return-response>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    config = GatewayConfig(
        allow_anonymous=True,
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                policies_xml=policy_xml,
            )
        ],
    )

    def handler(_: httpx.Request) -> httpx.Response:
        raise AssertionError("Upstream should not be called when return-response triggers")

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get("/api/health")
    assert resp.status_code == 418
    assert resp.text == "nope"


def test_full_model_operation_method_routing() -> None:
    config = GatewayConfig(
        allow_anonymous=True,
        apis={
            "api": ApiConfig(
                name="api",
                path="api",
                upstream_base_url="http://unused",
                operations={
                    "get": OperationConfig(
                        name="get-health",
                        method="GET",
                        url_template="/health",
                        upstream_base_url="http://upstream-get",
                    ),
                    "post": OperationConfig(
                        name="post-health",
                        method="POST",
                        url_template="/health",
                        upstream_base_url="http://upstream-post",
                    ),
                },
            )
        },
    )

    def handler(req: httpx.Request) -> httpx.Response:
        if req.method == "GET":
            assert req.url.host == "upstream-get"
            assert req.url.path == "/health"
        elif req.method == "POST":
            assert req.url.host == "upstream-post"
            assert req.url.path == "/health"
        else:
            raise AssertionError(f"Unexpected method {req.method}")
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        assert client.get("/api/health").status_code == 200
        assert client.post("/api/health").status_code == 200


def test_full_model_api_and_operation_policies_stack() -> None:
    api_policy = """\
<policies>
  <inbound>
    <set-header name="x-api" exists-action="override"><value>1</value></set-header>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    op_policy = """\
<policies>
  <inbound>
    <set-header name="x-op" exists-action="override"><value>1</value></set-header>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    config = GatewayConfig(
        allow_anonymous=True,
        apis={
            "api": ApiConfig(
                name="api",
                path="api",
                upstream_base_url="http://upstream",
                policies_xml=api_policy,
                operations={
                    "get": OperationConfig(
                        name="health",
                        method="GET",
                        url_template="/health",
                        policies_xml=op_policy,
                    )
                },
            )
        },
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.headers.get("x-api") == "1"
        assert req.headers.get("x-op") == "1"
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get("/api/health")
    assert resp.status_code == 200


def test_route_authz_requires_scope() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience, extra_claims={"scope": "read"})

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        products={"p1": ProductConfig(name="p1")},
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["p1"],
                )
            },
        ),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                product="p1",
                authz=RouteAuthzConfig(required_scopes=["read"]),
            )
        ],
    )

    app = create_app(
        config=config,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "good",
            },
        )
    assert resp.status_code == 200


def test_route_authz_missing_scope_returns_403() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience, extra_claims={"scope": "write"})

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        products={"p1": ProductConfig(name="p1")},
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["p1"],
                )
            },
        ),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                product="p1",
                authz=RouteAuthzConfig(required_scopes=["read"]),
            )
        ],
    )

    def handler(_: httpx.Request) -> httpx.Response:
        raise AssertionError("Upstream should not be called when authz fails")

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "good",
            },
        )
    assert resp.status_code == 403
    assert resp.json()["detail"] == "Missing required scope"


def test_route_authz_requires_claim() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(
        private_key=private_key,
        issuer=issuer,
        audience=audience,
        extra_claims={"tenant": "t1"},
    )

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        products={"p1": ProductConfig(name="p1")},
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["p1"],
                )
            },
        ),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                product="p1",
                authz=RouteAuthzConfig(required_claims={"tenant": "t1"}),
            )
        ],
    )

    app = create_app(
        config=config,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "good",
            },
        )
    assert resp.status_code == 200


def test_route_authz_missing_claim_returns_403() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        products={"p1": ProductConfig(name="p1")},
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["p1"],
                )
            },
        ),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                product="p1",
                authz=RouteAuthzConfig(required_claims={"tenant": "t1"}),
            )
        ],
    )

    def handler(_: httpx.Request) -> httpx.Response:
        raise AssertionError("Upstream should not be called when authz fails")

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "good",
            },
        )
    assert resp.status_code == 403
    assert resp.json()["detail"] == "Missing required claim"


def test_route_authz_requires_role() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(
        private_key=private_key,
        issuer=issuer,
        audience=audience,
        extra_claims={"realm_access": {"roles": ["admin"]}},
    )

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        products={"p1": ProductConfig(name="p1")},
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["p1"],
                )
            },
        ),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                product="p1",
                authz=RouteAuthzConfig(required_roles=["admin"]),
            )
        ],
    )

    app = create_app(
        config=config,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "good",
            },
        )
    assert resp.status_code == 200


def test_route_authz_missing_role_returns_403() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        products={"p1": ProductConfig(name="p1")},
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["p1"],
                )
            },
        ),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                product="p1",
                authz=RouteAuthzConfig(required_roles=["admin"]),
            )
        ],
    )

    def handler(_: httpx.Request) -> httpx.Response:
        raise AssertionError("Upstream should not be called when authz fails")

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "good",
            },
        )
    assert resp.status_code == 403
    assert resp.json()["detail"] == "Missing required role"


def test_secondary_subscription_key_works() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        products={"p1": ProductConfig(name="p1")},
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["p1"],
                )
            },
        ),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                product="p1",
            )
        ],
    )

    app = create_app(
        config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200)))
    )
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "good2",
            },
        )
    assert resp.status_code == 200


def test_product_access_denied_without_product_grant() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        products={"p1": ProductConfig(name="p1")},
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=[],
                )
            },
        ),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                product="p1",
            )
        ],
    )

    app = create_app(
        config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200)))
    )
    with TestClient(app) as client:
        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "good",
            },
        )
    assert resp.status_code == 403
    assert resp.json()["detail"] == "Subscription not authorized for product"


def test_rotate_subscription_key_updates_gateway_lookup() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    def handler(req: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"ok": True})

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        products={"p1": ProductConfig(name="p1")},
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "demo": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["p1"],
                )
            },
        ),
        admin_token="adm",
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                product="p1",
            )
        ],
    )

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        rotated = client.post(
            "/apim/admin/subscriptions/sub1/rotate?key=secondary",
            headers={"X-Apim-Admin-Token": "adm"},
        )
        assert rotated.status_code == 200
        new_key = rotated.json()["new_key"]

        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": new_key,
            },
        )
        assert resp.status_code == 200


def test_management_plane_requires_tenant_key() -> None:
    config = GatewayConfig(
        allow_anonymous=True,
        tenant_access=TenantAccessConfig(enabled=True, primary_key="t1", secondary_key="t2"),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
            )
        ],
    )
    app = create_app(config=config)
    with TestClient(app) as client:
        resp = client.get("/apim/management/status")
        assert resp.status_code == 403

        ok = client.get("/apim/management/status", headers={"X-Apim-Tenant-Key": "t1"})
        assert ok.status_code == 200


def test_shipped_example_configs_enable_management_plane() -> None:
    root = Path(__file__).resolve().parents[1]
    example_paths = [
        root / "examples" / "basic.json",
        root / "examples" / "mcp" / "http.json",
        root / "examples" / "oidc" / "keycloak.json",
    ]

    for path in example_paths:
        cfg = GatewayConfig.model_validate(json.loads(path.read_text(encoding="utf-8")))
        app = create_app(config=cfg)
        with TestClient(app) as client:
            resp = client.get("/apim/management/status", headers={"X-Apim-Tenant-Key": "local-dev-tenant-key"})
        assert resp.status_code == 200, path.name


def test_management_plane_rotate_subscription_key_updates_gateway_lookup() -> None:
    issuer = "http://issuer.example"
    audience = "api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience)

    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"ok": True})

    config = GatewayConfig(
        allow_anonymous=False,
        oidc=OIDCConfig(issuer=issuer, audience=audience, jwks=jwks),
        tenant_access=TenantAccessConfig(enabled=True, primary_key="t1", secondary_key="t2"),
        products={"p1": ProductConfig(name="p1")},
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "sub1": Subscription(
                    id="sub1",
                    name="demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["p1"],
                )
            },
        ),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                product="p1",
            )
        ],
    )

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        rotated = client.post(
            "/apim/management/subscriptions/sub1/rotate?key=secondary",
            headers={"X-Apim-Tenant-Key": "t1"},
        )
        assert rotated.status_code == 200
        new_key = rotated.json()["new_key"]

        resp = client.get(
            "/api/v1/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": new_key,
            },
        )
        assert resp.status_code == 200


def test_trace_payload_captures_forwarded_headers() -> None:
    config = GatewayConfig(
        allow_anonymous=True,
        trace_enabled=True,
        proxy_streaming=False,
        routes=[
            RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", upstream_path_prefix="/api")
        ],
    )

    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get(
            "/api/health",
            headers={
                "Host": "apim.localtest.me:8443",
                "X-Forwarded-Host": "apim.localtest.me",
                "X-Forwarded-Proto": "https",
                "X-Forwarded-For": "203.0.113.10, 10.0.0.5",
                "x-apim-trace": "true",
            },
        )
        trace = client.get(f"/apim/trace/{resp.headers['x-apim-trace-id']}")

    assert resp.status_code == 200
    assert trace.status_code == 200
    payload = trace.json()
    assert payload["incoming_host"] == "apim.localtest.me:8443"
    assert payload["forwarded_host"] == "apim.localtest.me"
    assert payload["forwarded_proto"] == "https"
    assert payload["forwarded_for"] == "203.0.113.10, 10.0.0.5"
    assert payload["client_ip"] == "203.0.113.10"
    assert payload["upstream_url"] == "http://upstream/api/health"


def test_management_summary_lists_routes_and_gateway_scope() -> None:
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            tenant_access=TenantAccessConfig(enabled=True, primary_key="t1"),
            routes=[
                RouteConfig(
                    name="r1",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                    upstream_path_prefix="/api",
                )
            ],
        )
    )

    with TestClient(app) as client:
        resp = client.get("/apim/management/summary", headers={"X-Apim-Tenant-Key": "t1"})

    assert resp.status_code == 200
    payload = resp.json()
    assert payload["gateway_policy_scope"] == {"scope_type": "gateway", "scope_name": "gateway"}
    assert payload["routes"][0]["name"] == "r1"
    assert payload["routes"][0]["policy_scope"] == {"scope_type": "route", "scope_name": "r1"}


def test_management_resource_collections_expose_service_scoped_ids() -> None:
    app = create_app(
        config=GatewayConfig(
            service={"name": "team-sim", "display_name": "Team Simulator"},
            allow_anonymous=True,
            tenant_access=TenantAccessConfig(enabled=True, primary_key="t1"),
            products={
                "starter": ProductConfig(
                    name="Starter", require_subscription=True, groups=["admins"], tags=["featured"]
                )
            },
            subscription=SubscriptionConfig(
                required=True,
                subscriptions={
                    "starter-dev": Subscription(
                        id="sub-starter-dev",
                        name="starter-dev",
                        keys=SubscriptionKeyPair(primary="starter-primary", secondary="starter-secondary"),
                        products=["starter"],
                    )
                },
            ),
            named_values={"backend-secret": NamedValueConfig(value="super-secret-token", secret=True)},
            loggers={
                "appinsights": LoggerConfig(
                    logger_type="application_insights",
                    application_insights=LoggerApplicationInsightsConfig(
                        instrumentation_key="ikey-secret",
                        connection_string="InstrumentationKey=ikey-secret;IngestionEndpoint=https://example.test/",
                    ),
                )
            },
            diagnostics={
                "applicationinsights": DiagnosticConfig(
                    identifier="applicationinsights",
                    logger_id="appinsights",
                    sampling_percentage=5.0,
                    verbosity="verbose",
                    frontend_request=DiagnosticHttpMessageConfig(
                        body_bytes=32,
                        headers_to_log=["content-type"],
                        data_masking=DiagnosticDataMaskingConfig(
                            headers=[DiagnosticMaskingRuleConfig(mode="Mask", value="authorization")]
                        ),
                    ),
                )
            },
            backends={"hello-backend": BackendConfig(url="http://upstream")},
            api_version_sets={
                "public": ApiVersionSetConfig(
                    display_name="Public",
                    versioning_scheme=ApiVersioningScheme.Header,
                    version_header_name="x-api-version",
                )
            },
            policy_fragments={
                "inject-stage": '<set-header name="x-stage" exists-action="override"><value>prod</value></set-header>'
            },
            users={"dev-1": UserConfig(id="dev-1", email="dev@example.com", name="Dev One")},
            groups={"admins": GroupConfig(id="admins", name="Admins", users=["dev-1"])},
            tags={"featured": TagConfig(display_name="Featured")},
            apis={
                "hello": ApiConfig(
                    name="hello",
                    path="hello",
                    upstream_base_url="http://upstream",
                    products=["starter"],
                    api_version_set="public",
                    revision="2",
                    revision_description="Current revision",
                    source_api_id="service/team-sim/apis/hello;rev=1",
                    is_current=True,
                    is_online=True,
                    tags=["featured"],
                    operations={
                        "getHello": OperationConfig(
                            name="getHello",
                            method="GET",
                            url_template="/hello",
                            tags=["featured"],
                        )
                    },
                    revisions={
                        "1": ApiRevisionConfig(
                            revision="1", description="Initial revision", is_current=False, is_online=False
                        ),
                        "2": ApiRevisionConfig(
                            revision="2",
                            description="Current revision",
                            is_current=True,
                            is_online=True,
                            source_api_id="service/team-sim/apis/hello;rev=1",
                        ),
                    },
                    releases={
                        "public": ApiReleaseConfig(
                            name="public",
                            api_id="service/team-sim/apis/hello;rev=2",
                            notes="Shipped publicly",
                            revision="2",
                        )
                    },
                )
            },
        )
    )

    with TestClient(app) as client:
        headers = {"X-Apim-Tenant-Key": "t1"}
        service = client.get("/apim/management/service", headers=headers)
        summary = client.get("/apim/management/summary", headers=headers)
        apis = client.get("/apim/management/apis", headers=headers)
        operations = client.get("/apim/management/operations", headers=headers)
        products = client.get("/apim/management/products", headers=headers)
        subscriptions = client.get("/apim/management/subscriptions", headers=headers)
        backends = client.get("/apim/management/backends", headers=headers)
        named_values = client.get("/apim/management/named-values", headers=headers)
        loggers = client.get("/apim/management/loggers", headers=headers)
        diagnostics = client.get("/apim/management/diagnostics", headers=headers)
        version_sets = client.get("/apim/management/api-version-sets", headers=headers)
        fragments = client.get("/apim/management/policy-fragments", headers=headers)
        users = client.get("/apim/management/users", headers=headers)
        groups = client.get("/apim/management/groups", headers=headers)
        group_users = client.get("/apim/management/groups/admins/users", headers=headers)
        tags = client.get("/apim/management/tags", headers=headers)
        api_tags = client.get("/apim/management/apis/hello/tags", headers=headers)
        api_revisions = client.get("/apim/management/apis/hello/revisions", headers=headers)
        api_releases = client.get("/apim/management/apis/hello/releases", headers=headers)
        operation_tags = client.get("/apim/management/apis/hello/operations/getHello/tags", headers=headers)
        product_tags = client.get("/apim/management/products/starter/tags", headers=headers)
        product_groups = client.get("/apim/management/products/starter/groups", headers=headers)

    assert service.status_code == 200
    assert service.json()["id"] == "service/team-sim"
    assert service.json()["counts"]["apis"] == 1
    assert service.json()["counts"]["operations"] == 1
    assert service.json()["counts"]["api_revisions"] == 2
    assert service.json()["counts"]["api_releases"] == 1
    assert service.json()["counts"]["loggers"] == 1
    assert service.json()["counts"]["diagnostics"] == 1
    assert service.json()["counts"]["tags"] == 1
    assert service.json()["counts"]["recent_traces"] == 0

    assert summary.status_code == 200
    assert summary.json()["service"]["display_name"] == "Team Simulator"
    assert summary.json()["tags"][0]["resource_id"] == "service/team-sim/tags/featured"

    assert apis.status_code == 200
    assert apis.json()[0]["resource_id"] == "service/team-sim/apis/hello"
    assert apis.json()[0]["policy_scope"] == {"scope_type": "api", "scope_name": "hello"}
    assert apis.json()[0]["revision"] == "2"
    assert apis.json()[0]["tags"] == ["featured"]

    assert operations.status_code == 200
    assert operations.json()[0]["resource_id"] == "service/team-sim/apis/hello/operations/getHello"
    assert operations.json()[0]["policy_scope"] == {"scope_type": "operation", "scope_name": "hello:getHello"}
    assert operations.json()[0]["tags"] == ["featured"]

    assert products.status_code == 200
    assert products.json()[0]["resource_id"] == "service/team-sim/products/starter"
    assert products.json()[0]["groups"] == ["admins"]
    assert products.json()[0]["tags"] == ["featured"]

    assert subscriptions.status_code == 200
    assert subscriptions.json()[0]["resource_id"] == "service/team-sim/subscriptions/sub-starter-dev"

    assert backends.status_code == 200
    assert backends.json()[0]["resource_id"] == "service/team-sim/backends/hello-backend"

    assert named_values.status_code == 200
    assert named_values.json()[0]["resource_id"] == "service/team-sim/named-values/backend-secret"
    assert named_values.json()[0]["value"] == "***"
    assert named_values.json()[0]["resolved"]["value"] == "***"

    assert loggers.status_code == 200
    assert loggers.json()[0]["resource_id"] == "service/team-sim/loggers/appinsights"
    assert loggers.json()[0]["application_insights"]["instrumentation_key"] == "***"

    assert diagnostics.status_code == 200
    assert diagnostics.json()[0]["resource_id"] == "service/team-sim/diagnostics/applicationinsights"
    assert diagnostics.json()[0]["logger_resource_id"] == "service/team-sim/loggers/appinsights"

    assert version_sets.status_code == 200
    assert version_sets.json()[0]["resource_id"] == "service/team-sim/api-version-sets/public"

    assert fragments.status_code == 200
    assert fragments.json()[0]["resource_id"] == "service/team-sim/policy-fragments/inject-stage"

    assert users.status_code == 200
    assert users.json()[0]["groups"] == ["admins"]
    assert users.json()[0]["resource_id"] == "service/team-sim/users/dev-1"

    assert groups.status_code == 200
    assert groups.json()[0]["users"] == ["dev-1"]
    assert groups.json()[0]["resource_id"] == "service/team-sim/groups/admins"
    assert groups.json()[0]["products"] == ["starter"]

    assert group_users.status_code == 200
    assert group_users.json()[0]["resource_id"] == "service/team-sim/groups/admins/users/dev-1"
    assert group_users.json()[0]["user_resource_id"] == "service/team-sim/users/dev-1"

    assert tags.status_code == 200
    assert tags.json()[0]["resource_id"] == "service/team-sim/tags/featured"

    assert api_tags.status_code == 200
    assert api_tags.json()[0]["resource_id"] == "service/team-sim/apis/hello/tags/featured"

    assert api_revisions.status_code == 200
    assert api_revisions.json()[0]["resource_id"] == "service/team-sim/apis/hello/revisions/1"

    assert api_releases.status_code == 200
    assert api_releases.json()[0]["resource_id"] == "service/team-sim/apis/hello/releases/public"

    assert operation_tags.status_code == 200
    assert operation_tags.json()[0]["resource_id"] == "service/team-sim/apis/hello/operations/getHello/tags/featured"

    assert product_tags.status_code == 200
    assert product_tags.json()[0]["resource_id"] == "service/team-sim/products/starter/tags/featured"

    assert product_groups.status_code == 200
    assert product_groups.json()[0]["resource_id"] == "service/team-sim/products/starter/groups/admins"


def test_management_logger_and_diagnostic_endpoints_are_read_only_and_descriptive() -> None:
    app = create_app(
        config=GatewayConfig(
            service={"name": "team-sim", "display_name": "Team Simulator"},
            allow_anonymous=True,
            tenant_access=TenantAccessConfig(enabled=True, primary_key="t1"),
            loggers={
                "appinsights": LoggerConfig(
                    logger_type="application_insights",
                    description="Primary telemetry sink",
                    resource_id="/subscriptions/test/resourceGroups/rg/providers/Microsoft.Insights/components/demo",
                    application_insights=LoggerApplicationInsightsConfig(
                        instrumentation_key="ikey-secret",
                        connection_string="InstrumentationKey=ikey-secret;IngestionEndpoint=https://example.test/",
                    ),
                )
            },
            diagnostics={
                "applicationinsights": DiagnosticConfig(
                    identifier="applicationinsights",
                    logger_id="appinsights",
                    always_log_errors=True,
                    sampling_percentage=5.0,
                    verbosity="verbose",
                    http_correlation_protocol="W3C",
                    frontend_request=DiagnosticHttpMessageConfig(
                        body_bytes=32,
                        headers_to_log=["content-type", "accept"],
                    ),
                )
            },
        )
    )

    with TestClient(app) as client:
        headers = {"X-Apim-Tenant-Key": "t1"}
        logger_resp = client.get("/apim/management/loggers/appinsights", headers=headers)
        diagnostic_resp = client.get("/apim/management/diagnostics/applicationinsights", headers=headers)

    assert logger_resp.status_code == 200
    assert logger_resp.json()["description"] == "Primary telemetry sink"
    assert logger_resp.json()["application_insights"]["connection_string"] == "***"

    assert diagnostic_resp.status_code == 200
    assert diagnostic_resp.json()["logger_id"] == "appinsights"
    assert diagnostic_resp.json()["logger_resource_id"] == "service/team-sim/loggers/appinsights"
    assert diagnostic_resp.json()["frontend_request"]["body_bytes"] == 32


def test_management_api_schema_endpoints_and_put_preserve_imported_metadata() -> None:
    app = create_app(
        config=GatewayConfig(
            service={"name": "team-sim", "display_name": "Team Simulator"},
            allow_anonymous=True,
            tenant_access=TenantAccessConfig(enabled=True, primary_key="t1"),
            apis={
                "weather": ApiConfig(
                    name="weather",
                    path="weather",
                    upstream_base_url="http://weather-upstream",
                    operations={
                        "current": OperationConfig(
                            name="current",
                            method="GET",
                            url_template="/current/{city}",
                            description="Get current weather",
                            template_parameters=[
                                OperationParameterConfig(
                                    name="city",
                                    required=True,
                                    type="string",
                                    description="City slug",
                                )
                            ],
                            request=OperationRequestMetadataConfig(
                                headers=[
                                    OperationParameterConfig(
                                        name="x-region",
                                        required=False,
                                        type="string",
                                        description="Preferred region",
                                    )
                                ]
                            ),
                            responses=[
                                OperationResponseMetadataConfig(
                                    status_code=200,
                                    description="Weather payload",
                                    representations=[
                                        OperationRepresentationConfig(
                                            content_type="application/json",
                                            schema_id="WeatherResponse",
                                            type_name="WeatherResponse",
                                        )
                                    ],
                                )
                            ],
                        )
                    },
                    schemas={
                        "WeatherResponse": ApiSchemaConfig(
                            content_type="application/json",
                            value='{"type":"object","properties":{"temperature":{"type":"number"}}}',
                        )
                    },
                )
            },
        )
    )

    with TestClient(app) as client:
        headers = {"X-Apim-Tenant-Key": "t1"}

        list_schemas = client.get("/apim/management/apis/weather/schemas", headers=headers)
        get_schema = client.get("/apim/management/apis/weather/schemas/WeatherResponse", headers=headers)
        update_api = client.put(
            "/apim/management/apis/weather",
            headers=headers,
            json={
                "name": "weather",
                "path": "weather-v2",
                "upstream_base_url": "http://weather-upstream-v2",
            },
        )
        update_operation = client.put(
            "/apim/management/apis/weather/operations/current",
            headers=headers,
            json={
                "name": "current",
                "method": "GET",
                "url_template": "/current/{city}",
            },
        )
        get_operation = client.get("/apim/management/apis/weather/operations/current", headers=headers)

    assert list_schemas.status_code == 200
    assert list_schemas.json()[0]["resource_id"] == "service/team-sim/apis/weather/schemas/WeatherResponse"

    assert get_schema.status_code == 200
    assert get_schema.json()["content_type"] == "application/json"

    assert update_api.status_code == 200
    assert update_api.json()["path"] == "weather-v2"
    assert update_api.json()["operations"][0]["id"] == "current"
    assert update_api.json()["schemas"][0]["id"] == "WeatherResponse"

    assert update_operation.status_code == 200
    assert update_operation.json()["description"] == "Get current weather"
    assert update_operation.json()["template_parameters"][0]["name"] == "city"
    assert update_operation.json()["request"]["headers"][0]["name"] == "x-region"
    assert update_operation.json()["responses"][0]["representations"][0]["schema_id"] == "WeatherResponse"

    assert get_operation.status_code == 200
    assert get_operation.json()["description"] == "Get current weather"


def test_management_api_revision_and_release_endpoints_and_put_preserve_metadata() -> None:
    app = create_app(
        config=GatewayConfig(
            service={"name": "team-sim", "display_name": "Team Simulator"},
            allow_anonymous=True,
            tenant_access=TenantAccessConfig(enabled=True, primary_key="t1"),
            apis={
                "weather": ApiConfig(
                    name="weather",
                    path="weather",
                    upstream_base_url="http://weather-upstream",
                    revision="2",
                    revision_description="Current revision",
                    source_api_id="service/team-sim/apis/weather;rev=1",
                    is_current=True,
                    is_online=True,
                    revisions={
                        "1": ApiRevisionConfig(
                            revision="1", description="Initial revision", is_current=False, is_online=False
                        ),
                        "2": ApiRevisionConfig(
                            revision="2",
                            description="Current revision",
                            is_current=True,
                            is_online=True,
                            source_api_id="service/team-sim/apis/weather;rev=1",
                        ),
                    },
                    releases={
                        "public": ApiReleaseConfig(
                            name="public",
                            api_id="service/team-sim/apis/weather;rev=2",
                            notes="Shipped publicly",
                            revision="2",
                        )
                    },
                )
            },
        )
    )

    with TestClient(app) as client:
        headers = {"X-Apim-Tenant-Key": "t1"}

        list_revisions = client.get("/apim/management/apis/weather/revisions", headers=headers)
        get_revision = client.get("/apim/management/apis/weather/revisions/2", headers=headers)
        list_releases = client.get("/apim/management/apis/weather/releases", headers=headers)
        get_release = client.get("/apim/management/apis/weather/releases/public", headers=headers)
        update_api = client.put(
            "/apim/management/apis/weather",
            headers=headers,
            json={
                "name": "weather",
                "path": "weather-v2",
                "upstream_base_url": "http://weather-upstream-v2",
            },
        )
        get_api = client.get("/apim/management/apis/weather", headers=headers)

    assert list_revisions.status_code == 200
    assert list_revisions.json()[0]["resource_id"] == "service/team-sim/apis/weather/revisions/1"

    assert get_revision.status_code == 200
    assert get_revision.json()["is_current"] is True

    assert list_releases.status_code == 200
    assert list_releases.json()[0]["resource_id"] == "service/team-sim/apis/weather/releases/public"

    assert get_release.status_code == 200
    assert get_release.json()["revision"] == "2"

    assert update_api.status_code == 200
    assert update_api.json()["revision"] == "2"
    assert update_api.json()["revisions"][1]["id"] == "2"
    assert update_api.json()["releases"][0]["id"] == "public"

    assert get_api.status_code == 200
    assert get_api.json()["releases"][0]["notes"] == "Shipped publicly"


def test_management_tag_crud_and_links_persist_without_parent_put_wiping_assignments(
    tmp_path: Path, monkeypatch
) -> None:
    config_path = tmp_path / "apim-tags.json"
    config_path.write_text(
        json.dumps(
            {
                "service": {"name": "tag-sim", "display_name": "Tag Simulator"},
                "allow_anonymous": True,
                "tenant_access": {"enabled": True, "primary_key": "t1"},
                "products": {"starter": {"name": "Starter", "require_subscription": True}},
                "apis": {
                    "weather": {
                        "name": "weather",
                        "path": "weather",
                        "upstream_base_url": "http://weather-upstream",
                        "operations": {"current": {"name": "current", "method": "GET", "url_template": "/current"}},
                    }
                },
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("APIM_CONFIG_PATH", str(config_path))

    app = create_app()
    with TestClient(app) as client:
        headers = {"X-Apim-Tenant-Key": "t1"}

        created_tag = client.put("/apim/management/tags/featured", headers=headers, json={"display_name": "Featured"})
        api_link = client.put("/apim/management/apis/weather/tags/featured", headers=headers)
        product_link = client.put("/apim/management/products/starter/tags/featured", headers=headers)
        operation_link = client.put("/apim/management/apis/weather/operations/current/tags/featured", headers=headers)

        api_update = client.put(
            "/apim/management/apis/weather",
            headers=headers,
            json={"name": "weather", "path": "weather-v2", "upstream_base_url": "http://weather-upstream-v2"},
        )
        product_update = client.put(
            "/apim/management/products/starter",
            headers=headers,
            json={"name": "Starter", "description": "Starter tier", "require_subscription": True},
        )
        operation_update = client.put(
            "/apim/management/apis/weather/operations/current",
            headers=headers,
            json={"name": "current", "method": "GET", "url_template": "/current"},
        )

        list_tags = client.get("/apim/management/tags", headers=headers)
        api_tags = client.get("/apim/management/apis/weather/tags", headers=headers)
        product_tags = client.get("/apim/management/products/starter/tags", headers=headers)
        operation_tags = client.get("/apim/management/apis/weather/operations/current/tags", headers=headers)

        persisted_after_create = json.loads(config_path.read_text(encoding="utf-8"))

        deleted_tag = client.delete("/apim/management/tags/featured", headers=headers)
        persisted_after_delete = json.loads(config_path.read_text(encoding="utf-8"))

    assert created_tag.status_code == 200
    assert created_tag.json()["resource_id"] == "service/tag-sim/tags/featured"

    assert api_link.status_code == 200
    assert api_link.json()["resource_id"] == "service/tag-sim/apis/weather/tags/featured"

    assert product_link.status_code == 200
    assert product_link.json()["resource_id"] == "service/tag-sim/products/starter/tags/featured"

    assert operation_link.status_code == 200
    assert operation_link.json()["resource_id"] == "service/tag-sim/apis/weather/operations/current/tags/featured"

    assert api_update.status_code == 200
    assert api_update.json()["tags"] == ["featured"]

    assert product_update.status_code == 200
    assert product_update.json()["tags"] == ["featured"]

    assert operation_update.status_code == 200
    assert operation_update.json()["tags"] == ["featured"]

    assert list_tags.status_code == 200
    assert list_tags.json()[0]["display_name"] == "Featured"

    assert api_tags.status_code == 200
    assert api_tags.json()[0]["resource_id"] == "service/tag-sim/apis/weather/tags/featured"

    assert product_tags.status_code == 200
    assert product_tags.json()[0]["resource_id"] == "service/tag-sim/products/starter/tags/featured"

    assert operation_tags.status_code == 200
    assert operation_tags.json()[0]["resource_id"] == "service/tag-sim/apis/weather/operations/current/tags/featured"

    assert persisted_after_create["tags"]["featured"]["display_name"] == "Featured"
    assert persisted_after_create["apis"]["weather"]["tags"] == ["featured"]
    assert persisted_after_create["apis"]["weather"]["operations"]["current"]["tags"] == ["featured"]
    assert persisted_after_create["products"]["starter"]["tags"] == ["featured"]

    assert deleted_tag.status_code == 200
    assert "featured" not in persisted_after_delete["tags"]
    assert persisted_after_delete["apis"]["weather"]["tags"] == []
    assert persisted_after_delete["apis"]["weather"]["operations"]["current"]["tags"] == []
    assert persisted_after_delete["products"]["starter"]["tags"] == []


def test_management_group_crud_and_product_group_links_persist_without_product_put_wiping_assignments(
    tmp_path: Path, monkeypatch
) -> None:
    config_path = tmp_path / "apim-groups.json"
    config_path.write_text(
        json.dumps(
            {
                "service": {"name": "group-sim", "display_name": "Group Simulator"},
                "allow_anonymous": True,
                "tenant_access": {"enabled": True, "primary_key": "t1"},
                "products": {"starter": {"name": "Starter", "require_subscription": True}},
                "groups": {},
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("APIM_CONFIG_PATH", str(config_path))

    app = create_app()
    with TestClient(app) as client:
        headers = {"X-Apim-Tenant-Key": "t1"}

        created_group = client.put(
            "/apim/management/groups/developers",
            headers=headers,
            json={"name": "Developers", "description": "Internal developers", "type": "custom"},
        )
        group_link = client.put("/apim/management/products/starter/groups/developers", headers=headers)
        product_update = client.put(
            "/apim/management/products/starter",
            headers=headers,
            json={"name": "Starter", "description": "Starter tier", "require_subscription": True},
        )
        list_groups = client.get("/apim/management/groups", headers=headers)
        get_group = client.get("/apim/management/groups/developers", headers=headers)
        product_groups = client.get("/apim/management/products/starter/groups", headers=headers)

        persisted_after_create = json.loads(config_path.read_text(encoding="utf-8"))

        deleted_group = client.delete("/apim/management/groups/developers", headers=headers)
        persisted_after_delete = json.loads(config_path.read_text(encoding="utf-8"))

    assert created_group.status_code == 200
    assert created_group.json()["resource_id"] == "service/group-sim/groups/developers"
    assert created_group.json()["description"] == "Internal developers"

    assert group_link.status_code == 200
    assert group_link.json()["resource_id"] == "service/group-sim/products/starter/groups/developers"

    assert product_update.status_code == 200
    assert product_update.json()["groups"] == ["developers"]

    assert list_groups.status_code == 200
    assert list_groups.json()[0]["products"] == ["starter"]

    assert get_group.status_code == 200
    assert get_group.json()["type"] == "custom"

    assert product_groups.status_code == 200
    assert product_groups.json()[0]["group_resource_id"] == "service/group-sim/groups/developers"

    assert persisted_after_create["groups"]["developers"]["name"] == "Developers"
    assert persisted_after_create["products"]["starter"]["groups"] == ["developers"]

    assert deleted_group.status_code == 200
    assert "developers" not in persisted_after_delete["groups"]
    assert persisted_after_delete["products"]["starter"]["groups"] == []


def test_management_user_crud_and_group_user_links_persist_without_group_put_wiping_memberships(
    tmp_path: Path, monkeypatch
) -> None:
    config_path = tmp_path / "apim-group-users.json"
    config_path.write_text(
        json.dumps(
            {
                "service": {"name": "user-sim", "display_name": "User Simulator"},
                "allow_anonymous": True,
                "tenant_access": {"enabled": True, "primary_key": "t1"},
                "users": {},
                "groups": {"developers": {"id": "developers", "name": "Developers"}},
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("APIM_CONFIG_PATH", str(config_path))

    app = create_app()
    with TestClient(app) as client:
        headers = {"X-Apim-Tenant-Key": "t1"}

        created_user = client.put(
            "/apim/management/users/alice",
            headers=headers,
            json={
                "email": "alice@example.com",
                "first_name": "Alice",
                "last_name": "Dev",
                "note": "Internal developer",
                "state": "active",
                "confirmation": "invite",
            },
        )
        group_user_link = client.put("/apim/management/groups/developers/users/alice", headers=headers)
        group_update = client.put(
            "/apim/management/groups/developers",
            headers=headers,
            json={"name": "Developers", "description": "Engineering team", "type": "custom"},
        )
        list_users = client.get("/apim/management/users", headers=headers)
        group_users = client.get("/apim/management/groups/developers/users", headers=headers)
        get_user = client.get("/apim/management/users/alice", headers=headers)

        persisted_after_create = json.loads(config_path.read_text(encoding="utf-8"))

        deleted_user = client.delete("/apim/management/users/alice", headers=headers)
        persisted_after_delete = json.loads(config_path.read_text(encoding="utf-8"))

    assert created_user.status_code == 200
    assert created_user.json()["resource_id"] == "service/user-sim/users/alice"
    assert created_user.json()["first_name"] == "Alice"
    assert created_user.json()["groups"] == []

    assert group_user_link.status_code == 200
    assert group_user_link.json()["resource_id"] == "service/user-sim/groups/developers/users/alice"

    assert group_update.status_code == 200
    assert group_update.json()["users"] == ["alice"]

    assert list_users.status_code == 200
    assert list_users.json()[0]["groups"] == ["developers"]

    assert group_users.status_code == 200
    assert group_users.json()[0]["user_resource_id"] == "service/user-sim/users/alice"

    assert get_user.status_code == 200
    assert get_user.json()["name"] == "Alice Dev"

    assert persisted_after_create["groups"]["developers"]["users"] == ["alice"]
    assert persisted_after_create["users"]["alice"]["email"] == "alice@example.com"

    assert deleted_user.status_code == 200
    assert "alice" not in persisted_after_delete["users"]
    assert persisted_after_delete["groups"]["developers"]["users"] == []


def test_management_crud_persists_api_authored_resources(tmp_path: Path, monkeypatch) -> None:
    config_path = tmp_path / "apim.json"
    config_path.write_text(
        json.dumps(
            {
                "service": {"name": "persisted-sim", "display_name": "Persisted Simulator"},
                "allow_anonymous": True,
                "tenant_access": {"enabled": True, "primary_key": "t1"},
                "products": {},
                "backends": {},
                "named_values": {},
                "policy_fragments": {},
                "apis": {},
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("APIM_CONFIG_PATH", str(config_path))

    app = create_app()
    with TestClient(app) as client:
        headers = {"X-Apim-Tenant-Key": "t1"}

        product = client.put(
            "/apim/management/products/starter",
            headers=headers,
            json={"name": "Starter", "description": "Starter tier", "require_subscription": True},
        )
        backend = client.put(
            "/apim/management/backends/weather-backend",
            headers=headers,
            json={"url": "http://weather-backend", "description": "Weather backend"},
        )
        named_value = client.put(
            "/apim/management/named-values/upstream-key",
            headers=headers,
            json={"value": "abc123", "secret": True},
        )
        fragment = client.put(
            "/apim/management/policy-fragments/add-stage",
            headers=headers,
            json={"xml": '<set-header name="x-stage" exists-action="override"><value>dev</value></set-header>'},
        )
        api = client.put(
            "/apim/management/apis/weather",
            headers=headers,
            json={
                "name": "weather",
                "path": "weather",
                "upstream_base_url": "http://weather-backend",
                "backend": "weather-backend",
                "products": ["starter"],
                "policies_xml": "<policies><inbound><base /></inbound><backend /><outbound /><on-error /></policies>",
            },
        )
        operation = client.put(
            "/apim/management/apis/weather/operations/current",
            headers=headers,
            json={
                "name": "current",
                "method": "GET",
                "url_template": "/current",
                "products": ["starter"],
            },
        )

        persisted_after_create = json.loads(config_path.read_text(encoding="utf-8"))

        delete_operation = client.delete("/apim/management/apis/weather/operations/current", headers=headers)
        delete_api = client.delete("/apim/management/apis/weather", headers=headers)
        delete_fragment = client.delete("/apim/management/policy-fragments/add-stage", headers=headers)

        persisted_after_delete = json.loads(config_path.read_text(encoding="utf-8"))

    assert product.status_code == 200
    assert product.json()["resource_id"] == "service/persisted-sim/products/starter"

    assert backend.status_code == 200
    assert backend.json()["resource_id"] == "service/persisted-sim/backends/weather-backend"

    assert named_value.status_code == 200
    assert named_value.json()["resource_id"] == "service/persisted-sim/named-values/upstream-key"

    assert fragment.status_code == 200
    assert fragment.json()["resource_id"] == "service/persisted-sim/policy-fragments/add-stage"

    assert api.status_code == 200
    assert api.json()["resource_id"] == "service/persisted-sim/apis/weather"

    assert operation.status_code == 200
    assert operation.json()["resource_id"] == "service/persisted-sim/apis/weather/operations/current"

    assert persisted_after_create["routes"] == []
    assert "starter" in persisted_after_create["products"]
    assert "weather-backend" in persisted_after_create["backends"]
    assert "upstream-key" in persisted_after_create["named_values"]
    assert "add-stage" in persisted_after_create["policy_fragments"]
    assert "weather" in persisted_after_create["apis"]
    assert "current" in persisted_after_create["apis"]["weather"]["operations"]

    assert delete_operation.status_code == 200
    assert delete_api.status_code == 200
    assert delete_fragment.status_code == 200
    assert "current" not in persisted_after_delete["apis"].get("weather", {}).get("operations", {})
    assert "weather" not in persisted_after_delete["apis"]
    assert "add-stage" not in persisted_after_delete["policy_fragments"]


def test_platform_style_mounted_config_allows_jwt_requests(tmp_path: Path, monkeypatch) -> None:
    issuer = "http://issuer.example"
    audience = "api-app"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(
        private_key=private_key,
        issuer=issuer,
        audience=audience,
        extra_claims={"realm_access": {"roles": ["user"]}},
    )

    config_path = tmp_path / "platform-mounted.json"
    config_path.write_text(
        json.dumps(
            {
                "allow_anonymous": False,
                "oidc": {"issuer": issuer, "audience": audience, "jwks": jwks},
                "tenant_access": {"enabled": True, "primary_key": "platform-tenant"},
                "products": {
                    "subnet-calculator": {
                        "name": "Subnet Calculator",
                        "require_subscription": True,
                    }
                },
                "subscription": {
                    "required": True,
                    "subscriptions": {
                        "platform-demo": {
                            "id": "platform-demo",
                            "name": "platform-demo",
                            "keys": {"primary": "platform-demo-key", "secondary": "platform-demo-key-secondary"},
                            "products": ["subnet-calculator"],
                        }
                    },
                },
                "routes": [
                    {
                        "name": "subnet-calculator-api",
                        "path_prefix": "/api",
                        "upstream_base_url": "http://upstream",
                        "upstream_path_prefix": "/api",
                        "product": "subnet-calculator",
                        "authz": {"required_roles": ["user"]},
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("APIM_CONFIG_PATH", str(config_path))

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.url == httpx.URL("http://upstream/api/health")
        return httpx.Response(200, json={"ok": True})

    app = create_app(http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        health = client.get("/apim/health")
        startup = client.get("/apim/startup")
        status = client.get("/apim/management/status", headers={"X-Apim-Tenant-Key": "platform-tenant"})
        ok = client.get(
            "/api/health",
            headers={
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-Subscription-Key": "platform-demo-key",
            },
        )

    assert health.status_code == 200
    assert startup.status_code == 200
    assert status.status_code == 200
    assert status.json()["service"]["name"] == "apim-simulator"
    assert ok.status_code == 200


def test_management_policy_get_put_updates_route_policy_in_memory() -> None:
    policy_xml = """\
<policies>
  <inbound />
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    config = GatewayConfig(
        allow_anonymous=True,
        tenant_access=TenantAccessConfig(enabled=True, primary_key="t1"),
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://upstream",
                upstream_path_prefix="/api",
                policies_xml=policy_xml,
            )
        ],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert req.headers.get("x-managed") == "1"
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        current = client.get("/apim/management/policies/route/r1", headers={"X-Apim-Tenant-Key": "t1"})
        assert current.status_code == 200
        assert current.json()["xml"] == policy_xml

        updated = client.put(
            "/apim/management/policies/route/r1",
            headers={"X-Apim-Tenant-Key": "t1"},
            json={
                "xml": """\
<policies>
  <inbound>
    <set-header name="x-managed" exists-action="override"><value>1</value></set-header>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
            },
        )
        assert updated.status_code == 200

        ok = client.get("/api/health")

    assert ok.status_code == 200


def test_management_replay_returns_response_and_trace() -> None:
    def handler(req: httpx.Request) -> httpx.Response:
        assert req.url == httpx.URL("http://upstream/api/health?mode=debug")
        return httpx.Response(200, json={"ok": True})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            tenant_access=TenantAccessConfig(enabled=True, primary_key="t1"),
            trace_enabled=True,
            proxy_streaming=False,
            routes=[
                RouteConfig(
                    name="r1",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                    upstream_path_prefix="/api",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        replay = client.post(
            "/apim/management/replay",
            headers={"X-Apim-Tenant-Key": "t1"},
            json={"method": "GET", "path": "/api/health", "query": {"mode": "debug"}},
        )

    assert replay.status_code == 200
    payload = replay.json()
    assert payload["response"]["status_code"] == 200
    assert payload["trace_id"]
    assert payload["trace"]["route"] == "r1"


def test_mtls_mode_disabled_allows_requests_without_cert() -> None:
    """When client_certificate mode is disabled, requests without certs succeed."""
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            client_certificate=ClientCertificateConfig(mode=ClientCertificateMode.Disabled),
            routes=[
                RouteConfig(
                    name="default",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        resp = client.get("/api/test")
        assert resp.status_code == 200


def test_mtls_mode_required_rejects_request_without_cert() -> None:
    """When client_certificate mode is required, requests without certs are rejected."""
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            client_certificate=ClientCertificateConfig(mode=ClientCertificateMode.Required),
            routes=[
                RouteConfig(
                    name="default",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        resp = client.get("/api/test")
        assert resp.status_code == 401
        assert "Client certificate required" in resp.json()["detail"]


def test_mtls_mode_required_accepts_request_with_cert() -> None:
    """When client_certificate mode is required, requests with cert headers succeed."""
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            client_certificate=ClientCertificateConfig(mode=ClientCertificateMode.Required),
            routes=[
                RouteConfig(
                    name="default",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        resp = client.get(
            "/api/test",
            headers={
                "X-Client-Cert-Subject": "CN=client,O=test",
                "X-Client-Cert-Issuer": "CN=ca,O=test",
            },
        )
        assert resp.status_code == 200


def test_mtls_mode_optional_allows_requests_without_cert() -> None:
    """When client_certificate mode is optional, requests without certs succeed."""
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            client_certificate=ClientCertificateConfig(mode=ClientCertificateMode.Optional),
            routes=[
                RouteConfig(
                    name="default",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        resp = client.get("/api/test")
        assert resp.status_code == 200


def test_mtls_trusted_cert_by_thumbprint() -> None:
    """When trusted_certificates is configured, certs matching thumbprint are accepted."""
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            client_certificate=ClientCertificateConfig(
                mode=ClientCertificateMode.Required,
                trusted_certificates=[
                    TrustedClientCertificateConfig(
                        name="allowed-client",
                        thumbprint="ABC123DEF456",
                    )
                ],
            ),
            routes=[
                RouteConfig(
                    name="default",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        # Matching thumbprint (case-insensitive)
        resp = client.get(
            "/api/test",
            headers={"X-Client-Cert-Thumbprint": "abc123def456"},
        )
        assert resp.status_code == 200

        # Non-matching thumbprint
        resp = client.get(
            "/api/test",
            headers={"X-Client-Cert-Thumbprint": "wrong-thumbprint"},
        )
        assert resp.status_code == 403
        assert "not trusted" in resp.json()["detail"]


def test_mtls_trusted_cert_by_subject() -> None:
    """When trusted_certificates is configured, certs matching subject are accepted."""
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            client_certificate=ClientCertificateConfig(
                mode=ClientCertificateMode.Required,
                trusted_certificates=[
                    TrustedClientCertificateConfig(
                        name="allowed-client",
                        subject="CN=allowed-client",
                    )
                ],
            ),
            routes=[
                RouteConfig(
                    name="default",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        # Matching subject (contains)
        resp = client.get(
            "/api/test",
            headers={"X-Client-Cert-Subject": "CN=allowed-client,O=test"},
        )
        assert resp.status_code == 200

        # Non-matching subject
        resp = client.get(
            "/api/test",
            headers={"X-Client-Cert-Subject": "CN=other-client,O=test"},
        )
        assert resp.status_code == 403


def test_mtls_trusted_cert_by_issuer() -> None:
    """When trusted_certificates is configured, certs matching issuer are accepted."""
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            client_certificate=ClientCertificateConfig(
                mode=ClientCertificateMode.Required,
                trusted_certificates=[
                    TrustedClientCertificateConfig(
                        name="allowed-issuer",
                        issuer="CN=internal-ca",
                    )
                ],
            ),
            routes=[
                RouteConfig(
                    name="default",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        # Matching issuer
        resp = client.get(
            "/api/test",
            headers={"X-Client-Cert-Issuer": "CN=internal-ca,O=myorg"},
        )
        assert resp.status_code == 200

        # Non-matching issuer
        resp = client.get(
            "/api/test",
            headers={"X-Client-Cert-Issuer": "CN=external-ca"},
        )
        assert resp.status_code == 403


def test_mtls_custom_header_names() -> None:
    """Custom header names for client cert info are respected."""
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            client_certificate=ClientCertificateConfig(
                mode=ClientCertificateMode.Required,
                subject_header="X-SSL-Client-Subject",
                issuer_header="X-SSL-Client-Issuer",
                thumbprint_header="X-SSL-Client-Fingerprint",
            ),
            routes=[
                RouteConfig(
                    name="default",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        # Standard headers - should fail (no cert detected)
        resp = client.get(
            "/api/test",
            headers={"X-Client-Cert-Subject": "CN=client"},
        )
        assert resp.status_code == 401

        # Custom headers - should succeed
        resp = client.get(
            "/api/test",
            headers={"X-SSL-Client-Subject": "CN=client"},
        )
        assert resp.status_code == 200


def test_startup_probe_returns_200_when_ready() -> None:
    """Startup probe returns 200 once app is ready."""
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            routes=[
                RouteConfig(
                    name="default",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        resp = client.get("/apim/startup")
        assert resp.status_code == 200
        assert resp.json()["status"] == "started"


def test_reload_endpoint_reloads_config() -> None:
    """Reload endpoint triggers config reload."""
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            routes=[
                RouteConfig(
                    name="default",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        resp = client.post("/apim/reload")
        assert resp.status_code == 200
        assert resp.json()["status"] == "reloaded"
        assert "routes" in resp.json()


def test_reload_requires_admin_token_when_configured() -> None:
    """Reload endpoint requires admin token when configured."""
    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            admin_token="secret-admin-token",
            routes=[
                RouteConfig(
                    name="default",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))),
    )
    with TestClient(app) as client:
        # Without token - should fail
        resp = client.post("/apim/reload")
        assert resp.status_code == 403

        # With correct token - should succeed
        resp = client.post("/apim/reload", headers={"X-Apim-Admin-Token": "secret-admin-token"})
        assert resp.status_code == 200
        assert resp.json()["status"] == "reloaded"


def test_named_values_resolve_in_backend_credentials_and_are_masked_in_trace() -> None:
    config = GatewayConfig(
        allow_anonymous=True,
        trace_enabled=True,
        proxy_streaming=False,
        named_values={
            "backend-host": NamedValueConfig(value="backend.example.test"),
            "backend-secret": NamedValueConfig(value="super-secret-token", secret=True),
        },
        backends={
            "b1": BackendConfig(
                url="https://{{backend-host}}",
                authorization_scheme="Bearer",
                authorization_parameter="{{backend-secret}}",
                header_credentials={"x-backend-name": "{{backend-host}}"},
                query_credentials={"sig": "{{backend-secret}}"},
            )
        },
        routes=[
            RouteConfig(
                name="r1",
                path_prefix="/api",
                upstream_base_url="http://ignored",
                upstream_path_prefix="/api",
                backend="b1",
            )
        ],
    )

    def handler(req: httpx.Request) -> httpx.Response:
        assert str(req.url) == "https://backend.example.test/api/health?sig=super-secret-token"
        assert req.headers["authorization"] == "Bearer super-secret-token"
        assert req.headers["x-backend-name"] == "backend.example.test"
        return httpx.Response(200, json={"ok": True})

    app = create_app(config=config, http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    with TestClient(app) as client:
        resp = client.get("/api/health", headers={"x-apim-trace": "true"})
        trace = client.get(f"/apim/trace/{resp.headers['x-apim-trace-id']}")

    assert resp.status_code == 200
    assert trace.status_code == 200
    payload = trace.json()
    assert payload["selected_backend"]["backend_id"] == "b1"
    assert "super-secret-token" not in json.dumps(payload)


def test_validate_jwt_policy_uses_openid_config_and_updates_claim_headers() -> None:
    issuer = "https://issuer.example"
    audience = "sample-api"
    jwks, private_key = _make_rsa_jwks()
    token = _make_token(private_key=private_key, issuer=issuer, audience=audience, extra_claims={"scope": "read"})

    policy = """\
<policies>
  <inbound>
    <validate-jwt header-name="Authorization" require-scheme="Bearer" require-expiration-time="false" output-token-variable-name="jwt">
      <openid-config url="https://issuer.example/.well-known/openid-configuration" />
      <audiences>
        <audience>sample-api</audience>
      </audiences>
      <required-claims>
        <claim name="scope" match="any" separator=" ">
          <value>read</value>
        </claim>
      </required-claims>
    </validate-jwt>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    def handler(req: httpx.Request) -> httpx.Response:
        if req.url == httpx.URL("https://issuer.example/.well-known/openid-configuration"):
            return httpx.Response(200, json={"issuer": issuer, "jwks_uri": "https://issuer.example/jwks"})
        if req.url == httpx.URL("https://issuer.example/jwks"):
            return httpx.Response(200, json=jwks)
        assert req.url == httpx.URL("http://upstream/api/health")
        assert req.headers["x-apim-user-object-id"] == "user-123"
        assert req.headers["x-ms-client-principal-name"] == "demo@dev.test"
        return httpx.Response(200, json={"ok": True})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            trace_enabled=True,
            proxy_streaming=False,
            routes=[
                RouteConfig(
                    name="r1",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                    upstream_path_prefix="/api",
                    policies_xml=policy,
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        resp = client.get("/api/health", headers={"Authorization": f"Bearer {token}", "x-apim-trace": "true"})
        trace = client.get(f"/apim/trace/{resp.headers['x-apim-trace-id']}")

    assert resp.status_code == 200
    assert trace.status_code == 200
    payload = trace.json()
    assert payload["jwt_validations"][0]["status"] == "valid"


def test_send_request_policy_can_branch_on_response_body() -> None:
    policy = """\
<policies>
  <inbound>
    <set-variable name="token" value="@(context.Request.Headers.GetValueOrDefault(&quot;Authorization&quot;,&quot;scheme param&quot;).Split(&#x27; &#x27;).Last())" />
    <send-request mode="new" response-variable-name="tokenstate" timeout="20" ignore-error="true">
      <set-url>https://introspection.example/token</set-url>
      <set-method>POST</set-method>
      <set-header name="Authorization" exists-action="override">
        <value>basic demo</value>
      </set-header>
      <set-header name="Content-Type" exists-action="override">
        <value>application/x-www-form-urlencoded</value>
      </set-header>
      <set-body>@($&quot;token={(string)context.Variables[&quot;token&quot;]}&quot;)</set-body>
    </send-request>
    <choose>
      <when condition="@((bool)((IResponse)context.Variables[&quot;tokenstate&quot;]).Body.As&lt;JObject&gt;()[&quot;active&quot;] == false)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error=&quot;invalid_token&quot;</value>
          </set-header>
        </return-response>
      </when>
    </choose>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    def handler(req: httpx.Request) -> httpx.Response:
        if req.url == httpx.URL("https://introspection.example/token"):
            assert req.method == "POST"
            assert req.content == b"token=opaque"
            return httpx.Response(200, json={"active": False})
        return httpx.Response(200, json={"ok": True})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            routes=[
                RouteConfig(
                    name="r1",
                    path_prefix="/api",
                    upstream_base_url="http://upstream",
                    upstream_path_prefix="/api",
                    policies_xml=policy,
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        resp = client.get("/api/health", headers={"Authorization": "Bearer opaque"})

    assert resp.status_code == 401
    assert resp.headers["www-authenticate"] == 'Bearer error="invalid_token"'


def test_set_backend_service_policy_switches_backend_by_query() -> None:
    policy = """\
<policies>
  <inbound>
    <choose>
      <when condition="@(context.Request.Url.Query.GetValueOrDefault(&quot;version&quot;) == &quot;2013-05&quot;)">
        <set-backend-service base-url="http://upstream-v1/api/8.2" />
      </when>
    </choose>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    seen_urls: list[str] = []

    def handler(req: httpx.Request) -> httpx.Response:
        seen_urls.append(str(req.url))
        return httpx.Response(200, json={"ok": True})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            routes=[
                RouteConfig(
                    name="r1",
                    path_prefix="/api",
                    upstream_base_url="http://upstream-default/api/10.4",
                    policies_xml=policy,
                )
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        resp = client.get("/api/partners/15", params={"version": "2013-05"})

    assert resp.status_code == 200
    assert seen_urls == ["http://upstream-v1/api/8.2/partners/15?version=2013-05"]


def test_rate_limit_by_key_supports_response_condition_and_custom_headers() -> None:
    policy = """\
<policies>
  <inbound>
    <rate-limit-by-key
      calls="1"
      renewal-period="60"
      counter-key="@(context.Request.Headers.GetValueOrDefault(&quot;x-key&quot;,&quot;anon&quot;))"
      increment-condition="@(context.Response.StatusCode == 200)"
      retry-after-header-name="X-Retry"
      retry-after-variable-name="retry_after"
      remaining-calls-header-name="X-Remaining"
      remaining-calls-variable-name="remaining_calls"
      total-calls-header-name="X-Total" />
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    seen_urls: list[str] = []

    def handler(req: httpx.Request) -> httpx.Response:
        seen_urls.append(str(req.url))
        return httpx.Response(200, json={"ok": True})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            trace_enabled=True,
            proxy_streaming=False,
            routes=[
                RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", policies_xml=policy)
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        first = client.get("/api/items", headers={"x-key": "demo", "x-apim-trace": "true"})
        first_trace = client.get(f"/apim/trace/{first.headers['x-apim-trace-id']}")
        second = client.get("/api/items", headers={"x-key": "demo", "x-apim-trace": "true"})
        second_trace = client.get(f"/apim/trace/{second.headers['x-apim-trace-id']}")

    assert first.status_code == 200
    assert first.headers["x-remaining"] == "0"
    assert first.headers["x-total"] == "1"
    assert second.status_code == 429
    assert second.headers["x-retry"]
    assert seen_urls == ["http://upstream/items"]
    assert first_trace.json()["policy_variable_writes"][-1]["name"] == "remaining_calls"
    assert second_trace.json()["policy_variable_writes"][-1]["name"] == "retry_after"


def test_quota_by_key_respects_first_period_start(monkeypatch: Any) -> None:
    import app.policy as policy_module

    fixed_now = datetime(2026, 4, 2, 10, 1, 0, tzinfo=UTC).timestamp()
    monkeypatch.setattr(policy_module.time, "time", lambda: fixed_now)

    policy = """\
<policies>
  <inbound>
    <quota-by-key
      calls="1"
      renewal-period="300"
      counter-key="@(context.Request.IpAddress)"
      first-period-start="2026-04-02T10:00:00Z" />
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    seen_urls: list[str] = []

    def handler(req: httpx.Request) -> httpx.Response:
        seen_urls.append(str(req.url))
        return httpx.Response(200, json={"ok": True})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            routes=[
                RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", policies_xml=policy)
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        first = client.get("/api/health", headers={"X-Forwarded-For": "10.1.2.3"})
        second = client.get("/api/health", headers={"X-Forwarded-For": "10.1.2.3"})

    assert first.status_code == 200
    assert second.status_code == 403
    assert second.headers["retry-after"] == "240"
    assert seen_urls == ["http://upstream/health"]


def test_cache_lookup_and_store_hit_and_vary_by_query_parameter() -> None:
    policy = """\
<policies>
  <inbound>
    <cache-lookup
      vary-by-developer="false"
      vary-by-developer-groups="false"
      caching-type="prefer-external"
      downstream-caching-type="public"
      must-revalidate="true">
      <vary-by-query-parameter>version</vary-by-query-parameter>
    </cache-lookup>
  </inbound>
  <backend />
  <outbound>
    <cache-store duration="60" />
  </outbound>
  <on-error />
</policies>
"""

    call_count = {"value": 0}

    def handler(req: httpx.Request) -> httpx.Response:
        call_count["value"] += 1
        return httpx.Response(200, json={"call": call_count["value"]})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            proxy_streaming=True,
            routes=[
                RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", policies_xml=policy)
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        first = client.get("/api/catalog", params={"version": "v1"})
        second = client.get("/api/catalog", params={"version": "v1"})
        third = client.get("/api/catalog", params={"version": "v2"})

    assert first.json() == {"call": 1}
    assert second.json() == {"call": 1}
    assert third.json() == {"call": 2}
    assert call_count["value"] == 2
    assert second.headers["cache-control"] == "public, must-revalidate"


def test_cache_lookup_varies_by_developer_subscription() -> None:
    policy = """\
<policies>
  <inbound>
    <cache-lookup
      vary-by-developer="true"
      vary-by-developer-groups="false"
      caching-type="internal"
      downstream-caching-type="private"
      must-revalidate="true" />
  </inbound>
  <backend />
  <outbound>
    <cache-store duration="60" />
  </outbound>
  <on-error />
</policies>
"""

    call_count = {"value": 0}

    def handler(req: httpx.Request) -> httpx.Response:
        call_count["value"] += 1
        return httpx.Response(200, json={"call": call_count["value"]})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            subscription=SubscriptionConfig(
                required=True,
                subscriptions={
                    "a": Subscription(
                        id="sub-a", name="A", keys=SubscriptionKeyPair(primary="key-a", secondary="key-a-2")
                    ),
                    "b": Subscription(
                        id="sub-b", name="B", keys=SubscriptionKeyPair(primary="key-b", secondary="key-b-2")
                    ),
                },
            ),
            routes=[
                RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", policies_xml=policy)
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        first = client.get("/api/catalog", headers={"Ocp-Apim-Subscription-Key": "key-a"})
        second = client.get("/api/catalog", headers={"Ocp-Apim-Subscription-Key": "key-a"})
        third = client.get("/api/catalog", headers={"Ocp-Apim-Subscription-Key": "key-b"})

    assert first.json() == {"call": 1}
    assert second.json() == {"call": 1}
    assert third.json() == {"call": 2}
    assert call_count["value"] == 2
    assert second.headers["cache-control"] == "private, must-revalidate"


def test_cache_lookup_value_store_and_remove_value() -> None:
    policy = """\
<policies>
  <inbound>
    <choose>
      <when condition="header('x-mode') == 'drop'">
        <cache-remove-value key="@(context.Request.Headers.GetValueOrDefault(&quot;x-user&quot;,&quot;&quot;))" />
        <return-response>
          <set-status code="200" reason="ok" />
          <set-body>removed</set-body>
        </return-response>
      </when>
    </choose>
    <cache-lookup-value key="@(context.Request.Headers.GetValueOrDefault(&quot;x-user&quot;,&quot;&quot;))" variable-name="session" />
    <choose>
      <when condition="@(context.Variables.GetValueOrDefault(&quot;session&quot;,&quot;&quot;) == &quot;warm&quot;)">
        <return-response>
          <set-status code="200" reason="ok" />
          <set-header name="content-type" exists-action="override"><value>application/json</value></set-header>
          <set-body>{"cached":true}</set-body>
        </return-response>
      </when>
    </choose>
  </inbound>
  <backend />
  <outbound>
    <cache-store-value key="@(context.Request.Headers.GetValueOrDefault(&quot;x-user&quot;,&quot;&quot;))" value="warm" duration="60" />
  </outbound>
  <on-error />
</policies>
"""

    call_count = {"value": 0}

    def handler(req: httpx.Request) -> httpx.Response:
        call_count["value"] += 1
        return httpx.Response(200, json={"call": call_count["value"]})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            routes=[
                RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", policies_xml=policy)
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    with TestClient(app) as client:
        first = client.get("/api/value", headers={"x-user": "alice"})
        second = client.get("/api/value", headers={"x-user": "alice"})
        removed = client.get("/api/value", headers={"x-user": "alice", "x-mode": "drop"})
        third = client.get("/api/value", headers={"x-user": "alice"})

    assert first.json() == {"call": 1}
    assert second.json() == {"cached": True}
    assert removed.text == "removed"
    assert third.json() == {"call": 2}
    assert call_count["value"] == 2


def test_external_cache_policy_is_unsupported_at_runtime() -> None:
    policy = """\
<policies>
  <inbound>
    <cache-lookup-value key="demo" variable-name="value" caching-type="external" />
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=True,
            routes=[
                RouteConfig(name="r1", path_prefix="/api", upstream_base_url="http://upstream", policies_xml=policy)
            ],
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json={"ok": True}))),
    )

    with TestClient(app) as client:
        resp = client.get("/api/value")

    assert resp.status_code == 500
    assert resp.json()["detail"] == "Unsupported caching-type external"
