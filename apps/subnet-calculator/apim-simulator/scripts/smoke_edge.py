#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import os
import sys
import traceback
from pathlib import Path

import httpx
from smoke_mcp import make_async_client, resolve_tls_verify
from smoke_mcp import run_with_retry as run_mcp

BASE_URL = os.getenv("SMOKE_EDGE_BASE_URL", "http://apim.localtest.me:8088").rstrip("/")
SUBSCRIPTION_KEY = os.getenv("SMOKE_MCP_SUBSCRIPTION_KEY", "mcp-demo-key")
DEFAULT_CA_CERT = Path(__file__).resolve().parent.parent / "examples" / "edge" / "certs" / "dev-root-ca.crt"
VERIFY_TLS = resolve_tls_verify(
    default_ca=DEFAULT_CA_CERT if BASE_URL.startswith("https://") else None,
    ca_env="SMOKE_EDGE_CA_CERT",
    verify_env="SMOKE_EDGE_VERIFY_TLS",
    insecure_env="SMOKE_EDGE_INSECURE_SKIP_VERIFY",
)
EXPECTED_PROTO = os.getenv("SMOKE_EDGE_EXPECT_PROTO", "https" if BASE_URL.startswith("https://") else "http")
EXPECTED_HOST = os.getenv(
    "SMOKE_EDGE_EXPECT_HOST",
    "apim.localtest.me:8443" if BASE_URL.startswith("https://") else "apim.localtest.me:8088",
)
RETRY_ATTEMPTS = int(os.getenv("SMOKE_EDGE_ATTEMPTS", "20"))
RETRY_DELAY_SECONDS = float(os.getenv("SMOKE_EDGE_RETRY_DELAY_SECONDS", "1"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


async def get_with_retry(
    client: httpx.AsyncClient,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    attempts: int = RETRY_ATTEMPTS,
    delay_seconds: float = RETRY_DELAY_SECONDS,
) -> httpx.Response:
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            response = await client.get(url, headers=headers)
            response.raise_for_status()
            return response
        except Exception as exc:
            last_error = exc
            if attempt == attempts:
                raise
            await asyncio.sleep(delay_seconds)

    if last_error is not None:
        raise last_error
    raise RuntimeError(f"failed to fetch {url}")


async def main_async() -> None:
    async with make_async_client(timeout=20.0, verify=VERIFY_TLS) as client:
        debug = await get_with_retry(
            client,
            f"{BASE_URL}/__edge/echo",
            headers={
                "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
                "x-apim-trace": "true",
            },
        )
        payload = debug.json()
        echoed_headers = {key.lower(): value for key, value in payload["headers"].items()}

        require(echoed_headers.get("host") == EXPECTED_HOST, f"unexpected upstream host: {echoed_headers}")
        require(
            echoed_headers.get("x-forwarded-host") == EXPECTED_HOST,
            f"unexpected forwarded host: {echoed_headers}",
        )
        require(
            echoed_headers.get("x-forwarded-proto") == EXPECTED_PROTO,
            f"unexpected forwarded proto: {echoed_headers}",
        )
        require(bool(echoed_headers.get("x-forwarded-for")), f"forwarded-for missing: {echoed_headers}")

        trace_id = debug.headers.get("x-apim-trace-id")
        require(bool(trace_id), "trace id missing from edge debug response")

        trace = await client.get(f"{BASE_URL}/apim/trace/{trace_id}")
        trace.raise_for_status()
        trace_payload = trace.json()

        require(trace_payload["incoming_host"] == EXPECTED_HOST, f"unexpected trace host: {trace_payload}")
        require(trace_payload["forwarded_host"] == EXPECTED_HOST, f"unexpected trace forwarded host: {trace_payload}")
        require(trace_payload["forwarded_proto"] == EXPECTED_PROTO, f"unexpected trace proto: {trace_payload}")
        require(bool(trace_payload["forwarded_for"]), f"unexpected trace forwarded-for: {trace_payload}")
        require(trace_payload["client_ip"], f"trace client_ip missing: {trace_payload}")
        require(trace_payload["upstream_url"].endswith("/api/echo"), f"unexpected upstream url: {trace_payload}")

    await run_mcp(url=f"{BASE_URL}/mcp", subscription_key=SUBSCRIPTION_KEY, verify=VERIFY_TLS)
    print("Edge smoke passed")
    print(f"- base_url: {BASE_URL}")
    print(f"- forwarded_host: {EXPECTED_HOST}")
    print(f"- forwarded_proto: {EXPECTED_PROTO}")


def main() -> int:
    try:
        asyncio.run(main_async())
        return 0
    except Exception as exc:
        sys.stderr.write(f"Edge smoke failed: {exc}\n")
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
