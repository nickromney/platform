from __future__ import annotations

import asyncio
import shutil
import sys
from pathlib import Path
from typing import Any

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from platform_mcp.d2 import D2Runner
from platform_mcp.observability import MetricsRegistry, observed_tool_call
from platform_mcp.server import HttpServerSettings, REQUIRED_TOOL_NAMES, RuntimeSettings, ToolRuntime, create_mcp_server
from platform_mcp.smoke import build_headers, rpc


class FakeApiClient:
    def __init__(self, responses: dict[tuple[str, str], dict[str, Any]]) -> None:
        self.responses = responses
        self.calls: list[tuple[str, str, dict[str, Any] | None]] = []

    async def get(self, path: str) -> dict[str, Any]:
        self.calls.append(("GET", path, None))
        return self.responses[("GET", path)]

    async def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        self.calls.append(("POST", path, payload))
        return self.responses[("POST", path)]


class FakeD2Runner:
    async def validate(self, source: str) -> dict[str, Any]:
        return {"status": "ok", "source_size": len(source)}

    async def format(self, source: str) -> dict[str, Any]:
        return {"status": "ok", "source": source.strip() + "\n"}

    async def render(self, source: str, *, output_format: str, layout: str) -> dict[str, Any]:
        return {
            "status": "ok",
            "format": output_format,
            "layout": layout,
            "content": "<svg></svg>",
            "source_size": len(source),
        }


def runtime() -> ToolRuntime:
    return ToolRuntime(
        settings=RuntimeSettings(),
        idp_client=FakeApiClient(
            {
                ("GET", "/api/v1/status"): {"status": "ok"},
                ("GET", "/api/v1/catalog/apps"): {"items": [{"name": "subnetcalc"}]},
            }
        ),
        subnetcalc_client=FakeApiClient(
            {
                ("POST", "/api/v1/ipv4/subnet-info"): {"network": "192.168.1.0/24", "mode": "Azure"},
                ("POST", "/api/v1/ipv6/subnet-info"): {"network": "2001:db8::/64"},
            }
        ),
        sentiment_client=FakeApiClient(
            {
                ("POST", "/api/v1/comments"): {
                    "text": "clear and useful",
                    "label": "positive",
                    "confidence": 0.98,
                }
            }
        ),
        d2_runner=FakeD2Runner(),
    )


@pytest.mark.asyncio
async def test_tools_list_includes_required_tools_from_fastmcp_registry() -> None:
    mcp = create_mcp_server(runtime())

    tool_names = {tool.name for tool in await mcp.list_tools()}

    assert tool_names == REQUIRED_TOOL_NAMES
    assert len(tool_names) == 7


def test_create_mcp_server_uses_fastmcp_streamable_http_defaults() -> None:
    mcp = create_mcp_server(runtime(), HttpServerSettings())

    assert mcp.name == "platform-mcp"
    assert mcp.settings.host == "0.0.0.0"
    assert mcp.settings.port == 8080
    assert mcp.settings.streamable_http_path == "/mcp"
    assert mcp.settings.stateless_http is True
    assert mcp.settings.json_response is True


def test_create_mcp_server_exposes_health_route() -> None:
    mcp = create_mcp_server(runtime(), HttpServerSettings())

    assert "/health" in {route.path for route in mcp.streamable_http_app().routes}


def test_http_server_settings_honor_platform_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("PLATFORM_MCP_HOST", "127.0.0.1")
    monkeypatch.setenv("PLATFORM_MCP_PORT", "18080")
    monkeypatch.setenv("PLATFORM_MCP_PATH", "/custom-mcp")

    mcp = create_mcp_server(runtime())

    assert mcp.settings.host == "127.0.0.1"
    assert mcp.settings.port == 18080
    assert mcp.settings.streamable_http_path == "/custom-mcp"


@pytest.mark.asyncio
async def test_platform_tools_return_structured_payloads_with_next_actions() -> None:
    tools = runtime()

    status = await tools.platform_status()
    catalog = await tools.platform_catalog_list()

    assert status["status"] == "ok"
    assert status["data"] == {"status": "ok"}
    assert "next_actions" in status
    assert catalog["data"]["items"][0]["name"] == "subnetcalc"


@pytest.mark.asyncio
async def test_subnetcalc_calculate_uses_mocked_http_client_and_detects_ip_version() -> None:
    tools = runtime()

    result = await tools.subnetcalc_calculate(cidr="192.168.1.0/24", mode="Azure")

    assert result["status"] == "ok"
    assert result["data"]["network"] == "192.168.1.0/24"
    assert tools.subnetcalc_client.calls == [
        ("POST", "/api/v1/ipv4/subnet-info", {"network": "192.168.1.0/24", "mode": "Azure"})
    ]


@pytest.mark.asyncio
async def test_sentiment_classify_uses_mocked_http_client() -> None:
    tools = runtime()

    result = await tools.sentiment_classify(text="clear and useful")

    assert result["status"] == "ok"
    assert result["data"]["label"] == "positive"
    assert tools.sentiment_client.calls == [("POST", "/api/v1/comments", {"text": "clear and useful"})]


@pytest.mark.asyncio
async def test_d2_missing_binary_is_structured_recoverable_error() -> None:
    tools = ToolRuntime(
        settings=RuntimeSettings(d2_binary="/definitely/not/d2"),
        idp_client=FakeApiClient({}),
        subnetcalc_client=FakeApiClient({}),
        sentiment_client=FakeApiClient({}),
        d2_runner=D2Runner(binary="/definitely/not/d2", max_source_bytes=1024, timeout_seconds=1),
    )

    result = await tools.d2_validate(source="a -> b")

    assert result["status"] == "error"
    assert result["error"]["code"] == "D2_UNAVAILABLE"
    assert result["error"]["recoverable"] is True
    assert "next_actions" in result


@pytest.mark.asyncio
async def test_d2_source_size_limit_is_structured_recoverable_error() -> None:
    binary = shutil.which("true") or "/usr/bin/true"
    tools = ToolRuntime(
        settings=RuntimeSettings(d2_binary=binary, d2_max_source_bytes=5),
        idp_client=FakeApiClient({}),
        subnetcalc_client=FakeApiClient({}),
        sentiment_client=FakeApiClient({}),
        d2_runner=D2Runner(binary=binary, max_source_bytes=5, timeout_seconds=1),
    )

    result = await tools.d2_validate(source="a -> b")

    assert result["status"] == "error"
    assert result["error"]["code"] == "D2_SOURCE_TOO_LARGE"
    assert result["error"]["recoverable"] is True


@pytest.mark.asyncio
async def test_d2_timeout_is_structured_recoverable_error(tmp_path: Path) -> None:
    script = tmp_path / "slow-d2"
    script.write_text("#!/bin/sh\nsleep 2\n", encoding="utf-8")
    script.chmod(0o755)
    tools = ToolRuntime(
        settings=RuntimeSettings(d2_binary=str(script), d2_timeout_seconds=0.01),
        idp_client=FakeApiClient({}),
        subnetcalc_client=FakeApiClient({}),
        sentiment_client=FakeApiClient({}),
        d2_runner=D2Runner(binary=str(script), max_source_bytes=1024, timeout_seconds=0.01),
    )

    result = await tools.d2_render(source="a -> b")

    assert result["status"] == "error"
    assert result["error"]["code"] == "D2_TIMEOUT"
    assert result["error"]["recoverable"] is True


@pytest.mark.asyncio
async def test_d2_runner_does_not_use_shell_interpolation(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    observed: dict[str, Any] = {}
    binary = tmp_path / "d2"
    binary.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    binary.chmod(0o755)

    async def fake_create_subprocess_exec(*args: str, **kwargs: Any) -> Any:
        observed["args"] = args
        output_path = Path(args[-1])

        class Process:
            returncode = 0

            async def communicate(self, input: bytes | None = None) -> tuple[bytes, bytes]:
                output_path.write_text("<svg></svg>", encoding="utf-8")
                return b"", b""

        return Process()

    monkeypatch.setattr(asyncio, "create_subprocess_exec", fake_create_subprocess_exec)
    runner = D2Runner(binary=str(binary), max_source_bytes=1024, timeout_seconds=1)

    result = await runner.render("a -> b", output_format="svg", layout="elk")

    assert result["status"] == "ok"
    assert observed["args"][0] == str(binary)
    assert all(";" not in arg for arg in observed["args"])


def test_smoke_client_builds_bearer_headers_and_json_rpc_payloads() -> None:
    headers = build_headers("token-123")
    payload = rpc("tools/list", request_id=7)

    assert headers["authorization"] == "Bearer token-123"
    assert headers["accept"] == "application/json, text/event-stream"
    assert payload == {"jsonrpc": "2.0", "id": 7, "method": "tools/list"}


@pytest.mark.asyncio
async def test_observed_tool_calls_emit_prometheus_metrics() -> None:
    registry = MetricsRegistry()

    async def call() -> dict[str, Any]:
        return {"status": "ok"}

    result = await observed_tool_call("platform_status", call)
    registry.record_tool_call("platform_status", "ok", 0.25)
    rendered = registry.render()

    assert result == {"status": "ok"}
    assert 'platform_mcp_tool_calls_total{tool="platform_status",status="ok"} 1' in rendered
    assert "platform_mcp_tool_duration_seconds_sum" in rendered
