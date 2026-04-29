from __future__ import annotations

import json
import os
import ssl
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Probe:
    url: str
    timeout: float = 5.0


@dataclass(frozen=True)
class Response:
    status: int
    headers: dict[str, str]
    payload: str


def _ssl_context(url: str) -> ssl.SSLContext | None:
    if not url.startswith("https://"):
        return None
    cafile = os.getenv("BACKSTAGE_CA_FILE", "").strip()
    if cafile:
        return ssl.create_default_context(cafile=cafile)
    if os.getenv("BACKSTAGE_INSECURE_TLS", "false").lower() == "true":
        return ssl._create_unverified_context()  # noqa: S323
    return ssl.create_default_context()


def fetch(probe: Probe, *, headers: dict[str, str] | None = None) -> Response:
    request = urllib.request.Request(probe.url, headers=headers or {})
    with urllib.request.urlopen(request, timeout=probe.timeout, context=_ssl_context(probe.url)) as response:
        payload = response.read().decode("utf-8")
        return Response(
            status=response.status,
            headers={key.lower(): value for key, value in response.headers.items()},
            payload=payload,
        )


def fetch_json(probe: Probe, *, headers: dict[str, str] | None = None) -> Any:
    response = fetch(probe, headers={"Accept": "application/json", **(headers or {})})
    return json.loads(response.payload) if response.payload else None


def wait_for_http(probe: Probe, *, seconds: int = 90) -> Response:
    deadline = time.monotonic() + seconds
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            return fetch(probe)
        except (OSError, urllib.error.HTTPError, urllib.error.URLError) as exc:
            last_error = exc
            time.sleep(2)
    raise SystemExit(f"timed out waiting for {probe.url}: {last_error}")


def wait_for_json(probe: Probe, *, headers: dict[str, str] | None = None, seconds: int = 90) -> Any:
    deadline = time.monotonic() + seconds
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            return fetch_json(probe, headers=headers)
        except (OSError, urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as exc:
            last_error = exc
            time.sleep(2)
    raise SystemExit(f"timed out waiting for {probe.url}: {last_error}")


def main() -> None:
    base_url = os.getenv("BACKSTAGE_BASE_URL", "http://localhost:7007").rstrip("/")
    wait_for_http(Probe(f"{base_url}/api/app/health"))
    print(f"OK   Backstage app reachable at {base_url}/api/app/health")

    auth = wait_for_json(Probe(f"{base_url}/api/auth/guest/refresh"))
    token = auth.get("backstageIdentity", {}).get("token") or auth.get("token")
    if not token:
        raise SystemExit(f"guest auth response did not include a Backstage token: {auth}")

    entity = wait_for_json(
        Probe(f"{base_url}/api/catalog/entities/by-name/component/default/apim-simulator"),
        headers={"Authorization": f"Bearer {token}"},
    )
    if entity.get("metadata", {}).get("name") != "apim-simulator":
        raise SystemExit(f"unexpected catalog entity: {entity}")
    if "apim-simulator-gateway-api" not in entity.get("spec", {}).get("providesApis", []):
        raise SystemExit(f"catalog entity is missing gateway API relation: {entity}")
    print("OK   Backstage catalog imported component:default/apim-simulator")


if __name__ == "__main__":
    main()
