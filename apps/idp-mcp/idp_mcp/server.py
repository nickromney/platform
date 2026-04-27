from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

DEFAULT_IDP_API_BASE_URL = "https://portal-api.127.0.0.1.sslip.io"


@dataclass(frozen=True)
class IdpApiClient:
    base_url: str

    @classmethod
    def from_env(cls) -> "IdpApiClient":
        return cls(os.environ.get("IDP_API_BASE_URL", DEFAULT_IDP_API_BASE_URL).rstrip("/"))

    def platform_status(self) -> dict[str, Any]:
        return self._request("GET", "/api/v1/status")

    def catalog_list(self) -> dict[str, Any]:
        return self._request("GET", "/api/v1/catalog/apps")

    def create_environment(self, payload: dict[str, Any]) -> dict[str, Any]:
        request = {"runtime": "kind", **payload}
        return self._request("POST", "/api/v1/environments?dry_run=true", request)

    def _request(self, method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=body,
            method=method,
            headers={"content-type": "application/json", "accept": "application/json"},
        )

        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                response_body = response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8")
            raise RuntimeError(f"Portal API {exc.code}: {detail}") from exc

        return json.loads(response_body or "{}")


def tool_definitions() -> list[dict[str, Any]]:
    return [
        {
            "name": "platform_status",
            "description": "Read the platform status through the HTTP API.",
            "inputSchema": {"type": "object", "properties": {}},
        },
        {
            "name": "catalog_list",
            "description": "Read the platform IDP service catalog through the HTTP API.",
            "inputSchema": {"type": "object", "properties": {}},
        },
        {
            "name": "environment_create",
            "description": "Dry-run an application environment request through the HTTP API.",
            "inputSchema": {
                "type": "object",
                "required": ["app", "environment"],
                "properties": {
                    "app": {"type": "string"},
                    "environment": {"type": "string"},
                    "runtime": {"type": "string"},
                },
            },
        },
    ]


def handle_tool_call(client: IdpApiClient, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name == "platform_status":
        result = client.platform_status()
    elif name == "catalog_list":
        result = client.catalog_list()
    elif name == "environment_create":
        result = client.create_environment(arguments)
    else:
        raise ValueError(f"unknown tool: {name}")

    return {
        "content": [
            {
                "type": "text",
                "text": json.dumps(result, indent=2, sort_keys=True),
            }
        ]
    }


def handle_message(client: IdpApiClient, message: dict[str, Any]) -> dict[str, Any] | None:
    method = message.get("method")
    message_id = message.get("id")

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": message_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "serverInfo": {"name": "platform-idp-mcp", "version": "0.1.0"},
                "capabilities": {"tools": {}},
            },
        }

    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": message_id, "result": {"tools": tool_definitions()}}

    if method == "tools/call":
        params = message.get("params", {})
        result = handle_tool_call(client, params.get("name", ""), params.get("arguments", {}))
        return {"jsonrpc": "2.0", "id": message_id, "result": result}

    if message_id is None:
        return None

    return {
        "jsonrpc": "2.0",
        "id": message_id,
        "error": {"code": -32601, "message": f"method not found: {method}"},
    }


def main() -> None:
    client = IdpApiClient.from_env()
    for line in sys.stdin:
        if not line.strip():
            continue
        response = handle_message(client, json.loads(line))
        if response is not None:
            print(json.dumps(response), flush=True)


if __name__ == "__main__":
    main()
