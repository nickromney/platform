#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import os
import sys
import traceback

from smoke_mcp import make_async_client
from smoke_mcp import run as run_mcp

DEFAULT_PRIVATE_BASE_URL = "http://apim-simulator:8000"
DEFAULT_PRIVATE_HOST = "apim-simulator:8000"
BASE_URL = os.getenv("SMOKE_PRIVATE_BASE_URL", DEFAULT_PRIVATE_BASE_URL).rstrip("/")
SUBSCRIPTION_KEY = os.getenv("SMOKE_MCP_SUBSCRIPTION_KEY", "mcp-demo-key")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


async def main_async() -> None:
    async with make_async_client(timeout=20.0) as client:
        debug = await client.get(
            f"{BASE_URL}/__edge/echo",
            headers={
                "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
                "x-apim-trace": "true",
            },
        )
        debug.raise_for_status()
        payload = debug.json()
        echoed_headers = {key.lower(): value for key, value in payload["headers"].items()}

        require(echoed_headers.get("host") == DEFAULT_PRIVATE_HOST, f"unexpected upstream host: {echoed_headers}")

        trace_id = debug.headers.get("x-apim-trace-id")
        require(bool(trace_id), "trace id missing from private debug response")
        trace = await client.get(f"{BASE_URL}/apim/trace/{trace_id}")
        trace.raise_for_status()
        trace_payload = trace.json()

        require(trace_payload["incoming_host"] == DEFAULT_PRIVATE_HOST, f"unexpected trace host: {trace_payload}")
        require(trace_payload["upstream_url"].endswith("/api/echo"), f"unexpected upstream url: {trace_payload}")

    await run_mcp(url=f"{BASE_URL}/mcp", subscription_key=SUBSCRIPTION_KEY, verify=True)
    print("Private smoke passed")
    print(f"- base_url: {BASE_URL}")


def main() -> int:
    try:
        asyncio.run(main_async())
        return 0
    except Exception as exc:
        sys.stderr.write(f"Private smoke failed: {exc}\n")
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
