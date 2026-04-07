from __future__ import annotations

import asyncio
import ipaddress
import json
import re
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from xml.etree import ElementTree

import httpx
import jwt
from fastapi import HTTPException
from jwt.algorithms import RSAAlgorithm

from app.apim_expr import (
    CalloutResponse,
    JwtValue,
    build_expression_context,
    evaluate_apim_expression,
    is_apim_expression,
)
from app.config import GatewayConfig
from app.named_values import mask_secret_data, resolve_named_values_in_text


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
    body: bytes = b""
    response_status_code: int | None = None
    response_headers: dict[str, str] | None = None
    response_body: bytes = b""
    response_media_type: str | None = None


@dataclass
class PolicyTraceCollector:
    steps: list[dict[str, Any]] = field(default_factory=list)
    variable_writes: list[dict[str, Any]] = field(default_factory=list)
    jwt_validations: list[dict[str, Any]] = field(default_factory=list)
    send_requests: list[dict[str, Any]] = field(default_factory=list)
    selected_backend: dict[str, Any] | None = None


@dataclass
class PolicyRuntime:
    gateway_config: GatewayConfig | None = None
    http_client: httpx.AsyncClient | None = None
    timeout_seconds: float = 30.0
    trace: PolicyTraceCollector | None = None
    openid_cache: dict[str, tuple[dict[str, Any], dict[str, Any]]] = field(default_factory=dict)
    response_cache: dict[str, Any] = field(default_factory=dict)
    value_cache: dict[str, Any] = field(default_factory=dict)
    deferred_actions: list[Any] = field(default_factory=list)


@dataclass(frozen=True)
class ResponseCacheEntry:
    expires_at: float
    status_code: int
    headers: dict[str, str]
    body: bytes
    media_type: str | None = None


@dataclass(frozen=True)
class ValueCacheEntry:
    expires_at: float
    value: Any


@dataclass(frozen=True)
class ResponseCachePolicyContext:
    cache_key: str
    downstream_caching_type: str
    must_revalidate: bool
    allow_private_response_caching: bool


class DeferredPolicyAction:
    def finalize(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> None:  # pragma: no cover
        raise NotImplementedError


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


@dataclass(frozen=True)
class ExpressionCondition(Condition):
    expression: str

    def __call__(self, req: PolicyRequest) -> bool:
        return bool(evaluate_apim_expression(self.expression, build_expression_context(req)))


def parse_condition(expr: str | None) -> Condition:
    if not expr:
        return Always()

    expr = expr.strip()
    if expr.startswith("@"):
        return ExpressionCondition(expression=expr)

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
    def apply(
        self, req: PolicyRequest, runtime: PolicyRuntime | None = None
    ) -> ResponseSpec | None:  # pragma: no cover
        raise NotImplementedError

    async def apply_async(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        return self.apply(req, runtime)


@dataclass(frozen=True)
class NoOp(PolicyNode):
    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        return None


@dataclass(frozen=True)
class SetHeader(PolicyNode):
    name: str
    value: str
    exists_action: str = "override"

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        key = self.name
        action = (self.exists_action or "override").lower()
        rendered = render_policy_value(self.value, req, runtime)
        if action == "delete":
            req.headers.pop(key, None)
            _record_step(runtime, "set-header", {"name": key, "action": "delete"})
            return None

        if action == "skip" and key in req.headers:
            _record_step(runtime, "set-header", {"name": key, "action": "skip"})
            return None

        if action == "append" and key in req.headers:
            req.headers[key] = f"{req.headers[key]},{rendered}"
        else:
            req.headers[key] = rendered

        _record_step(runtime, "set-header", {"name": key, "action": action, "value": rendered})
        return None


@dataclass(frozen=True)
class RewriteUri(PolicyNode):
    template: str

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        req.path = render_policy_value(self.template, req, runtime)
        _record_step(runtime, "rewrite-uri", {"path": req.path})
        return None


@dataclass(frozen=True)
class SetVariable(PolicyNode):
    name: str
    value: str

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        rendered = evaluate_policy_value(self.value, req, runtime)
        req.variables[self.name] = rendered
        _record_variable_write(runtime, self.name, rendered, "set-variable")
        return None


@dataclass(frozen=True)
class SetQueryParameter(PolicyNode):
    name: str
    value: str
    exists_action: str = "override"

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        key = self.name
        action = (self.exists_action or "override").lower()
        rendered = render_policy_value(self.value, req, runtime)
        if action == "delete":
            req.query.pop(key, None)
            _record_step(runtime, "set-query-parameter", {"name": key, "action": "delete"})
            return None

        if action == "skip" and key in req.query:
            _record_step(runtime, "set-query-parameter", {"name": key, "action": "skip"})
            return None

        if action == "append" and key in req.query:
            req.query[key] = f"{req.query[key]},{rendered}"
        else:
            req.query[key] = rendered

        _record_step(runtime, "set-query-parameter", {"name": key, "action": action, "value": rendered})
        return None


@dataclass(frozen=True)
class SetBody(PolicyNode):
    value: str

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        req.body = render_policy_value(self.value, req, runtime).encode("utf-8")
        _record_step(runtime, "set-body", {"length": len(req.body)})
        return None


@dataclass(frozen=True)
class ReturnResponse(PolicyNode):
    status_code: int
    reason: str | None = None
    headers: list[SetHeader] = field(default_factory=list)
    body: str | None = None
    media_type: str | None = None

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        out_headers: dict[str, str] = {}
        temp_req = PolicyRequest(
            method=req.method,
            path=req.path,
            query=dict(req.query),
            headers=out_headers,
            variables=req.variables,
            body=req.body,
        )
        for header in self.headers:
            header.apply(temp_req, runtime)

        body = render_policy_value(self.body or "", req, runtime)
        _record_step(runtime, "return-response", {"status_code": self.status_code})
        return ResponseSpec(
            status_code=self.status_code,
            headers=out_headers,
            body=body.encode("utf-8"),
            media_type=self.media_type or out_headers.get("content-type"),
        )


@dataclass(frozen=True)
class Choose(PolicyNode):
    branches: list[tuple[Condition, list[PolicyNode]]]
    otherwise: list[PolicyNode]

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        raise RuntimeError("Choose must be executed through apply_async")

    async def apply_async(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        for cond, steps in self.branches:
            if cond(req):
                _record_step(runtime, "choose", {"branch": "when"})
                return await _apply_steps_async(steps, req, runtime)
        _record_step(runtime, "choose", {"branch": "otherwise"})
        return await _apply_steps_async(self.otherwise, req, runtime)


@dataclass(frozen=True)
class CheckHeader(PolicyNode):
    name: str
    expected: str | None
    status_code: int
    message: str

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        actual = req.headers.get(self.name.lower())
        if actual is None or (self.expected is not None and actual != self.expected):
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

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
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
                elif ip == ipaddress.ip_address(entry):
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
    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        return None


@dataclass(frozen=True)
class RateLimit(PolicyNode):
    calls: int
    renewal_period: int
    scope: str = "subscription"

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
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

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        store = req.variables.get("quota_store")
        if not isinstance(store, dict):
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


def _request_headers(req: PolicyRequest) -> dict[str, str]:
    headers = req.variables.get("_request_headers")
    return headers if isinstance(headers, dict) else req.headers


def _request_query(req: PolicyRequest) -> dict[str, str]:
    query = req.variables.get("_request_query")
    return query if isinstance(query, dict) else req.query


def _response_header_target(req: PolicyRequest) -> dict[str, str]:
    if req.response_headers is not None:
        return req.response_headers
    return req.headers


def _pending_response_headers(req: PolicyRequest) -> dict[str, str]:
    pending = req.variables.get("_pending_response_headers")
    if isinstance(pending, dict):
        return pending
    pending = {}
    req.variables["_pending_response_headers"] = pending
    return pending


def _queue_response_header(req: PolicyRequest, name: str, value: Any) -> None:
    _pending_response_headers(req)[name.lower()] = _stringify_policy_value(value)


def apply_pending_response_headers(req: PolicyRequest, headers: dict[str, str]) -> None:
    pending = req.variables.get("_pending_response_headers")
    if not isinstance(pending, dict):
        return
    for name, value in pending.items():
        headers[name.lower()] = str(value)


def _policy_bool(
    value: str | None,
    req: PolicyRequest,
    runtime: PolicyRuntime | None = None,
    *,
    default: bool = False,
) -> bool:
    if value is None:
        return default
    resolved = evaluate_policy_value(value, req, runtime)
    if isinstance(resolved, bool):
        return resolved
    text = _stringify_policy_value(resolved).strip().lower()
    if text in {"true", "1", "yes"}:
        return True
    if text in {"false", "0", "no", ""}:
        return False
    return default


def _policy_int(
    value: str | None,
    req: PolicyRequest,
    runtime: PolicyRuntime | None = None,
    *,
    default: int = 0,
) -> int:
    if value is None:
        return default
    resolved = evaluate_policy_value(value, req, runtime)
    if isinstance(resolved, bool):
        return int(resolved)
    if isinstance(resolved, (int, float)):
        return int(resolved)
    text = _stringify_policy_value(resolved).strip()
    if not text:
        return default
    return int(float(text))


def _is_deferred_expression(value: str | None) -> bool:
    return value is not None and is_apim_expression(value)


def _normalize_cache_caching_type(caching_type: str | None) -> tuple[str, bool]:
    normalized = (caching_type or "prefer-external").strip().lower() or "prefer-external"
    if normalized == "external":
        raise HTTPException(status_code=500, detail="Unsupported caching-type external")
    if normalized == "prefer-external":
        return "internal", True
    return "internal", False


def _cleanup_value_cache(store: dict[str, Any], key: str, now: float) -> ValueCacheEntry | None:
    entry = store.get(key)
    if not isinstance(entry, ValueCacheEntry):
        return None
    if entry.expires_at < now:
        store.pop(key, None)
        return None
    return entry


def _vary_values(values: list[str]) -> list[str]:
    out: list[str] = []
    for item in values:
        for part in item.split(";"):
            value = part.strip()
            if value:
                out.append(value)
    return out


def _build_response_cache_key(
    req: PolicyRequest,
    *,
    vary_by_headers: list[str],
    vary_by_query_parameters: list[str],
    vary_by_developer: bool,
    vary_by_developer_groups: bool,
) -> str:
    request_headers = _request_headers(req)
    request_query = _request_query(req)
    query_names = vary_by_query_parameters or sorted(request_query.keys())
    query_part = {name: request_query.get(name, "") for name in query_names}
    header_part = {name.lower(): request_headers.get(name.lower(), "") for name in vary_by_headers}
    developer = str(req.variables.get("subscription_id") or "anonymous") if vary_by_developer else ""
    groups = req.variables.get("subscription_groups")
    group_part = sorted(str(item) for item in groups) if vary_by_developer_groups and isinstance(groups, list) else []
    return json.dumps(
        {
            "route": str(req.variables.get("route") or ""),
            "method": req.method.upper(),
            "path": req.path,
            "query": query_part,
            "headers": header_part,
            "developer": developer,
            "groups": group_part,
        },
        sort_keys=True,
        separators=(",", ":"),
    )


def _apply_downstream_cache_headers(
    headers: dict[str, str],
    *,
    downstream_caching_type: str,
    must_revalidate: bool,
) -> None:
    mode = (downstream_caching_type or "none").strip().lower()
    if mode == "none":
        headers["cache-control"] = "no-store"
        return
    directives = [mode]
    if must_revalidate:
        directives.append("must-revalidate")
    headers["cache-control"] = ", ".join(directives)


def _rate_limit_bucket(store: dict[str, Any], key: str) -> list[float]:
    bucket = store.get(key)
    if not isinstance(bucket, list):
        bucket = []
        store[key] = bucket
    return bucket


def _prune_rate_limit_bucket(bucket: list[float], now: float, renewal_period: int) -> None:
    threshold = now - renewal_period
    while bucket and bucket[0] <= threshold:
        bucket.pop(0)


def _rate_limit_retry_after(bucket: list[float], now: float, renewal_period: int) -> int:
    if not bucket:
        return renewal_period
    earliest = bucket[0]
    return max(1, int((earliest + renewal_period) - now))


def _quota_window_state(
    store: dict[str, Any],
    key: str,
    *,
    now: float,
    renewal_period: int,
    first_period_start: str | None,
) -> tuple[dict[str, Any], int | None]:
    if renewal_period == 0:
        entry = store.get(key)
        if not isinstance(entry, dict):
            entry = {"window_start": None, "count": 0}
            store[key] = entry
        return entry, None

    if renewal_period < 0:
        raise HTTPException(status_code=500, detail="quota-by-key renewal-period must be >= 0")

    if first_period_start and first_period_start != "0001-01-01T00:00:00Z":
        anchor = datetime.strptime(first_period_start, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC).timestamp()
    else:
        anchor = 0.0

    if now < anchor:
        window_start = anchor
    else:
        window_index = int((now - anchor) // renewal_period)
        window_start = anchor + (window_index * renewal_period)

    entry = store.get(key)
    if not isinstance(entry, dict) or entry.get("window_start") != window_start:
        entry = {"window_start": window_start, "count": 0}
        store[key] = entry

    reset_at = int(window_start + renewal_period)
    return entry, reset_at


@dataclass(frozen=True)
class RateLimitByKeyDeferred(DeferredPolicyAction):
    calls: str
    renewal_period: str
    counter_key: str
    increment_condition: str | None
    increment_count: str | None
    retry_after_header_name: str | None
    retry_after_variable_name: str | None
    remaining_calls_header_name: str | None
    remaining_calls_variable_name: str | None
    total_calls_header_name: str | None

    def finalize(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> None:
        store = req.variables.get("rate_limit_store")
        if not isinstance(store, dict):
            return
        calls = max(1, _policy_int(self.calls, req, runtime, default=1))
        renewal_period = max(1, _policy_int(self.renewal_period, req, runtime, default=60))
        counter_key = render_policy_value(self.counter_key, req, runtime)
        if not counter_key:
            return
        now = time.time()
        bucket = _rate_limit_bucket(store, f"rate-limit-by-key:{counter_key}")
        _prune_rate_limit_bucket(bucket, now, renewal_period)
        should_increment = _policy_bool(self.increment_condition, req, runtime, default=True)
        increment = max(0, _policy_int(self.increment_count, req, runtime, default=1))
        if should_increment and increment:
            bucket.extend([now] * increment)
        remaining = max(0, calls - len(bucket))
        if self.remaining_calls_variable_name:
            req.variables[self.remaining_calls_variable_name] = remaining
            _record_variable_write(runtime, self.remaining_calls_variable_name, remaining, "rate-limit-by-key")
        if self.remaining_calls_header_name:
            _response_header_target(req)[self.remaining_calls_header_name.lower()] = str(remaining)
        if self.total_calls_header_name:
            _response_header_target(req)[self.total_calls_header_name.lower()] = str(calls)
        _record_step(
            runtime,
            "rate-limit-by-key",
            {
                "counter_key": counter_key,
                "deferred": True,
                "count": len(bucket),
                "remaining": remaining,
            },
        )


@dataclass(frozen=True)
class QuotaByKeyDeferred(DeferredPolicyAction):
    calls: str
    renewal_period: str
    counter_key: str
    increment_condition: str | None
    increment_count: str | None
    first_period_start: str | None

    def finalize(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> None:
        store = req.variables.get("quota_store")
        if not isinstance(store, dict):
            return
        renewal_period = _policy_int(self.renewal_period, req, runtime, default=3600)
        counter_key = render_policy_value(self.counter_key, req, runtime)
        if not counter_key:
            return
        now = time.time()
        entry, _ = _quota_window_state(
            store,
            f"quota-by-key:{counter_key}",
            now=now,
            renewal_period=renewal_period,
            first_period_start=self.first_period_start,
        )
        should_increment = _policy_bool(self.increment_condition, req, runtime, default=True)
        increment = max(0, _policy_int(self.increment_count, req, runtime, default=1))
        if should_increment and increment:
            entry["count"] = int(entry.get("count") or 0) + increment
        _record_step(
            runtime,
            "quota-by-key",
            {
                "counter_key": counter_key,
                "deferred": True,
                "count": int(entry.get("count") or 0),
            },
        )


@dataclass(frozen=True)
class RateLimitByKey(PolicyNode):
    calls: str
    renewal_period: str
    counter_key: str
    increment_condition: str | None = None
    increment_count: str | None = None
    retry_after_header_name: str | None = None
    retry_after_variable_name: str | None = None
    remaining_calls_header_name: str | None = None
    remaining_calls_variable_name: str | None = None
    total_calls_header_name: str | None = None

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        store = req.variables.get("rate_limit_store")
        if not isinstance(store, dict):
            return None
        calls = max(1, _policy_int(self.calls, req, runtime, default=1))
        renewal_period = max(1, _policy_int(self.renewal_period, req, runtime, default=60))
        counter_key = render_policy_value(self.counter_key, req, runtime)
        if not counter_key:
            raise HTTPException(status_code=500, detail="rate-limit-by-key requires counter-key")
        now = time.time()
        bucket = _rate_limit_bucket(store, f"rate-limit-by-key:{counter_key}")
        _prune_rate_limit_bucket(bucket, now, renewal_period)

        if _is_deferred_expression(self.increment_condition) or _is_deferred_expression(self.increment_count):
            if len(bucket) >= calls:
                retry_after = _rate_limit_retry_after(bucket, now, renewal_period)
                return self._limit_response(
                    req,
                    runtime,
                    calls=calls,
                    retry_after=retry_after,
                    remaining=0,
                )
            if runtime is not None:
                runtime.deferred_actions.append(
                    RateLimitByKeyDeferred(
                        calls=self.calls,
                        renewal_period=self.renewal_period,
                        counter_key=self.counter_key,
                        increment_condition=self.increment_condition,
                        increment_count=self.increment_count,
                        retry_after_header_name=self.retry_after_header_name,
                        retry_after_variable_name=self.retry_after_variable_name,
                        remaining_calls_header_name=self.remaining_calls_header_name,
                        remaining_calls_variable_name=self.remaining_calls_variable_name,
                        total_calls_header_name=self.total_calls_header_name,
                    )
                )
            _record_step(
                runtime,
                "rate-limit-by-key",
                {
                    "counter_key": counter_key,
                    "deferred": True,
                    "count": len(bucket),
                    "remaining": max(0, calls - len(bucket)),
                },
            )
            return None

        should_increment = _policy_bool(self.increment_condition, req, runtime, default=True)
        increment = max(0, _policy_int(self.increment_count, req, runtime, default=1))
        if should_increment and increment:
            bucket.extend([now] * increment)
        remaining = max(0, calls - len(bucket))
        if self.remaining_calls_variable_name:
            req.variables[self.remaining_calls_variable_name] = remaining
            _record_variable_write(runtime, self.remaining_calls_variable_name, remaining, "rate-limit-by-key")
        if self.remaining_calls_header_name:
            _queue_response_header(req, self.remaining_calls_header_name, remaining)
        if self.total_calls_header_name:
            _queue_response_header(req, self.total_calls_header_name, calls)
        _record_step(
            runtime,
            "rate-limit-by-key",
            {"counter_key": counter_key, "count": len(bucket), "remaining": remaining},
        )
        if len(bucket) > calls:
            retry_after = _rate_limit_retry_after(bucket, now, renewal_period)
            return self._limit_response(
                req,
                runtime,
                calls=calls,
                retry_after=retry_after,
                remaining=remaining,
            )
        return None

    def _limit_response(
        self,
        req: PolicyRequest,
        runtime: PolicyRuntime | None,
        *,
        calls: int,
        retry_after: int,
        remaining: int,
    ) -> ResponseSpec:
        header_name = self.retry_after_header_name or "Retry-After"
        if self.retry_after_variable_name:
            req.variables[self.retry_after_variable_name] = retry_after
            _record_variable_write(runtime, self.retry_after_variable_name, retry_after, "rate-limit-by-key")
        headers = {
            "content-type": "text/plain",
            header_name.lower(): str(retry_after),
        }
        if self.remaining_calls_header_name:
            headers[self.remaining_calls_header_name.lower()] = str(remaining)
        if self.total_calls_header_name:
            headers[self.total_calls_header_name.lower()] = str(calls)
        return ResponseSpec(status_code=429, headers=headers, body=b"Rate limit exceeded")


@dataclass(frozen=True)
class QuotaByKey(PolicyNode):
    calls: str
    renewal_period: str
    counter_key: str
    increment_condition: str | None = None
    increment_count: str | None = None
    first_period_start: str | None = None

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        store = req.variables.get("quota_store")
        if not isinstance(store, dict):
            return None
        calls = max(1, _policy_int(self.calls, req, runtime, default=1))
        renewal_period = _policy_int(self.renewal_period, req, runtime, default=3600)
        counter_key = render_policy_value(self.counter_key, req, runtime)
        if not counter_key:
            raise HTTPException(status_code=500, detail="quota-by-key requires counter-key")
        now = time.time()
        entry, reset_at = _quota_window_state(
            store,
            f"quota-by-key:{counter_key}",
            now=now,
            renewal_period=renewal_period,
            first_period_start=self.first_period_start,
        )
        current = int(entry.get("count") or 0)
        if _is_deferred_expression(self.increment_condition) or _is_deferred_expression(self.increment_count):
            if current >= calls:
                return self._quota_response(now=now, reset_at=reset_at)
            if runtime is not None:
                runtime.deferred_actions.append(
                    QuotaByKeyDeferred(
                        calls=self.calls,
                        renewal_period=self.renewal_period,
                        counter_key=self.counter_key,
                        increment_condition=self.increment_condition,
                        increment_count=self.increment_count,
                        first_period_start=self.first_period_start,
                    )
                )
            _record_step(runtime, "quota-by-key", {"counter_key": counter_key, "deferred": True, "count": current})
            return None

        should_increment = _policy_bool(self.increment_condition, req, runtime, default=True)
        increment = max(0, _policy_int(self.increment_count, req, runtime, default=1))
        if should_increment and increment:
            current += increment
            entry["count"] = current
        _record_step(runtime, "quota-by-key", {"counter_key": counter_key, "count": current})
        if current > calls:
            return self._quota_response(now=now, reset_at=reset_at)
        return None

    def _quota_response(self, *, now: float, reset_at: int | None) -> ResponseSpec:
        headers = {"content-type": "text/plain"}
        if reset_at is not None:
            headers["retry-after"] = str(max(1, reset_at - int(now)))
        return ResponseSpec(status_code=403, headers=headers, body=b"Quota exceeded")


@dataclass(frozen=True)
class CacheLookup(PolicyNode):
    vary_by_headers: list[str] = field(default_factory=list)
    vary_by_query_parameters: list[str] = field(default_factory=list)
    vary_by_developer: str = "false"
    vary_by_developer_groups: str = "false"
    downstream_caching_type: str = "none"
    must_revalidate: str = "true"
    allow_private_response_caching: str = "false"
    caching_type: str = "prefer-external"

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        if runtime is None:
            return None
        _, adapted = _normalize_cache_caching_type(self.caching_type)
        req.variables["_policy_response_cache_active"] = True
        if req.method.upper() != "GET":
            _record_step(runtime, "cache-lookup", {"status": "skipped", "reason": "method_not_get"})
            return None
        allow_private = _policy_bool(self.allow_private_response_caching, req, runtime, default=False)
        request_headers = _request_headers(req)
        if request_headers.get("authorization") and not allow_private:
            _record_step(runtime, "cache-lookup", {"status": "skipped", "reason": "private_response_caching_disabled"})
            return None
        vary_by_developer = _policy_bool(self.vary_by_developer, req, runtime, default=False)
        vary_by_developer_groups = _policy_bool(self.vary_by_developer_groups, req, runtime, default=False)
        downstream_caching_type = render_policy_value(self.downstream_caching_type or "none", req, runtime).lower()
        must_revalidate = _policy_bool(self.must_revalidate, req, runtime, default=True)
        cache_key = _build_response_cache_key(
            req,
            vary_by_headers=[item.lower() for item in self.vary_by_headers],
            vary_by_query_parameters=self.vary_by_query_parameters,
            vary_by_developer=vary_by_developer,
            vary_by_developer_groups=vary_by_developer_groups,
        )
        req.variables["_policy_response_cache_context"] = ResponseCachePolicyContext(
            cache_key=cache_key,
            downstream_caching_type=downstream_caching_type,
            must_revalidate=must_revalidate,
            allow_private_response_caching=allow_private,
        )
        entry = runtime.response_cache.get(cache_key)
        if isinstance(entry, ResponseCacheEntry):
            if entry.expires_at < time.time():
                runtime.response_cache.pop(cache_key, None)
            else:
                headers = dict(entry.headers)
                _apply_downstream_cache_headers(
                    headers,
                    downstream_caching_type=downstream_caching_type,
                    must_revalidate=must_revalidate,
                )
                _record_step(runtime, "cache-lookup", {"status": "hit", "adapted": adapted, "cache_key": cache_key})
                return ResponseSpec(
                    status_code=entry.status_code,
                    headers=headers,
                    body=entry.body,
                    media_type=entry.media_type,
                )
        _record_step(runtime, "cache-lookup", {"status": "miss", "adapted": adapted, "cache_key": cache_key})
        return None


@dataclass(frozen=True)
class CacheStore(PolicyNode):
    duration: str
    cache_response: str | None = None

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        if runtime is None:
            return None
        context = req.variables.get("_policy_response_cache_context")
        if not isinstance(context, ResponseCachePolicyContext):
            return None
        if req.method.upper() != "GET":
            _record_step(runtime, "cache-store", {"status": "skipped", "reason": "method_not_get"})
            return None
        should_store = (
            _policy_bool(self.cache_response, req, runtime, default=False)
            if self.cache_response is not None
            else req.response_status_code == 200
        )
        if not should_store:
            _record_step(runtime, "cache-store", {"status": "skipped", "reason": "response_not_cacheable"})
            return None
        ttl = max(0, _policy_int(self.duration, req, runtime, default=0))
        if ttl <= 0:
            _record_step(runtime, "cache-store", {"status": "skipped", "reason": "non_positive_ttl"})
            return None
        headers = dict(_response_header_target(req))
        _apply_downstream_cache_headers(
            headers,
            downstream_caching_type=context.downstream_caching_type,
            must_revalidate=context.must_revalidate,
        )
        runtime.response_cache[context.cache_key] = ResponseCacheEntry(
            expires_at=time.time() + ttl,
            status_code=req.response_status_code or 200,
            headers=headers,
            body=req.response_body,
            media_type=req.response_media_type,
        )
        _record_step(runtime, "cache-store", {"status": "stored", "cache_key": context.cache_key, "ttl_seconds": ttl})
        return None


@dataclass(frozen=True)
class CacheLookupValue(PolicyNode):
    key: str
    variable_name: str
    default_value: str | None = None
    caching_type: str = "prefer-external"

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        if runtime is None:
            return None
        _, adapted = _normalize_cache_caching_type(self.caching_type)
        key = render_policy_value(self.key, req, runtime)
        now = time.time()
        entry = _cleanup_value_cache(runtime.value_cache, key, now)
        if entry is not None:
            req.variables[self.variable_name] = entry.value
            _record_variable_write(runtime, self.variable_name, entry.value, "cache-lookup-value")
            _record_step(runtime, "cache-lookup-value", {"status": "hit", "cache_key": key, "adapted": adapted})
            return None
        if self.default_value is not None:
            value = evaluate_policy_value(self.default_value, req, runtime)
            req.variables[self.variable_name] = value
            _record_variable_write(runtime, self.variable_name, value, "cache-lookup-value-default")
        _record_step(runtime, "cache-lookup-value", {"status": "miss", "cache_key": key, "adapted": adapted})
        return None


@dataclass(frozen=True)
class CacheStoreValue(PolicyNode):
    key: str
    value: str
    duration: str
    caching_type: str = "prefer-external"

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        if runtime is None:
            return None
        _, adapted = _normalize_cache_caching_type(self.caching_type)
        key = render_policy_value(self.key, req, runtime)
        value = evaluate_policy_value(self.value, req, runtime)
        ttl = max(0, _policy_int(self.duration, req, runtime, default=0))
        runtime.value_cache[key] = ValueCacheEntry(expires_at=time.time() + ttl, value=value)
        _record_step(
            runtime, "cache-store-value", {"status": "stored", "cache_key": key, "ttl_seconds": ttl, "adapted": adapted}
        )
        return None


@dataclass(frozen=True)
class CacheRemoveValue(PolicyNode):
    key: str
    caching_type: str = "prefer-external"

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        if runtime is None:
            return None
        _, adapted = _normalize_cache_caching_type(self.caching_type)
        key = render_policy_value(self.key, req, runtime)
        removed = runtime.value_cache.pop(key, None) is not None
        _record_step(
            runtime,
            "cache-remove-value",
            {"status": "removed" if removed else "miss", "cache_key": key, "adapted": adapted},
        )
        return None


@dataclass(frozen=True)
class RequiredClaim:
    name: str
    values: list[str]
    match: str = "all"
    separator: str | None = None


@dataclass(frozen=True)
class ValidateJwt(PolicyNode):
    header_name: str | None
    query_parameter_name: str | None
    token_value: str | None
    failed_validation_httpcode: int = 401
    failed_validation_error_message: str = "JWT validation failed"
    require_scheme: str | None = None
    require_expiration_time: bool = True
    output_token_variable_name: str | None = None
    openid_config_urls: list[str] = field(default_factory=list)
    issuers: list[str] = field(default_factory=list)
    audiences: list[str] = field(default_factory=list)
    required_claims: list[RequiredClaim] = field(default_factory=list)

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        raise RuntimeError("validate-jwt must be executed through apply_async")

    async def apply_async(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        token = render_policy_value(self.token_value or "", req, runtime) if self.token_value else None
        header_name = render_policy_value(self.header_name or "", req, runtime) if self.header_name else None
        query_name = (
            render_policy_value(self.query_parameter_name or "", req, runtime) if self.query_parameter_name else None
        )

        if header_name:
            header_value = req.headers.get(header_name.lower())
            if header_value is None:
                return self._failure(req, runtime, "JWT not present.")
            if self.require_scheme and header_name.lower() == "authorization":
                expected_prefix = f"{self.require_scheme} "
                if not header_value.startswith(expected_prefix):
                    return self._failure(req, runtime, "JWT not present.")
                token = header_value[len(expected_prefix) :].strip()
            else:
                token = header_value.strip()
        elif query_name:
            token = req.query.get(query_name)

        if not token:
            return self._failure(req, runtime, "JWT not present.")

        if runtime is None or runtime.http_client is None:
            raise HTTPException(status_code=500, detail="validate-jwt requires an HTTP client")

        try:
            claims = await self._decode_token(token, req, runtime)
            self._validate_claims(claims, req, runtime)
        except HTTPException as exc:
            _record_jwt_validation(runtime, {"status": "invalid", "detail": exc.detail})
            return ResponseSpec(
                status_code=self.failed_validation_httpcode,
                headers={"content-type": "text/plain"},
                body=str(self.failed_validation_error_message or exc.detail).encode("utf-8"),
            )

        req.variables["_last_jwt_claims"] = claims
        _record_variable_write(runtime, "_last_jwt_claims", claims, "validate-jwt")
        if self.output_token_variable_name:
            jwt_value = JwtValue(claims, token)
            req.variables[self.output_token_variable_name] = jwt_value
            _record_variable_write(runtime, self.output_token_variable_name, jwt_value, "validate-jwt")
        _record_jwt_validation(
            runtime,
            {
                "status": "valid",
                "issuer": claims.get("iss"),
                "audience": claims.get("aud"),
                "output_variable": self.output_token_variable_name,
            },
        )
        return None

    def _failure(self, req: PolicyRequest, runtime: PolicyRuntime | None, detail: str) -> ResponseSpec:
        _record_jwt_validation(runtime, {"status": "invalid", "detail": detail})
        return ResponseSpec(
            status_code=self.failed_validation_httpcode,
            headers={"content-type": "text/plain"},
            body=str(self.failed_validation_error_message or detail).encode("utf-8"),
        )

    async def _decode_token(
        self,
        token: str,
        req: PolicyRequest,
        runtime: PolicyRuntime,
    ) -> dict[str, Any]:
        urls = [render_policy_value(url, req, runtime) for url in self.openid_config_urls]
        if not urls:
            raise HTTPException(status_code=500, detail="validate-jwt requires at least one openid-config url")

        unverified = jwt.get_unverified_header(token)
        kid = unverified.get("kid")
        last_error: Exception | None = None

        for url in urls:
            metadata, jwks = await _load_openid_configuration(url, runtime)
            keys = jwks.get("keys") or []
            candidates = [item for item in keys if isinstance(item, dict)]
            if kid:
                candidates = [item for item in candidates if item.get("kid") == kid] or candidates
            for jwk in candidates:
                try:
                    key = RSAAlgorithm.from_jwk(json.dumps(jwk))
                    claims = jwt.decode(
                        token,
                        key,
                        algorithms=["RS256", "RS384", "RS512", "PS256", "ES256"],
                        options={
                            "verify_aud": False,
                            "verify_iss": False,
                            "require": ["exp"] if self.require_expiration_time else [],
                        },
                    )
                    if not self.issuers and metadata.get("issuer"):
                        claims.setdefault("_metadata_issuer", metadata.get("issuer"))
                    return claims
                except Exception as exc:  # pragma: no cover - exercised indirectly via failure path
                    last_error = exc
                    continue

        raise HTTPException(status_code=401, detail="Invalid or expired access token") from last_error

    def _validate_claims(self, claims: dict[str, Any], req: PolicyRequest, runtime: PolicyRuntime | None) -> None:
        expected_issuers = [render_policy_value(item, req, runtime) for item in self.issuers]
        expected_audiences = [render_policy_value(item, req, runtime) for item in self.audiences]
        if not expected_issuers and claims.get("_metadata_issuer"):
            expected_issuers = [str(claims.get("_metadata_issuer"))]

        issuer = str(claims.get("iss") or "")
        if expected_issuers and issuer not in expected_issuers:
            raise HTTPException(status_code=401, detail="Issuer validation failed")

        actual_aud = claims.get("aud")
        audiences = (
            [str(item) for item in actual_aud]
            if isinstance(actual_aud, list)
            else ([str(actual_aud)] if actual_aud else [])
        )
        if expected_audiences and not set(expected_audiences).intersection(audiences):
            raise HTTPException(status_code=401, detail="Audience validation failed")

        for claim in self.required_claims:
            actual = claims.get(claim.name)
            if actual is None:
                raise HTTPException(status_code=401, detail=f"Missing required claim: {claim.name}")
            if isinstance(actual, list):
                actual_values = [str(item) for item in actual]
            elif claim.separator and isinstance(actual, str):
                actual_values = [item.strip() for item in actual.split(claim.separator) if item.strip()]
            else:
                actual_values = [str(actual)]

            expected = [render_policy_value(item, req, runtime) for item in claim.values]
            if claim.match == "any":
                if not set(expected).intersection(actual_values):
                    raise HTTPException(status_code=401, detail=f"Claim validation failed: {claim.name}")
                continue
            if not set(expected).issubset(set(actual_values)):
                raise HTTPException(status_code=401, detail=f"Claim validation failed: {claim.name}")


@dataclass(frozen=True)
class SetBackendService(PolicyNode):
    base_url: str | None = None
    backend_id: str | None = None

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        resolved_backend_id = render_policy_value(self.backend_id or "", req, runtime) if self.backend_id else None
        resolved_base_url = render_policy_value(self.base_url or "", req, runtime) if self.base_url else None

        if resolved_backend_id:
            req.variables["selected_backend_id"] = resolved_backend_id
            if runtime and runtime.gateway_config:
                backend = runtime.gateway_config.backends.get(resolved_backend_id)
                if backend is None:
                    raise HTTPException(status_code=500, detail=f"Unknown backend: {resolved_backend_id}")
                req.variables["selected_backend_url"] = backend.url
            if runtime and runtime.trace is not None:
                runtime.trace.selected_backend = {"backend_id": resolved_backend_id}
            _record_step(runtime, "set-backend-service", {"backend_id": resolved_backend_id})
            return None

        if not resolved_base_url:
            raise HTTPException(status_code=500, detail="set-backend-service requires backend-id or base-url")
        req.variables["selected_backend_url"] = resolved_base_url
        if runtime and runtime.trace is not None:
            runtime.trace.selected_backend = {"base_url": resolved_base_url}
        _record_step(runtime, "set-backend-service", {"base_url": resolved_base_url})
        return None


@dataclass(frozen=True)
class SendRequest(PolicyNode):
    mode: str
    response_variable_name: str
    timeout: str | None = None
    ignore_error: bool = False
    url: str | None = None
    method: str | None = None
    headers: list[SetHeader] = field(default_factory=list)
    body: str | None = None
    authentication_certificate_thumbprint: str | None = None
    authentication_managed_identity_resource: str | None = None

    def apply(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        raise RuntimeError("send-request must be executed through apply_async")

    async def apply_async(self, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> ResponseSpec | None:
        if runtime is None or runtime.http_client is None:
            raise HTTPException(status_code=500, detail="send-request requires an HTTP client")

        mode = (render_policy_value(self.mode, req, runtime) or "new").lower()
        headers = dict(req.headers) if mode == "copy" else {}
        method = req.method if mode == "copy" else "GET"
        body = req.body if mode == "copy" else b""
        url = str(req.variables.get("original_request_url") or "")

        if self.url is not None:
            url = render_policy_value(self.url, req, runtime)
        if not url:
            raise HTTPException(status_code=500, detail="send-request requires set-url")
        if self.method is not None:
            method = render_policy_value(self.method, req, runtime).upper()

        temp_req = PolicyRequest(
            method=req.method,
            path=req.path,
            query=dict(req.query),
            headers=headers,
            variables=req.variables,
            body=body,
        )
        for header in self.headers:
            header.apply(temp_req, runtime)
        if self.body is not None:
            temp_req.body = render_policy_value(self.body, req, runtime).encode("utf-8")

        if self.authentication_managed_identity_resource is not None:
            temp_req.headers["x-apim-managed-identity"] = "true"
            temp_req.headers["x-apim-managed-identity-resource"] = render_policy_value(
                self.authentication_managed_identity_resource,
                req,
                runtime,
            )
        if self.authentication_certificate_thumbprint is not None:
            temp_req.headers["x-apim-authentication-certificate-thumbprint"] = render_policy_value(
                self.authentication_certificate_thumbprint,
                req,
                runtime,
            )

        timeout = float(render_policy_value(self.timeout or "60", req, runtime)) if self.timeout else 60.0
        try:
            response = await runtime.http_client.request(
                method,
                url,
                headers=temp_req.headers,
                content=temp_req.body,
                timeout=timeout,
            )
        except httpx.RequestError as exc:
            if self.ignore_error:
                req.variables[self.response_variable_name] = None
                _record_variable_write(runtime, self.response_variable_name, None, "send-request")
                _record_send_request(
                    runtime,
                    {
                        "url": url,
                        "method": method,
                        "status": "ignored-error",
                        "error": str(exc),
                        "response_variable_name": self.response_variable_name,
                    },
                )
                return None
            raise HTTPException(status_code=500, detail=f"send-request failed: {exc}") from exc

        callout = CalloutResponse(
            status_code=response.status_code,
            headers=dict(response.headers),
            content=response.content,
            reason=response.reason_phrase,
        )
        req.variables[self.response_variable_name] = callout
        _record_variable_write(runtime, self.response_variable_name, callout, "send-request")
        _record_send_request(
            runtime,
            {
                "url": url,
                "method": method,
                "status_code": response.status_code,
                "response_variable_name": self.response_variable_name,
            },
        )
        return None


@dataclass(frozen=True)
class PolicyDocument:
    inbound: list[PolicyNode]
    backend: list[PolicyNode]
    outbound: list[PolicyNode]
    on_error: list[PolicyNode]


POLICY_VALUE_PATTERN = re.compile(r"\{([^{}]+)\}")


def _stringify_policy_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def _trace_safe_value(runtime: PolicyRuntime | None, value: Any) -> Any:
    if isinstance(value, JwtValue):
        value = {
            "type": "jwt",
            "subject": value.Subject,
            "issuer": value.Issuer,
            "audiences": value.Audiences,
            "claims": sorted(value.Claims.keys()),
        }
    elif isinstance(value, CalloutResponse):
        value = {
            "type": "response",
            "status_code": value.StatusCode,
            "reason": value.ReasonPhrase,
            "headers": dict(value.Headers),
            "body_text": value.Body.AsString()[:512],
        }
    if runtime and runtime.gateway_config:
        return mask_secret_data(value, runtime.gateway_config)
    return value


def _record_step(runtime: PolicyRuntime | None, step: str, detail: dict[str, Any]) -> None:
    if runtime is None or runtime.trace is None:
        return
    runtime.trace.steps.append({"step": step, **_trace_safe_value(runtime, detail)})


def _record_variable_write(runtime: PolicyRuntime | None, name: str, value: Any, source: str) -> None:
    if runtime is None or runtime.trace is None:
        return
    runtime.trace.variable_writes.append({"name": name, "source": source, "value": _trace_safe_value(runtime, value)})


def _record_send_request(runtime: PolicyRuntime | None, payload: dict[str, Any]) -> None:
    if runtime is None or runtime.trace is None:
        return
    runtime.trace.send_requests.append(_trace_safe_value(runtime, payload))


def _record_jwt_validation(runtime: PolicyRuntime | None, payload: dict[str, Any]) -> None:
    if runtime is None or runtime.trace is None:
        return
    runtime.trace.jwt_validations.append(_trace_safe_value(runtime, payload))


def _resolve_policy_token(req: PolicyRequest, token: str) -> str | None:
    normalized = token.strip()
    lowered = normalized.lower()

    if lowered == "method":
        return req.method
    if lowered == "path":
        return req.path
    if lowered == "subscription_id":
        return _stringify_policy_value(req.variables.get("subscription_id"))
    if lowered.startswith("header:"):
        name = lowered.split(":", 1)[1].strip()
        return _stringify_policy_value(req.headers.get(name))
    if lowered.startswith("query:"):
        name = normalized.split(":", 1)[1].strip()
        return _stringify_policy_value(req.query.get(name))
    if lowered.startswith("var:") or lowered.startswith("variable:"):
        name = normalized.split(":", 1)[1].strip()
        return _stringify_policy_value(req.variables.get(name))
    return None


def evaluate_policy_value(template: str, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> Any:
    source = template or ""
    if runtime and runtime.gateway_config:
        source = resolve_named_values_in_text(source, runtime.gateway_config)
    if is_apim_expression(source):
        return evaluate_apim_expression(source, build_expression_context(req))

    def _replace(match: re.Match[str]) -> str:
        resolved = _resolve_policy_token(req, match.group(1))
        if resolved is None:
            return match.group(0)
        return resolved

    return POLICY_VALUE_PATTERN.sub(_replace, source)


def render_policy_value(template: str, req: PolicyRequest, runtime: PolicyRuntime | None = None) -> str:
    return _stringify_policy_value(evaluate_policy_value(template, req, runtime))


def _text_or_empty(el: ElementTree.Element | None) -> str:
    if el is None or el.text is None:
        return ""
    return el.text.strip()


def _policy_value_or_empty(el: ElementTree.Element) -> str:
    attr_value = el.attrib.get("value")
    if attr_value is not None:
        return attr_value.strip()
    value_el = el.find("value")
    if value_el is not None:
        return _text_or_empty(value_el)
    return _text_or_empty(el)


def _parse_set_header(el: ElementTree.Element) -> SetHeader:
    name = el.attrib.get("name")
    if not name:
        raise HTTPException(status_code=500, detail="set-header missing name")
    exists_action = el.attrib.get("exists-action", "override")
    value = _policy_value_or_empty(el)
    return SetHeader(name=name.lower(), value=value, exists_action=exists_action)


def _parse_set_variable(el: ElementTree.Element) -> SetVariable:
    name = (el.attrib.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=500, detail="set-variable missing name")
    return SetVariable(name=name, value=_policy_value_or_empty(el))


def _parse_set_query_parameter(el: ElementTree.Element) -> SetQueryParameter:
    name = (el.attrib.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=500, detail="set-query-parameter missing name")
    exists_action = el.attrib.get("exists-action", "override")
    return SetQueryParameter(name=name, value=_policy_value_or_empty(el), exists_action=exists_action)


def _parse_set_body(el: ElementTree.Element) -> SetBody:
    return SetBody(value=_policy_value_or_empty(el))


def _parse_rewrite_uri(el: ElementTree.Element) -> RewriteUri:
    template = el.attrib.get("template")
    if not template:
        raise HTTPException(status_code=500, detail="rewrite-uri missing template")
    return RewriteUri(template=template)


def _parse_return_response(el: ElementTree.Element) -> ReturnResponse:
    status_el = el.find("set-status")
    if status_el is None:
        raise HTTPException(status_code=500, detail="return-response missing set-status")
    code = int(status_el.attrib.get("code") or "200")
    reason = status_el.attrib.get("reason")
    headers = [_parse_set_header(h) for h in el.findall("set-header")]
    body_el = el.find("body")
    set_body_el = el.find("set-body")
    body = (
        _parse_set_body(set_body_el).value
        if set_body_el is not None
        else (_text_or_empty(body_el) if body_el is not None else None)
    )
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
        value = _text_or_empty(addr)
        if value:
            allow.add(value)
    for cidr in el.findall("cidr"):
        value = _text_or_empty(cidr)
        if value:
            allow.add(value)
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


def _parse_rate_limit_by_key(el: ElementTree.Element) -> RateLimitByKey:
    calls = (el.attrib.get("calls") or "").strip()
    renewal_period = (el.attrib.get("renewal-period") or "").strip()
    counter_key = (el.attrib.get("counter-key") or "").strip()
    if not calls:
        raise HTTPException(status_code=500, detail="rate-limit-by-key requires calls")
    if not renewal_period:
        raise HTTPException(status_code=500, detail="rate-limit-by-key requires renewal-period")
    if not counter_key:
        raise HTTPException(status_code=500, detail="rate-limit-by-key requires counter-key")
    return RateLimitByKey(
        calls=calls,
        renewal_period=renewal_period,
        counter_key=counter_key,
        increment_condition=el.attrib.get("increment-condition"),
        increment_count=el.attrib.get("increment-count"),
        retry_after_header_name=el.attrib.get("retry-after-header-name"),
        retry_after_variable_name=el.attrib.get("retry-after-variable-name"),
        remaining_calls_header_name=el.attrib.get("remaining-calls-header-name"),
        remaining_calls_variable_name=el.attrib.get("remaining-calls-variable-name"),
        total_calls_header_name=el.attrib.get("total-calls-header-name"),
    )


def _parse_quota_by_key(el: ElementTree.Element) -> QuotaByKey:
    if el.attrib.get("bandwidth"):
        raise HTTPException(status_code=500, detail="quota-by-key bandwidth is not supported")
    calls = (el.attrib.get("calls") or "").strip()
    renewal_period = (el.attrib.get("renewal-period") or "").strip()
    counter_key = (el.attrib.get("counter-key") or "").strip()
    if not calls:
        raise HTTPException(status_code=500, detail="quota-by-key requires calls")
    if not renewal_period:
        raise HTTPException(status_code=500, detail="quota-by-key requires renewal-period")
    if not counter_key:
        raise HTTPException(status_code=500, detail="quota-by-key requires counter-key")
    return QuotaByKey(
        calls=calls,
        renewal_period=renewal_period,
        counter_key=counter_key,
        increment_condition=el.attrib.get("increment-condition"),
        increment_count=el.attrib.get("increment-count"),
        first_period_start=el.attrib.get("first-period-start"),
    )


def _parse_cache_lookup(el: ElementTree.Element) -> CacheLookup:
    return CacheLookup(
        vary_by_headers=_vary_values(
            [_text_or_empty(item) for item in el.findall("vary-by-header") if _text_or_empty(item)]
        ),
        vary_by_query_parameters=_vary_values(
            [_text_or_empty(item) for item in el.findall("vary-by-query-parameter") if _text_or_empty(item)]
        ),
        vary_by_developer=str(el.attrib.get("vary-by-developer") or "false"),
        vary_by_developer_groups=str(el.attrib.get("vary-by-developer-groups") or "false"),
        downstream_caching_type=str(el.attrib.get("downstream-caching-type") or "none"),
        must_revalidate=str(el.attrib.get("must-revalidate") or "true"),
        allow_private_response_caching=str(el.attrib.get("allow-private-response-caching") or "false"),
        caching_type=str(el.attrib.get("caching-type") or "prefer-external"),
    )


def _parse_cache_store(el: ElementTree.Element) -> CacheStore:
    duration = (el.attrib.get("duration") or "").strip()
    if not duration:
        raise HTTPException(status_code=500, detail="cache-store requires duration")
    return CacheStore(duration=duration, cache_response=el.attrib.get("cache-response"))


def _parse_cache_lookup_value(el: ElementTree.Element) -> CacheLookupValue:
    key = (el.attrib.get("key") or "").strip()
    variable_name = (el.attrib.get("variable-name") or "").strip()
    if not key:
        raise HTTPException(status_code=500, detail="cache-lookup-value requires key")
    if not variable_name:
        raise HTTPException(status_code=500, detail="cache-lookup-value requires variable-name")
    return CacheLookupValue(
        key=key,
        variable_name=variable_name,
        default_value=el.attrib.get("default-value"),
        caching_type=str(el.attrib.get("caching-type") or "prefer-external"),
    )


def _parse_cache_store_value(el: ElementTree.Element) -> CacheStoreValue:
    key = (el.attrib.get("key") or "").strip()
    value = (el.attrib.get("value") or "").strip()
    duration = (el.attrib.get("duration") or "").strip()
    if not key:
        raise HTTPException(status_code=500, detail="cache-store-value requires key")
    if value == "":
        raise HTTPException(status_code=500, detail="cache-store-value requires value")
    if not duration:
        raise HTTPException(status_code=500, detail="cache-store-value requires duration")
    return CacheStoreValue(
        key=key,
        value=value,
        duration=duration,
        caching_type=str(el.attrib.get("caching-type") or "prefer-external"),
    )


def _parse_cache_remove_value(el: ElementTree.Element) -> CacheRemoveValue:
    key = (el.attrib.get("key") or "").strip()
    if not key:
        raise HTTPException(status_code=500, detail="cache-remove-value requires key")
    return CacheRemoveValue(key=key, caching_type=str(el.attrib.get("caching-type") or "prefer-external"))


def _parse_validate_jwt(el: ElementTree.Element) -> ValidateJwt:
    required_claims: list[RequiredClaim] = []
    required_claims_el = el.find("required-claims")
    if required_claims_el is not None:
        for claim_el in required_claims_el.findall("claim"):
            name = (claim_el.attrib.get("name") or "").strip()
            if not name:
                raise HTTPException(status_code=500, detail="validate-jwt claim missing name")
            values = [_text_or_empty(value_el) for value_el in claim_el.findall("value") if _text_or_empty(value_el)]
            required_claims.append(
                RequiredClaim(
                    name=name,
                    values=values,
                    match=str(claim_el.attrib.get("match") or "all"),
                    separator=str(claim_el.attrib.get("separator")) if claim_el.attrib.get("separator") else None,
                )
            )

    return ValidateJwt(
        header_name=el.attrib.get("header-name"),
        query_parameter_name=el.attrib.get("query-parameter-name"),
        token_value=el.attrib.get("token-value"),
        failed_validation_httpcode=int(el.attrib.get("failed-validation-httpcode") or "401"),
        failed_validation_error_message=str(
            el.attrib.get("failed-validation-error-message") or "JWT validation failed"
        ),
        require_scheme=el.attrib.get("require-scheme"),
        require_expiration_time=str(el.attrib.get("require-expiration-time") or "true").lower() != "false",
        output_token_variable_name=el.attrib.get("output-token-variable-name"),
        openid_config_urls=[
            str(item.attrib.get("url")) for item in el.findall("openid-config") if item.attrib.get("url")
        ],
        issuers=[_text_or_empty(item) for item in el.findall("./issuers/issuer") if _text_or_empty(item)],
        audiences=[_text_or_empty(item) for item in el.findall("./audiences/audience") if _text_or_empty(item)],
        required_claims=required_claims,
    )


def _parse_set_backend_service(el: ElementTree.Element) -> SetBackendService:
    base_url = el.attrib.get("base-url")
    backend_id = el.attrib.get("backend-id")
    if not base_url and not backend_id:
        raise HTTPException(status_code=500, detail="set-backend-service requires backend-id or base-url")
    return SetBackendService(base_url=base_url, backend_id=backend_id)


def _parse_send_request(el: ElementTree.Element) -> SendRequest:
    response_variable_name = (el.attrib.get("response-variable-name") or "").strip()
    if not response_variable_name:
        raise HTTPException(status_code=500, detail="send-request missing response-variable-name")
    auth_cert_el = el.find("authentication-certificate")
    auth_mi_el = el.find("authentication-managed-identity")
    return SendRequest(
        mode=str(el.attrib.get("mode") or "new"),
        response_variable_name=response_variable_name,
        timeout=el.attrib.get("timeout"),
        ignore_error=str(el.attrib.get("ignore-error") or "false").lower() == "true",
        url=_text_or_empty(el.find("set-url")) if el.find("set-url") is not None else None,
        method=_text_or_empty(el.find("set-method")) if el.find("set-method") is not None else None,
        headers=[_parse_set_header(item) for item in el.findall("set-header")],
        body=(_parse_set_body(el.find("set-body")).value if el.find("set-body") is not None else None),
        authentication_certificate_thumbprint=(
            str(auth_cert_el.attrib.get("thumbprint"))
            if auth_cert_el is not None and auth_cert_el.attrib.get("thumbprint")
            else None
        ),
        authentication_managed_identity_resource=(
            str(auth_mi_el.attrib.get("resource"))
            if auth_mi_el is not None and auth_mi_el.attrib.get("resource")
            else None
        ),
    )


def _rate_limit_key(req: PolicyRequest, *, scope: str) -> str:
    scope = (scope or "subscription").lower()
    route = str(req.variables.get("route") or "")
    subscription_id = str(req.variables.get("subscription_id") or "")
    products = req.variables.get("products")
    product_part = ",".join(sorted(str(item) for item in products)) if isinstance(products, list) else ""
    client_ip = str(req.variables.get("client_ip") or "")
    if scope == "subscription":
        return f"sub:{subscription_id}|route:{route}|products:{product_part}"
    if scope == "product":
        return f"product:{product_part}|sub:{subscription_id}|route:{route}"
    if scope == "ip":
        return f"ip:{client_ip}|route:{route}"
    return f"route:{route}|sub:{subscription_id}|products:{product_part}"


def _parse_choose(
    el: ElementTree.Element,
    *,
    policy_fragments: dict[str, str],
    section_name: str,
    seen_fragments: set[str],
) -> Choose:
    branches: list[tuple[Condition, list[PolicyNode]]] = []
    for when in el.findall("when"):
        cond = parse_condition(when.attrib.get("condition"))
        steps = _parse_children(
            list(when),
            policy_fragments=policy_fragments,
            section_name=section_name,
            seen_fragments=set(seen_fragments),
        )
        branches.append((cond, steps))
    otherwise_el = el.find("otherwise")
    otherwise_steps = (
        _parse_children(
            list(otherwise_el),
            policy_fragments=policy_fragments,
            section_name=section_name,
            seen_fragments=set(seen_fragments),
        )
        if otherwise_el is not None
        else []
    )
    return Choose(branches=branches, otherwise=otherwise_steps)


def _fragment_elements(xml: str, *, section_name: str) -> list[ElementTree.Element]:
    try:
        root = ElementTree.fromstring(xml)
    except ElementTree.ParseError:
        try:
            root = ElementTree.fromstring(f"<fragment>{xml}</fragment>")
        except ElementTree.ParseError as exc:
            raise HTTPException(status_code=500, detail="Invalid policy fragment XML") from exc

    if root.tag == "policies":
        section = root.find(section_name)
        return list(section) if section is not None else []
    if root.tag == "fragment":
        return list(root)
    return [root]


def _parse_children(
    children: list[ElementTree.Element],
    *,
    policy_fragments: dict[str, str],
    section_name: str,
    seen_fragments: set[str],
) -> list[PolicyNode]:
    out: list[PolicyNode] = []
    for child in children:
        if child.tag == "include-fragment":
            fragment_id = (
                child.attrib.get("fragment-id") or child.attrib.get("name") or child.attrib.get("id") or ""
            ).strip()
            if not fragment_id:
                raise HTTPException(status_code=500, detail="include-fragment missing fragment-id")
            if fragment_id in seen_fragments:
                raise HTTPException(status_code=500, detail=f"Circular policy fragment include: {fragment_id}")
            fragment_xml = policy_fragments.get(fragment_id)
            if fragment_xml is None:
                raise HTTPException(status_code=500, detail=f"Unknown policy fragment: {fragment_id}")
            fragment_children = _fragment_elements(fragment_xml, section_name=section_name)
            out.extend(
                _parse_children(
                    fragment_children,
                    policy_fragments=policy_fragments,
                    section_name=section_name,
                    seen_fragments=seen_fragments | {fragment_id},
                )
            )
            continue
        out.append(
            _parse_node(
                child,
                policy_fragments=policy_fragments,
                section_name=section_name,
                seen_fragments=seen_fragments,
            )
        )
    return out


def _parse_node(
    el: ElementTree.Element,
    *,
    policy_fragments: dict[str, str],
    section_name: str,
    seen_fragments: set[str],
) -> PolicyNode:
    tag = el.tag
    if tag == "base":
        return NoOp()
    if tag == "set-header":
        return _parse_set_header(el)
    if tag == "set-variable":
        return _parse_set_variable(el)
    if tag == "set-query-parameter":
        return _parse_set_query_parameter(el)
    if tag == "set-body":
        return _parse_set_body(el)
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
    if tag == "rate-limit-by-key":
        return _parse_rate_limit_by_key(el)
    if tag == "quota":
        return _parse_quota(el)
    if tag == "quota-by-key":
        return _parse_quota_by_key(el)
    if tag == "cache-lookup":
        return _parse_cache_lookup(el)
    if tag == "cache-store":
        return _parse_cache_store(el)
    if tag == "cache-lookup-value":
        return _parse_cache_lookup_value(el)
    if tag == "cache-store-value":
        return _parse_cache_store_value(el)
    if tag == "cache-remove-value":
        return _parse_cache_remove_value(el)
    if tag == "return-response":
        return _parse_return_response(el)
    if tag == "choose":
        return _parse_choose(
            el,
            policy_fragments=policy_fragments,
            section_name=section_name,
            seen_fragments=seen_fragments,
        )
    if tag == "validate-jwt":
        return _parse_validate_jwt(el)
    if tag == "set-backend-service":
        return _parse_set_backend_service(el)
    if tag == "send-request":
        return _parse_send_request(el)
    raise HTTPException(status_code=500, detail=f"Unsupported policy element: {tag}")


def parse_policies_xml(xml: str, *, policy_fragments: dict[str, str] | None = None) -> PolicyDocument:
    try:
        root = ElementTree.fromstring(xml)
    except ElementTree.ParseError as exc:
        raise HTTPException(status_code=500, detail="Invalid policies XML") from exc
    if root.tag != "policies":
        raise HTTPException(status_code=500, detail="Policies XML must have <policies> root")

    fragments = policy_fragments or {}

    def section(name: str) -> list[PolicyNode]:
        sec = root.find(name)
        if sec is None:
            return []
        return _parse_children(list(sec), policy_fragments=fragments, section_name=name, seen_fragments=set())

    return PolicyDocument(
        inbound=section("inbound"),
        backend=section("backend"),
        outbound=section("outbound"),
        on_error=section("on-error"),
    )


async def _load_openid_configuration(url: str, runtime: PolicyRuntime) -> tuple[dict[str, Any], dict[str, Any]]:
    cached = runtime.openid_cache.get(url)
    if cached is not None:
        return cached
    if runtime.http_client is None:
        raise HTTPException(status_code=500, detail="validate-jwt requires an HTTP client")
    metadata_response = await runtime.http_client.get(url, timeout=runtime.timeout_seconds)
    metadata_response.raise_for_status()
    metadata = metadata_response.json()
    if not isinstance(metadata, dict) or not metadata.get("jwks_uri"):
        raise HTTPException(status_code=500, detail="Invalid openid-config document")
    jwks_response = await runtime.http_client.get(str(metadata["jwks_uri"]), timeout=runtime.timeout_seconds)
    jwks_response.raise_for_status()
    jwks = jwks_response.json()
    if not isinstance(jwks, dict):
        raise HTTPException(status_code=500, detail="Invalid JWKS document")
    runtime.openid_cache[url] = (metadata, jwks)
    return metadata, jwks


async def _apply_steps_async(
    steps: list[PolicyNode],
    req: PolicyRequest,
    runtime: PolicyRuntime | None = None,
) -> ResponseSpec | None:
    for step in steps:
        out = await step.apply_async(req, runtime)
        if out is not None:
            return out
    return None


async def apply_inbound_async(
    docs: list[PolicyDocument],
    req: PolicyRequest,
    runtime: PolicyRuntime | None = None,
) -> ResponseSpec | None:
    for doc in docs:
        out = await _apply_steps_async(doc.inbound, req, runtime)
        if out is not None:
            return out
    return None


async def apply_backend_async(
    docs: list[PolicyDocument],
    req: PolicyRequest,
    runtime: PolicyRuntime | None = None,
) -> ResponseSpec | None:
    for doc in docs:
        out = await _apply_steps_async(doc.backend, req, runtime)
        if out is not None:
            return out
    return None


async def apply_outbound_async(
    docs: list[PolicyDocument],
    req: PolicyRequest,
    runtime: PolicyRuntime | None = None,
) -> None:
    for doc in docs:
        out = await _apply_steps_async(doc.outbound, req, runtime)
        if out is not None:
            raise HTTPException(
                status_code=500, detail="Outbound policies cannot short-circuit responses in the simulator"
            )


async def apply_on_error_async(
    docs: list[PolicyDocument],
    req: PolicyRequest,
    runtime: PolicyRuntime | None = None,
) -> ResponseSpec | None:
    for doc in docs:
        out = await _apply_steps_async(doc.on_error, req, runtime)
        if out is not None:
            return out
    return None


def finalize_deferred_actions(req: PolicyRequest, runtime: PolicyRuntime | None = None) -> None:
    if runtime is None or not runtime.deferred_actions:
        apply_pending_response_headers(req, _response_header_target(req))
        return
    actions = list(runtime.deferred_actions)
    runtime.deferred_actions.clear()
    for action in actions:
        action.finalize(req, runtime)
    apply_pending_response_headers(req, _response_header_target(req))


def apply_inbound(
    docs: list[PolicyDocument], req: PolicyRequest, runtime: PolicyRuntime | None = None
) -> ResponseSpec | None:
    return asyncio.run(apply_inbound_async(docs, req, runtime))


def apply_backend(
    docs: list[PolicyDocument], req: PolicyRequest, runtime: PolicyRuntime | None = None
) -> ResponseSpec | None:
    return asyncio.run(apply_backend_async(docs, req, runtime))


def apply_outbound(
    docs: list[PolicyDocument],
    *,
    headers: dict[str, str],
    variables: dict[str, Any] | None = None,
    response_status_code: int | None = None,
    response_body: bytes = b"",
    response_media_type: str | None = None,
    runtime: PolicyRuntime | None = None,
) -> None:
    req = PolicyRequest(
        method="GET",
        path="/",
        query={},
        headers=headers,
        variables=variables or {},
        response_status_code=response_status_code,
        response_headers=headers,
        response_body=response_body,
        response_media_type=response_media_type,
    )
    asyncio.run(apply_outbound_async(docs, req, runtime))
    finalize_deferred_actions(req, runtime)


def apply_on_error(
    docs: list[PolicyDocument], req: PolicyRequest, runtime: PolicyRuntime | None = None
) -> ResponseSpec | None:
    return asyncio.run(apply_on_error_async(docs, req, runtime))
