from __future__ import annotations

import json
import re
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import urlparse

import httpx
import yaml

SUPPORTED_API_IMPORT_FORMATS = {
    "openapi",
    "openapi+json",
    "openapi-link",
    "openapi+json-link",
    "swagger-json",
    "swagger-link-json",
}

HTTP_METHODS = {"get", "post", "put", "patch", "delete", "head", "options", "trace"}
INLINE_JSON_FORMATS = {"openapi+json", "swagger-json"}


@dataclass(frozen=True)
class ImportedOperation:
    name: str
    method: str
    url_template: str


@dataclass(frozen=True)
class ApiImportResult:
    format: str
    operations: list[ImportedOperation] = field(default_factory=list)
    upstream_base_url: str | None = None
    diagnostics: list[str] = field(default_factory=list)


def _default_fetcher(url: str) -> str:
    response = httpx.get(url, timeout=30.0)
    response.raise_for_status()
    return response.text


def _load_api_document(raw: str) -> dict[str, Any]:
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        data = yaml.safe_load(raw)
    if not isinstance(data, dict):
        raise ValueError("API import document must be an object")
    return data


def _operation_name(method: str, path: str, payload: dict[str, Any]) -> str:
    operation_id = payload.get("operationId")
    if isinstance(operation_id, str) and operation_id.strip():
        return operation_id.strip()

    slug = re.sub(r"[^A-Za-z0-9]+", "-", path).strip("-").lower() or "root"
    return f"{method.lower()}-{slug}"


def _upstream_base_url(document: dict[str, Any]) -> str | None:
    servers = document.get("servers")
    if not isinstance(servers, list):
        return None
    for server in servers:
        if not isinstance(server, dict):
            continue
        url = server.get("url")
        if not isinstance(url, str) or not url.strip():
            continue
        parsed = urlparse(url)
        if parsed.scheme and parsed.netloc:
            return url.rstrip("/")
    return None


def parse_api_import(
    *,
    content_format: str,
    content_value: str,
    fetcher: Callable[[str], str] | None = None,
) -> ApiImportResult:
    normalized = (content_format or "").strip().lower()
    if normalized not in SUPPORTED_API_IMPORT_FORMATS:
        raise ValueError(f"Unsupported API import format: {content_format}")

    loader = fetcher or _default_fetcher
    raw = loader(content_value) if "link" in normalized else content_value
    document = _load_api_document(raw)

    paths = document.get("paths")
    if not isinstance(paths, dict):
        raise ValueError("API import document missing paths")

    operations: list[ImportedOperation] = []
    for path, methods in paths.items():
        if not isinstance(path, str) or not isinstance(methods, dict):
            continue
        for method_name, payload in methods.items():
            if method_name.lower() not in HTTP_METHODS:
                continue
            if not isinstance(payload, dict):
                payload = {}
            operations.append(
                ImportedOperation(
                    name=_operation_name(method_name, path, payload),
                    method=method_name.upper(),
                    url_template=path,
                )
            )

    diagnostics: list[str] = []
    if not operations:
        diagnostics.append("API import document did not produce any operations.")

    return ApiImportResult(
        format=normalized,
        operations=operations,
        upstream_base_url=_upstream_base_url(document),
        diagnostics=diagnostics,
    )
