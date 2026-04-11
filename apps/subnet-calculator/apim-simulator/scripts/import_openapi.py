#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

import httpx


def _looks_like_url(value: str) -> bool:
    parsed = urlparse(value)
    return bool(parsed.scheme and parsed.netloc)


def _load_source(source: str) -> tuple[str, str]:
    if _looks_like_url(source):
        return "openapi-link", source
    path = Path(source)
    if not path.exists():
        raise FileNotFoundError(source)
    suffix = path.suffix.lower()
    content_format = "openapi+json" if suffix == ".json" else "openapi"
    return content_format, path.read_text(encoding="utf-8")


def main() -> int:
    source = os.environ.get("OPENAPI_SOURCE", "").strip()
    if not source:
        print("OPENAPI_SOURCE must point to an OpenAPI file path or URL.", file=sys.stderr)
        return 2

    api_id = os.environ.get("APIM_API_ID", "").strip()
    if not api_id:
        parsed = urlparse(source)
        stem = Path(parsed.path or source).stem if parsed.path else Path(source).stem
        api_id = stem or "imported-api"

    content_format, content_value = _load_source(source)
    api_name = os.environ.get("APIM_API_NAME", api_id)
    api_path = os.environ.get("APIM_API_PATH", api_id)
    base_url = os.environ.get("APIM_BASE_URL", "http://localhost:8000").rstrip("/")
    tenant_key = os.environ.get("APIM_TENANT_KEY", "local-dev-tenant-key")
    products = [item.strip() for item in os.environ.get("APIM_API_PRODUCTS", "").split(",") if item.strip()]

    response = httpx.post(
        f"{base_url}/apim/management/apis/{api_id}/import",
        headers={"X-Apim-Tenant-Key": tenant_key},
        json={
            "name": api_name,
            "path": api_path,
            "content_format": content_format,
            "content_value": content_value,
            "products": products or None,
        },
        timeout=60.0,
    )
    response.raise_for_status()
    payload = response.json()

    print(
        json.dumps(
            {
                "api_id": api_id,
                "path": payload["api"]["path"],
                "operations": sorted(item["id"] for item in payload["api"]["operations"]),
                "import": payload["import"],
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
