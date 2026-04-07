from __future__ import annotations

from dataclasses import dataclass
from fnmatch import fnmatch
from typing import Any

from fastapi import Request

from app.config import ApiVersioningScheme, GatewayConfig, RouteConfig
from app.security import AuthContext, build_client_principal

HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "host",
}


@dataclass(frozen=True)
class ResolvedRoute:
    route: RouteConfig
    upstream_path: str
    api_version: str | None = None


def _normalize_host(host: str) -> str:
    normalized = host.strip().lower()
    if not normalized:
        return ""
    # Prefer the first proxy hop host if a list is forwarded.
    return normalized.split(",", 1)[0].strip()


def _strip_port(host: str) -> str:
    if not host:
        return ""
    # Bracketed IPv6, optionally with port.
    if host.startswith("["):
        end = host.find("]")
        if end != -1:
            return host[: end + 1]
        return host
    if ":" in host:
        left, right = host.rsplit(":", 1)
        if right.isdigit():
            return left
    return host


def _expand_host_candidates(raw_host: str) -> list[str]:
    normalized = _normalize_host(raw_host)
    if not normalized:
        return []

    candidates: list[str] = []
    for value in (normalized, _strip_port(normalized)):
        if value and value not in candidates:
            candidates.append(value)
    return candidates


def _request_host_candidate_groups(request: Request) -> list[list[str]]:
    groups: list[list[str]] = []
    raw_values = [
        request.headers.get("x-forwarded-host", ""),
        request.headers.get("host", ""),
        request.url.hostname or "",
    ]
    for raw in raw_values:
        candidates = _expand_host_candidates(raw)
        if not candidates:
            continue
        if candidates in groups:
            continue
        groups.append(candidates)
    return groups


def _route_matches_host(route: RouteConfig, request_hosts: list[str]) -> bool:
    if not route.host_match:
        return True
    if not request_hosts:
        return False
    for expected in route.host_match:
        expected_norm = _normalize_host(expected)
        if not expected_norm:
            continue
        expected_no_port = _strip_port(expected_norm)
        for request_host in request_hosts:
            request_no_port = _strip_port(request_host)
            if expected_norm == request_host or expected_norm == request_no_port:
                return True
            if expected_no_port == request_host or expected_no_port == request_no_port:
                return True
            if "*" in expected_norm and (
                fnmatch(request_host, expected_norm) or fnmatch(request_no_port, expected_norm)
            ):
                return True
            if "*" in expected_no_port and (
                fnmatch(request_host, expected_no_port) or fnmatch(request_no_port, expected_no_port)
            ):
                return True
    return False


def _available_versions(config: GatewayConfig, *, method: str, path: str, version_set: str) -> set[str]:
    versions: set[str] = set()
    for route in config.routes:
        if route.api_version_set != version_set:
            continue
        if not route.matches(method=method, path=path):
            continue
        if route.api_version:
            versions.add(route.api_version)
    return versions


def _read_version(request: Request, *, config: GatewayConfig, route: RouteConfig, path: str) -> tuple[str | None, str]:
    # Returns (version, upstream_path).
    version_set_id = route.api_version_set
    if not version_set_id:
        return None, path

    version_set = config.api_version_sets.get(version_set_id)
    if version_set is None:
        return None, path

    if version_set.versioning_scheme == ApiVersioningScheme.Header:
        header_name = version_set.version_header_name or ""
        version = request.headers.get(header_name)
        return version, path

    if version_set.versioning_scheme == ApiVersioningScheme.Query:
        query_name = version_set.version_query_name or ""
        version = request.query_params.get(query_name)
        return version, path

    # Segment scheme: by default treat the first segment after path_prefix as the version.
    prefix = route.path_prefix.rstrip("/")
    remainder = path
    if prefix and (path == prefix or path.startswith(prefix + "/")):
        remainder = path[len(prefix) :]
    remainder = remainder.lstrip("/")
    first = remainder.split("/", 1)[0] if remainder else ""

    candidates = _available_versions(config, method=request.method, path=path, version_set=version_set_id)
    if first and first in candidates:
        # Strip the version segment for upstream routing to keep the internal API path stable.
        stripped = (prefix + "/" + remainder.split("/", 1)[1]) if "/" in remainder else prefix
        stripped = stripped or "/"
        return first, stripped
    return None, path


def resolve_route(config: GatewayConfig, request: Request) -> ResolvedRoute | None:
    path = request.url.path
    request_host_groups = _request_host_candidate_groups(request)
    if not request_host_groups:
        request_host_groups = [[]]

    for request_hosts in request_host_groups:
        for route in config.routes:
            if not route.matches(method=request.method, path=path):
                continue
            if not _route_matches_host(route, request_hosts):
                continue

            if not route.api_version_set:
                return ResolvedRoute(route=route, upstream_path=path)

            version_set_id = route.api_version_set
            version_set = config.api_version_sets.get(version_set_id)
            if version_set is None:
                # Misconfigured; fall through to "no route".
                return None

            requested_version, upstream_path = _read_version(request, config=config, route=route, path=path)
            if not requested_version:
                requested_version = version_set.default_version

            if not requested_version:
                return None

            for candidate in config.routes:
                if candidate.api_version_set != version_set_id:
                    continue
                if candidate.api_version != requested_version:
                    continue
                if not candidate.matches(method=request.method, path=path):
                    continue
                if not _route_matches_host(candidate, request_hosts):
                    continue
                return ResolvedRoute(route=candidate, upstream_path=upstream_path, api_version=requested_version)

            return None

    return None


def build_upstream_headers(request: Request, auth: AuthContext) -> dict[str, str]:
    headers: dict[str, str] = {
        key: value for key, value in request.headers.items() if key.lower() not in HOP_BY_HOP_HEADERS
    }
    incoming_host = request.headers.get("host")
    if incoming_host:
        headers["host"] = incoming_host

    claims = auth.claims
    headers["x-apim-user-object-id"] = str(claims.get("sub", ""))
    headers["x-apim-user-email"] = str(claims.get("email", ""))
    headers["x-apim-user-name"] = str(claims.get("name") or claims.get("preferred_username") or "")
    headers["x-apim-auth-method"] = "oidc"
    headers["x-ms-client-principal"] = build_client_principal(claims)
    headers["x-ms-client-principal-name"] = str(claims.get("preferred_username", ""))

    if auth.subscription is not None:
        headers["x-user-id"] = auth.subscription.id
        headers["x-user-name"] = auth.subscription.name
        if auth.subscription_products:
            headers["x-apim-products"] = ",".join(auth.subscription_products)

    return headers


def filter_response_headers(upstream_headers: dict[str, str]) -> dict[str, str]:
    headers = {key: value for key, value in upstream_headers.items() if key.lower() not in HOP_BY_HOP_HEADERS}
    headers["x-apim-simulator"] = "apim-simulator"
    return headers


def build_user_payload(auth: AuthContext, issuer: str | None, audience: str | None) -> dict[str, Any]:
    claims = auth.claims
    return {
        "name": claims.get("name") or claims.get("preferred_username"),
        "email": claims.get("email"),
        "preferred_username": claims.get("preferred_username"),
        "sub": claims.get("sub"),
        "issuer": issuer or claims.get("iss"),
        "aud": audience or claims.get("aud"),
        "subscription": auth.subscription.model_dump() if auth.subscription is not None else None,
        "products": auth.subscription_products,
    }
