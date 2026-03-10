from __future__ import annotations

import ipaddress
import time
from dataclasses import dataclass
from typing import Any
from xml.etree import ElementTree

from fastapi import HTTPException


@dataclass(frozen=True)
class ResponseSpec:
    status_code: int
    headers: dict[str, str]
    body: bytes = b""
    media_type: str | None = None


@dataclass
class PolicyRequest:
    method: str
    path: str
    query: dict[str, str]
    headers: dict[str, str]
    variables: dict[str, Any]


class Condition:
    def __call__(self, req: PolicyRequest) -> bool:  # pragma: no cover
        raise NotImplementedError


@dataclass(frozen=True)
class Always(Condition):
    def __call__(self, req: PolicyRequest) -> bool:
        return True


@dataclass(frozen=True)
class HeaderEquals(Condition):
    name: str
    value: str

    def __call__(self, req: PolicyRequest) -> bool:
        return req.headers.get(self.name.lower(), "") == self.value


@dataclass(frozen=True)
class HeaderStartsWith(Condition):
    name: str
    prefix: str

    def __call__(self, req: PolicyRequest) -> bool:
        return req.headers.get(self.name.lower(), "").startswith(self.prefix)


@dataclass(frozen=True)
class QueryEquals(Condition):
    name: str
    value: str

    def __call__(self, req: PolicyRequest) -> bool:
        return req.query.get(self.name, "") == self.value


@dataclass(frozen=True)
class MethodIs(Condition):
    method: str

    def __call__(self, req: PolicyRequest) -> bool:
        return req.method.upper() == self.method.upper()


@dataclass(frozen=True)
class PathStartsWith(Condition):
    prefix: str

    def __call__(self, req: PolicyRequest) -> bool:
        return req.path.startswith(self.prefix)


def parse_condition(expr: str | None) -> Condition:
    if not expr:
        return Always()

    # Supported mini-grammar (intentionally NOT APIM expression language):
    # - header('X') == 'Y'
    # - header('X').startswith('Y')
    # - query('x') == 'y'
    # - method == 'GET'
    # - path.startswith('/api')
    expr = expr.strip()

    def _strip_quotes(v: str) -> str:
        v = v.strip()
        if (v.startswith("'") and v.endswith("'")) or (v.startswith('"') and v.endswith('"')):
            return v[1:-1]
        return v

    if expr.startswith("header(") and ").startswith(" in expr:
        name = _strip_quotes(expr.split("header(", 1)[1].split(")", 1)[0]).lower()
        prefix = _strip_quotes(expr.split(".startswith(", 1)[1].rsplit(")", 1)[0])
        return HeaderStartsWith(name=name, prefix=prefix)

    if expr.startswith("header(") and "==" in expr:
        left, right = expr.split("==", 1)
        name = _strip_quotes(left.split("header(", 1)[1].split(")", 1)[0]).lower()
        value = _strip_quotes(right)
        return HeaderEquals(name=name, value=value)

    if expr.startswith("query(") and "==" in expr:
        left, right = expr.split("==", 1)
        name = _strip_quotes(left.split("query(", 1)[1].split(")", 1)[0])
        value = _strip_quotes(right)
        return QueryEquals(name=name, value=value)

    if expr.startswith("method") and "==" in expr:
        _, right = expr.split("==", 1)
        return MethodIs(method=_strip_quotes(right))

    if expr.startswith("path.startswith("):
        prefix = _strip_quotes(expr.split("path.startswith(", 1)[1].rsplit(")", 1)[0])
        return PathStartsWith(prefix=prefix)

    raise HTTPException(status_code=500, detail=f"Unsupported policy condition: {expr}")


class PolicyNode:
    def apply(self, req: PolicyRequest) -> ResponseSpec | None:  # pragma: no cover
        raise NotImplementedError


@dataclass(frozen=True)
class NoOp(PolicyNode):
    def apply(self, req: PolicyRequest) -> ResponseSpec | None:
        return None


@dataclass(frozen=True)
class SetHeader(PolicyNode):
    name: str
    value: str
    exists_action: str = "override"

    def apply(self, req: PolicyRequest) -> ResponseSpec | None:
        key = self.name
        action = (self.exists_action or "override").lower()
        if action == "delete":
            req.headers.pop(key, None)
            return None

        if action == "skip" and key in req.headers:
            return None

        if action == "append" and key in req.headers:
            req.headers[key] = f"{req.headers[key]},{self.value}"
            return None

        req.headers[key] = self.value
        return None


@dataclass(frozen=True)
class RewriteUri(PolicyNode):
    template: str

    def apply(self, req: PolicyRequest) -> ResponseSpec | None:
        # Minimal template expansion.
        # Supported placeholder: {path}
        try:
            req.path = self.template.format_map({"path": req.path})
        except Exception:
            req.path = self.template
        return None


@dataclass(frozen=True)
class ReturnResponse(PolicyNode):
    status_code: int
    reason: str | None = None
    headers: dict[str, str] | None = None
    body: str | None = None
    media_type: str | None = None

    def apply(self, req: PolicyRequest) -> ResponseSpec | None:
        out_headers = dict(self.headers or {})
        return ResponseSpec(
            status_code=self.status_code,
            headers=out_headers,
            body=(self.body or "").encode("utf-8"),
            media_type=self.media_type,
        )


@dataclass(frozen=True)
class Choose(PolicyNode):
    branches: list[tuple[Condition, list[PolicyNode]]]
    otherwise: list[PolicyNode]

    def apply(self, req: PolicyRequest) -> ResponseSpec | None:
        for cond, steps in self.branches:
            if cond(req):
                return _apply_steps(steps, req)
        return _apply_steps(self.otherwise, req)


@dataclass(frozen=True)
class PolicyDocument:
    inbound: list[PolicyNode]
    backend: list[PolicyNode]
    outbound: list[PolicyNode]
    on_error: list[PolicyNode]


def _text_or_empty(el: ElementTree.Element | None) -> str:
    if el is None or el.text is None:
        return ""
    return el.text.strip()


def _parse_set_header(el: ElementTree.Element) -> SetHeader:
    name = el.attrib.get("name")
    if not name:
        raise HTTPException(status_code=500, detail="set-header missing name")
    name = name.lower()
    exists_action = el.attrib.get("exists-action", "override")
    value_el = el.find("value")
    value = _text_or_empty(value_el)
    return SetHeader(name=name, value=value, exists_action=exists_action)


def _parse_rewrite_uri(el: ElementTree.Element) -> RewriteUri:
    template = el.attrib.get("template")
    if not template:
        raise HTTPException(status_code=500, detail="rewrite-uri missing template")
    return RewriteUri(template=template)


@dataclass(frozen=True)
class CheckHeader(PolicyNode):
    name: str
    expected: str | None
    status_code: int
    message: str

    def apply(self, req: PolicyRequest) -> ResponseSpec | None:
        actual = req.headers.get(self.name.lower())
        if actual is None:
            return ResponseSpec(
                status_code=self.status_code,
                headers={"content-type": "text/plain"},
                body=self.message.encode("utf-8"),
            )
        if self.expected is not None and actual != self.expected:
            return ResponseSpec(
                status_code=self.status_code,
                headers={"content-type": "text/plain"},
                body=self.message.encode("utf-8"),
            )
        return None


@dataclass(frozen=True)
class IpFilter(PolicyNode):
    action: str
    allow: set[str]

    def apply(self, req: PolicyRequest) -> ResponseSpec | None:
        ip_raw = req.variables.get("client_ip")
        if not isinstance(ip_raw, str) or not ip_raw:
            return None

        try:
            ip = ipaddress.ip_address(ip_raw)
        except ValueError:
            return None

        allowed = False
        for entry in self.allow:
            try:
                if "/" in entry:
                    if ip in ipaddress.ip_network(entry, strict=False):
                        allowed = True
                        break
                else:
                    if ip == ipaddress.ip_address(entry):
                        allowed = True
                        break
            except ValueError:
                continue

        action = (self.action or "allow").lower()
        if action == "allow" and not allowed:
            return ResponseSpec(status_code=403, headers={"content-type": "text/plain"}, body=b"IP not allowed")
        if action == "forbid" and allowed:
            return ResponseSpec(status_code=403, headers={"content-type": "text/plain"}, body=b"IP not allowed")
        return None


@dataclass(frozen=True)
class Cors(PolicyNode):
    def apply(self, req: PolicyRequest) -> ResponseSpec | None:
        # Simulator no-op: FastAPI CORS middleware handles CORS in most stacks.
        # We still parse the policy to avoid hard failures when configs include it.
        return None


@dataclass(frozen=True)
class RateLimit(PolicyNode):
    calls: int
    renewal_period: int
    scope: str = "subscription"

    def apply(self, req: PolicyRequest) -> ResponseSpec | None:
        store = req.variables.get("rate_limit_store")
        if not isinstance(store, dict):
            return None

        key = _rate_limit_key(req, scope=self.scope)
        now = int(time.time())
        window = now - (now % self.renewal_period)
        count = 0
        if isinstance(store.get(key), dict):
            entry = store[key]
            if entry.get("window") == window:
                count = int(entry.get("count") or 0)
        count += 1
        store[key] = {"window": window, "count": count}

        remaining = max(0, self.calls - count)
        headers = {
            "content-type": "text/plain",
            "x-ratelimit-limit": str(self.calls),
            "x-ratelimit-remaining": str(remaining),
            "x-ratelimit-reset": str(window + self.renewal_period),
        }
        if count > self.calls:
            return ResponseSpec(status_code=429, headers=headers, body=b"Rate limit exceeded")
        return None


@dataclass(frozen=True)
class Quota(PolicyNode):
    calls: int
    renewal_period: int
    scope: str = "subscription"

    def apply(self, req: PolicyRequest) -> ResponseSpec | None:
        store = req.variables.get("quota_store")
        if not isinstance(store, dict):
            # Back-compat: allow using the same store as rate limit.
            store = req.variables.get("rate_limit_store")
        if not isinstance(store, dict):
            return None

        key = f"quota:{_rate_limit_key(req, scope=self.scope)}"
        now = int(time.time())
        window = now - (now % self.renewal_period)
        count = 0
        if isinstance(store.get(key), dict):
            entry = store[key]
            if entry.get("window") == window:
                count = int(entry.get("count") or 0)
        count += 1
        store[key] = {"window": window, "count": count}

        remaining = max(0, self.calls - count)
        headers = {
            "content-type": "text/plain",
            "x-quota-limit": str(self.calls),
            "x-quota-remaining": str(remaining),
            "x-quota-reset": str(window + self.renewal_period),
        }
        if count > self.calls:
            return ResponseSpec(status_code=429, headers=headers, body=b"Quota exceeded")
        return None


def _parse_return_response(el: ElementTree.Element) -> ReturnResponse:
    status_el = el.find("set-status")
    if status_el is None:
        raise HTTPException(status_code=500, detail="return-response missing set-status")
    code = int(status_el.attrib.get("code") or "200")
    reason = status_el.attrib.get("reason")

    headers: dict[str, str] = {}
    for h in el.findall("set-header"):
        sh = _parse_set_header(h)
        # For a return-response we treat headers as simple set operations.
        headers[sh.name] = sh.value

    body_el = el.find("body")
    body = _text_or_empty(body_el) if body_el is not None else None
    return ReturnResponse(status_code=code, reason=reason, headers=headers, body=body)


def _parse_check_header(el: ElementTree.Element) -> CheckHeader:
    name = (el.attrib.get("name") or "").strip().lower()
    if not name:
        raise HTTPException(status_code=500, detail="check-header missing name")

    expected = el.attrib.get("value")
    status_code = int(el.attrib.get("failed-check-httpcode") or "401")
    message = str(el.attrib.get("failed-check-error-message") or "Missing or invalid header")
    return CheckHeader(name=name, expected=expected, status_code=status_code, message=message)


def _parse_ip_filter(el: ElementTree.Element) -> IpFilter:
    action = str(el.attrib.get("action") or "allow")
    allow: set[str] = set()

    for addr in el.findall("address"):
        v = _text_or_empty(addr)
        if v:
            allow.add(v)

    for cidr in el.findall("cidr"):
        v = _text_or_empty(cidr)
        if v:
            allow.add(v)

    # Support a tiny subset of the APIM shape.
    for ar in el.findall("address-range"):
        frm = (ar.attrib.get("from") or "").strip()
        to = (ar.attrib.get("to") or "").strip()
        if frm and to and frm == to:
            allow.add(frm)

    return IpFilter(action=action, allow=allow)


def _parse_rate_limit(el: ElementTree.Element) -> RateLimit:
    calls = int(el.attrib.get("calls") or "0")
    renewal = int(el.attrib.get("renewal-period") or el.attrib.get("renewal_period") or "60")
    scope = str(el.attrib.get("scope") or "subscription")
    if calls <= 0:
        raise HTTPException(status_code=500, detail="rate-limit requires calls > 0")
    return RateLimit(calls=calls, renewal_period=renewal, scope=scope)


def _parse_quota(el: ElementTree.Element) -> Quota:
    calls = int(el.attrib.get("calls") or "0")
    renewal = int(el.attrib.get("renewal-period") or el.attrib.get("renewal_period") or "3600")
    scope = str(el.attrib.get("scope") or "subscription")
    if calls <= 0:
        raise HTTPException(status_code=500, detail="quota requires calls > 0")
    return Quota(calls=calls, renewal_period=renewal, scope=scope)


def _rate_limit_key(req: PolicyRequest, *, scope: str) -> str:
    scope = (scope or "subscription").lower()
    route = str(req.variables.get("route") or "")
    subscription_id = str(req.variables.get("subscription_id") or "")
    products = req.variables.get("products")
    product_part = ",".join(sorted(str(p) for p in products)) if isinstance(products, list) else ""
    client_ip = str(req.variables.get("client_ip") or "")

    if scope == "subscription":
        return f"sub:{subscription_id}|route:{route}|products:{product_part}"
    if scope == "product":
        return f"product:{product_part}|sub:{subscription_id}|route:{route}"
    if scope == "ip":
        return f"ip:{client_ip}|route:{route}"
    return f"route:{route}|sub:{subscription_id}|products:{product_part}"


def _parse_choose(el: ElementTree.Element) -> Choose:
    branches: list[tuple[Condition, list[PolicyNode]]] = []
    for when in el.findall("when"):
        cond = parse_condition(when.attrib.get("condition"))
        steps = [_parse_node(child) for child in list(when)]
        branches.append((cond, steps))
    otherwise_el = el.find("otherwise")
    otherwise_steps = [_parse_node(child) for child in list(otherwise_el)] if otherwise_el is not None else []
    return Choose(branches=branches, otherwise=otherwise_steps)


def _parse_node(el: ElementTree.Element) -> PolicyNode:
    tag = el.tag

    if tag == "base":
        return NoOp()

    if tag == "set-header":
        return _parse_set_header(el)

    if tag == "rewrite-uri":
        return _parse_rewrite_uri(el)

    if tag == "check-header":
        return _parse_check_header(el)

    if tag == "ip-filter":
        return _parse_ip_filter(el)

    if tag == "cors":
        return Cors()

    if tag == "rate-limit":
        return _parse_rate_limit(el)

    if tag == "quota":
        return _parse_quota(el)

    if tag == "return-response":
        return _parse_return_response(el)

    if tag == "choose":
        return _parse_choose(el)

    raise HTTPException(status_code=500, detail=f"Unsupported policy element: {tag}")


def parse_policies_xml(xml: str) -> PolicyDocument:
    try:
        root = ElementTree.fromstring(xml)
    except ElementTree.ParseError as exc:
        raise HTTPException(status_code=500, detail="Invalid policies XML") from exc

    if root.tag != "policies":
        raise HTTPException(status_code=500, detail="Policies XML must have <policies> root")

    def section(name: str) -> list[PolicyNode]:
        sec = root.find(name)
        if sec is None:
            return []
        return [_parse_node(child) for child in list(sec)]

    return PolicyDocument(
        inbound=section("inbound"),
        backend=section("backend"),
        outbound=section("outbound"),
        on_error=section("on-error"),
    )


def _apply_steps(steps: list[PolicyNode], req: PolicyRequest) -> ResponseSpec | None:
    for step in steps:
        out = step.apply(req)
        if out is not None:
            return out
    return None


def apply_inbound(docs: list[PolicyDocument], req: PolicyRequest) -> ResponseSpec | None:
    for doc in docs:
        out = _apply_steps(doc.inbound, req)
        if out is not None:
            return out
    return None


def apply_outbound(docs: list[PolicyDocument], *, headers: dict[str, str]) -> None:
    # Outbound support is currently limited to set-header.
    dummy = PolicyRequest(method="GET", path="/", query={}, headers=headers, variables={})
    for doc in docs:
        _apply_steps(doc.outbound, dummy)


def apply_on_error(docs: list[PolicyDocument], req: PolicyRequest) -> ResponseSpec | None:
    for doc in docs:
        out = _apply_steps(doc.on_error, req)
        if out is not None:
            return out
    return None
