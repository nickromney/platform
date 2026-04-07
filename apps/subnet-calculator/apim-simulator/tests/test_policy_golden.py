from __future__ import annotations

from app.config import GatewayConfig, NamedValueConfig
from app.policy import (
    CacheLookup,
    CacheLookupValue,
    CacheRemoveValue,
    CacheStore,
    CacheStoreValue,
    PolicyRequest,
    PolicyRuntime,
    QuotaByKey,
    RateLimitByKey,
    apply_inbound,
    apply_on_error,
    apply_outbound,
    parse_policies_xml,
)


def test_golden_policy_set_header_override() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <set-header name="x-a" exists-action="override"><value>1</value></set-header>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    )
    req = PolicyRequest(method="GET", path="/api/health", query={}, headers={"x-a": "0"}, variables={})
    early = apply_inbound([doc], req)
    assert early is None
    assert req.headers["x-a"] == "1"


def test_golden_policy_return_response() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <return-response>
      <set-status code="401" reason="no" />
      <set-header name="content-type" exists-action="override"><value>text/plain</value></set-header>
      <body>deny</body>
    </return-response>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    )
    req = PolicyRequest(method="GET", path="/api/health", query={}, headers={}, variables={})
    early = apply_inbound([doc], req)
    assert early is not None
    assert early.status_code == 401
    assert early.headers["content-type"] == "text/plain"
    assert early.body == b"deny"


def test_golden_policy_choose_when() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <choose>
      <when condition="query('mode') == 'debug'">
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
    )
    req = PolicyRequest(method="GET", path="/api/health", query={"mode": "debug"}, headers={}, variables={})
    early = apply_inbound([doc], req)
    assert early is None
    assert req.headers["x-mode"] == "debug"


def test_golden_policy_on_error_return_response() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound />
  <backend />
  <outbound />
  <on-error>
    <return-response>
      <set-status code="502" reason="bad" />
      <set-header name="content-type" exists-action="override"><value>text/plain</value></set-header>
      <body>backend-down</body>
    </return-response>
  </on-error>
</policies>
"""
    )
    req = PolicyRequest(method="GET", path="/api/health", query={}, headers={}, variables={"error": "x"})
    out = apply_on_error([doc], req)
    assert out is not None
    assert out.status_code == 502
    assert out.body == b"backend-down"


def test_golden_policy_outbound_set_header() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound />
  <backend />
  <outbound>
    <set-header name="x-out" exists-action="override"><value>1</value></set-header>
  </outbound>
  <on-error />
</policies>
"""
    )
    headers: dict[str, str] = {}
    apply_outbound([doc], headers=headers)
    assert headers["x-out"] == "1"


def test_golden_policy_check_header_denies_when_missing() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <check-header name="x-required" failed-check-httpcode="401" failed-check-error-message="nope" />
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    )
    req = PolicyRequest(method="GET", path="/", query={}, headers={}, variables={})
    early = apply_inbound([doc], req)
    assert early is not None
    assert early.status_code == 401
    assert early.body == b"nope"


def test_golden_policy_ip_filter_denies() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <ip-filter action="allow">
      <address>10.0.0.1</address>
    </ip-filter>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    )
    req = PolicyRequest(method="GET", path="/", query={}, headers={}, variables={"client_ip": "10.0.0.2"})
    early = apply_inbound([doc], req)
    assert early is not None
    assert early.status_code == 403


def test_golden_policy_rate_limit_enforces_429() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <rate-limit calls="1" renewal-period="999999" scope="subscription" />
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    )
    store: dict[str, object] = {}
    req = PolicyRequest(
        method="GET",
        path="/",
        query={},
        headers={},
        variables={
            "route": "r1",
            "subscription_id": "sub1",
            "products": [],
            "client_ip": "10.0.0.1",
            "rate_limit_store": store,
        },
    )
    assert apply_inbound([doc], req) is None
    early = apply_inbound([doc], req)
    assert early is not None
    assert early.status_code == 429


def test_golden_policy_quota_enforces_429() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <quota calls="1" renewal-period="999999" scope="subscription" />
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    )
    store: dict[str, object] = {}
    req = PolicyRequest(
        method="GET",
        path="/",
        query={},
        headers={},
        variables={
            "route": "r1",
            "subscription_id": "sub1",
            "products": [],
            "client_ip": "10.0.0.1",
            "quota_store": store,
        },
    )
    assert apply_inbound([doc], req) is None
    early = apply_inbound([doc], req)
    assert early is not None
    assert early.status_code == 429


def test_golden_policy_set_variable_renders_into_later_policy_values() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <set-variable name="mode" value="{query:mode}" />
    <set-header name="x-mode" exists-action="override"><value>{var:mode}</value></set-header>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    )
    req = PolicyRequest(method="GET", path="/api/health", query={"mode": "debug"}, headers={}, variables={})
    early = apply_inbound([doc], req)
    assert early is None
    assert req.variables["mode"] == "debug"
    assert req.headers["x-mode"] == "debug"


def test_golden_policy_set_query_parameter_mutates_upstream_query_only() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <set-query-parameter name="source" exists-action="override">
      <value>{path}</value>
    </set-query-parameter>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    )
    req = PolicyRequest(method="GET", path="/api/health", query={}, headers={}, variables={})
    early = apply_inbound([doc], req)
    assert early is None
    assert req.query["source"] == "/api/health"


def test_golden_policy_set_body_replaces_request_body() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <set-body>{"path":"{path}","subscription":"{subscription_id}"}</set-body>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    )
    req = PolicyRequest(
        method="POST",
        path="/api/items",
        query={},
        headers={},
        variables={"subscription_id": "sub-1"},
        body=b"original",
    )
    early = apply_inbound([doc], req)
    assert early is None
    assert req.body == b'{"path":"/api/items","subscription":"sub-1"}'


def test_golden_policy_return_response_supports_set_body_template() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <set-variable name="mode" value="{query:mode}" />
    <return-response>
      <set-status code="200" reason="ok" />
      <set-header name="content-type" exists-action="override"><value>application/json</value></set-header>
      <set-body>{"mode":"{var:mode}"}</set-body>
    </return-response>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    )
    req = PolicyRequest(method="GET", path="/api/health", query={"mode": "trace"}, headers={}, variables={})
    early = apply_inbound([doc], req)
    assert early is not None
    assert early.status_code == 200
    assert early.body == b'{"mode":"trace"}'


def test_golden_policy_include_fragment_inserts_fragment_nodes() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <include-fragment fragment-id="common-header" />
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
""",
        policy_fragments={
            "common-header": """
<fragment>
  <set-header name="x-fragment" exists-action="override"><value>1</value></set-header>
</fragment>
"""
        },
    )
    req = PolicyRequest(method="GET", path="/api/health", query={}, headers={}, variables={})
    early = apply_inbound([doc], req)
    assert early is None
    assert req.headers["x-fragment"] == "1"


def test_golden_policy_named_values_resolve_before_template_tokens() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <set-header name="x-backend" exists-action="override"><value>https://{{backend-host}}{path}</value></set-header>
  </inbound>
  <backend />
  <outbound />
  <on-error />
</policies>
"""
    )
    req = PolicyRequest(method="GET", path="/api/health", query={}, headers={}, variables={})
    runtime = PolicyRuntime(
        gateway_config=GatewayConfig(named_values={"backend-host": NamedValueConfig(value="backend.example.test")})
    )

    early = apply_inbound([doc], req, runtime=runtime)

    assert early is None
    assert req.headers["x-backend"] == "https://backend.example.test/api/health"


def test_golden_policy_parses_policy_parity_v2_nodes() -> None:
    doc = parse_policies_xml(
        """\
<policies>
  <inbound>
    <rate-limit-by-key calls="10" renewal-period="60" counter-key="user-a" />
    <quota-by-key calls="100" renewal-period="300" counter-key="user-a" first-period-start="2026-04-02T10:00:00Z" />
    <cache-lookup vary-by-developer="true" vary-by-developer-groups="false" caching-type="internal">
      <vary-by-query-parameter>version;locale</vary-by-query-parameter>
    </cache-lookup>
    <cache-lookup-value key="token-user-a" variable-name="tokenstate" default-value="missing" />
    <cache-remove-value key="token-user-a" />
  </inbound>
  <backend />
  <outbound>
    <cache-store duration="60" />
    <cache-store-value key="token-user-a" value="warm" duration="60" />
  </outbound>
  <on-error />
</policies>
"""
    )

    assert isinstance(doc.inbound[0], RateLimitByKey)
    assert isinstance(doc.inbound[1], QuotaByKey)
    assert isinstance(doc.inbound[2], CacheLookup)
    assert isinstance(doc.inbound[3], CacheLookupValue)
    assert isinstance(doc.inbound[4], CacheRemoveValue)
    assert isinstance(doc.outbound[0], CacheStore)
    assert isinstance(doc.outbound[1], CacheStoreValue)
