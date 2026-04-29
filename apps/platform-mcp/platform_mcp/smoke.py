from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any

import httpx


def build_headers(token: str | None) -> dict[str, str]:
    headers = {
        "accept": "application/json, text/event-stream",
        "content-type": "application/json",
    }
    if token:
        headers["authorization"] = f"Bearer {token}"
    return headers


def rpc(method: str, params: dict[str, Any] | None = None, request_id: int = 1) -> dict[str, Any]:
    payload: dict[str, Any] = {"jsonrpc": "2.0", "id": request_id, "method": method}
    if params is not None:
        payload["params"] = params
    return payload


def list_tools(url: str, token: str | None, timeout_seconds: float) -> list[str]:
    headers = build_headers(token)
    with httpx.Client(timeout=timeout_seconds, verify=False) as client:
        client.post(
            url,
            headers=headers,
            json=rpc(
                "initialize",
                {
                    "protocolVersion": "2025-11-25",
                    "capabilities": {},
                    "clientInfo": {"name": "platform-mcp-smoke", "version": "0.1.0"},
                },
                request_id=1,
            ),
        ).raise_for_status()
        response = client.post(url, headers=headers, json=rpc("tools/list", request_id=2))
        response.raise_for_status()
        body = response.json()

    if "error" in body:
        raise RuntimeError(json.dumps(body["error"], sort_keys=True))
    tools = body.get("result", {}).get("tools", [])
    return sorted(tool["name"] for tool in tools)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="List tools from a Streamable HTTP MCP endpoint.")
    parser.add_argument("--url", default=os.environ.get("PLATFORM_MCP_URL", "https://mcp.127.0.0.1.sslip.io/mcp"))
    parser.add_argument("--token", default=os.environ.get("PLATFORM_MCP_BEARER_TOKEN"))
    parser.add_argument("--timeout", type=float, default=float(os.environ.get("PLATFORM_MCP_SMOKE_TIMEOUT", "10")))
    args = parser.parse_args(argv)

    try:
        tool_names = list_tools(args.url, args.token, args.timeout)
    except Exception as exc:
        print(f"platform-mcp-smoke: {exc}", file=sys.stderr)
        return 1

    print(json.dumps({"url": args.url, "tools": tool_names}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
