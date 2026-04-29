#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import httpx


def _load_payload(path: str) -> dict:
    if path == "-":
        return json.load(sys.stdin)
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main() -> int:
    tofu_show = os.environ.get("TOFU_SHOW", "").strip()
    if not tofu_show:
        print("TOFU_SHOW must point to a terraform/tofu show -json file.", file=sys.stderr)
        return 2

    base_url = os.environ.get("APIM_BASE_URL", "http://localhost:8000").rstrip("/")
    tenant_key = os.environ.get("APIM_TENANT_KEY", "local-dev-tenant-key")
    payload = _load_payload(tofu_show)

    response = httpx.post(
        f"{base_url}/apim/management/import/tofu-show",
        headers={"X-Apim-Tenant-Key": tenant_key},
        json=payload,
        timeout=60.0,
    )
    response.raise_for_status()
    body = response.json()

    print(
        "Imported config:",
        json.dumps(
            {
                "routes": body["routes"],
                "products": body["products"],
                "subscriptions": body["subscriptions"],
                "apis": body["apis"],
            },
            indent=2,
        ),
    )
    diagnostics = body.get("diagnostics") or []
    if diagnostics:
        print("Diagnostics:")
        for item in diagnostics:
            print(f"- [{item['status']}] {item['scope']} / {item['feature']}: {item['detail']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
