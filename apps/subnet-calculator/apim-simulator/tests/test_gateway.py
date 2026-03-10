from __future__ import annotations

import base64
import json
from typing import Any

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from jwt.algorithms import RSAAlgorithm

from app.config import (
    ApiConfig,
    ApiVersioningScheme,
    ApiVersionSetConfig,
    BackendConfig,
    ClientCertificateConfig,
    ClientCertificateMode,
    GatewayConfig,
    OIDCConfig,
    OperationConfig,
    ProductConfig,
    RouteAuthzConfig,
    RouteConfig,
    Subscription,
    SubscriptionConfig,
    SubscriptionKeyPair,
    SubscriptionState,
    TenantAccessConfig,
    TrustedClientCertificateConfig,
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
        "email": "demo@example.com",
        "name": "Demo User",
        "preferred_username": "demo",
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
        assert req.headers.get("x-apim-user-email") == "demo@example.com"
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
    assert resp.headers.get("x-apim-simulator") == "apim-sim-full"
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
            assert req.url.path == "/health/"
        elif req.method == "POST":
            assert req.url.host == "upstream-post"
            assert req.url.path == "/health/"
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
        http_client=httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))
        ),
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
        http_client=httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))
        ),
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
        http_client=httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))
        ),
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
        http_client=httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))
        ),
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
        http_client=httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))
        ),
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
        http_client=httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))
        ),
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
        http_client=httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))
        ),
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
        http_client=httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))
        ),
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
        http_client=httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))
        ),
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
        http_client=httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))
        ),
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
        http_client=httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))
        ),
    )
    with TestClient(app) as client:
        # Without token - should fail
        resp = client.post("/apim/reload")
        assert resp.status_code == 403

        # With correct token - should succeed
        resp = client.post("/apim/reload", headers={"X-Apim-Admin-Token": "secret-admin-token"})
        assert resp.status_code == 200
        assert resp.json()["status"] == "reloaded"
