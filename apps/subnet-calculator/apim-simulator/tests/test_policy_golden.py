from __future__ import annotations

from app.policy import PolicyRequest, apply_inbound, apply_on_error, apply_outbound, parse_policies_xml


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
