from __future__ import annotations

import ipaddress
import os
from dataclasses import dataclass
from typing import Any, Protocol

import httpx
from mcp.server.fastmcp import FastMCP
from starlette.responses import JSONResponse

from .clients import ApiClient
from .d2 import D2ExecutionError, D2Runner
from .observability import observed_tool_call, start_metrics_server

DEFAULT_IDP_API_BASE_URL = "https://portal-api.127.0.0.1.sslip.io"
DEFAULT_SUBNETCALC_API_BASE_URL = "https://subnetcalc-api.127.0.0.1.sslip.io"
DEFAULT_SENTIMENT_API_BASE_URL = "https://sentiment-api.127.0.0.1.sslip.io"

REQUIRED_TOOL_NAMES = {
    "platform_status",
    "platform_catalog_list",
    "subnetcalc_calculate",
    "sentiment_classify",
    "d2_validate",
    "d2_format",
    "d2_render",
}


class JsonApiClient(Protocol):
    calls: list[tuple[str, str, dict[str, Any] | None]]

    async def get(self, path: str) -> dict[str, Any]: ...

    async def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]: ...


@dataclass(frozen=True)
class RuntimeSettings:
    idp_api_base_url: str = DEFAULT_IDP_API_BASE_URL
    subnetcalc_api_base_url: str = DEFAULT_SUBNETCALC_API_BASE_URL
    sentiment_api_base_url: str = DEFAULT_SENTIMENT_API_BASE_URL
    upstream_bearer_token: str | None = None
    request_timeout_seconds: float = 10
    d2_binary: str = "d2"
    d2_max_source_bytes: int = 32_768
    d2_timeout_seconds: float = 5

    @classmethod
    def from_env(cls) -> "RuntimeSettings":
        return cls(
            idp_api_base_url=os.environ.get("IDP_API_BASE_URL", DEFAULT_IDP_API_BASE_URL).rstrip("/"),
            subnetcalc_api_base_url=os.environ.get(
                "SUBNETCALC_API_BASE_URL",
                DEFAULT_SUBNETCALC_API_BASE_URL,
            ).rstrip("/"),
            sentiment_api_base_url=os.environ.get(
                "SENTIMENT_API_BASE_URL",
                DEFAULT_SENTIMENT_API_BASE_URL,
            ).rstrip("/"),
            upstream_bearer_token=os.environ.get("PLATFORM_MCP_UPSTREAM_BEARER_TOKEN"),
            request_timeout_seconds=float(os.environ.get("PLATFORM_MCP_REQUEST_TIMEOUT_SECONDS", "10")),
            d2_binary=os.environ.get("D2_BINARY", os.environ.get("D2_BIN", "d2")),
            d2_max_source_bytes=int(os.environ.get("D2_MAX_SOURCE_BYTES", "32768")),
            d2_timeout_seconds=float(os.environ.get("D2_TIMEOUT_SECONDS", "5")),
        )


@dataclass(frozen=True)
class HttpServerSettings:
    host: str = "0.0.0.0"
    port: int = 8080
    streamable_http_path: str = "/mcp"

    @classmethod
    def from_env(cls) -> "HttpServerSettings":
        return cls(
            host=os.environ.get("PLATFORM_MCP_HOST", os.environ.get("HOST", "0.0.0.0")),
            port=int(os.environ.get("PLATFORM_MCP_PORT", os.environ.get("PORT", "8080"))),
            streamable_http_path=os.environ.get("PLATFORM_MCP_PATH", "/mcp"),
        )


@dataclass
class ToolRuntime:
    settings: RuntimeSettings
    idp_client: JsonApiClient
    subnetcalc_client: JsonApiClient
    sentiment_client: JsonApiClient
    d2_runner: Any

    @classmethod
    def from_env(cls) -> "ToolRuntime":
        settings = RuntimeSettings.from_env()
        client_kwargs = {
            "timeout_seconds": settings.request_timeout_seconds,
            "bearer_token": settings.upstream_bearer_token,
        }
        return cls(
            settings=settings,
            idp_client=ApiClient(settings.idp_api_base_url, **client_kwargs),
            subnetcalc_client=ApiClient(settings.subnetcalc_api_base_url, **client_kwargs),
            sentiment_client=ApiClient(settings.sentiment_api_base_url, **client_kwargs),
            d2_runner=D2Runner(
                binary=settings.d2_binary,
                max_source_bytes=settings.d2_max_source_bytes,
                timeout_seconds=settings.d2_timeout_seconds,
            ),
        )

    async def platform_status(self) -> dict[str, Any]:
        try:
            data = await self.idp_client.get("/api/v1/status")
            return ok("platform_status", data, ["Call platform_catalog_list to discover shipped applications."])
        except Exception as exc:
            return exception_result("IDP_STATUS_FAILED", "Could not read platform status.", exc)

    async def platform_catalog_list(self) -> dict[str, Any]:
        try:
            data = await self.idp_client.get("/api/v1/catalog/apps")
            return ok("platform_catalog_list", data, ["Use subnetcalc_calculate or sentiment_classify for app APIs."])
        except Exception as exc:
            return exception_result("IDP_CATALOG_FAILED", "Could not read platform catalog.", exc)

    async def subnetcalc_calculate(self, cidr: str, mode: str = "Azure") -> dict[str, Any]:
        try:
            network = ipaddress.ip_network(cidr, strict=False)
        except ValueError as exc:
            return error_result(
                "SUBNETCALC_INVALID_CIDR",
                "cidr must be valid IPv4 or IPv6 CIDR notation.",
                data={"cidr": cidr},
                next_actions=["Retry with a value like 192.168.1.0/24 or 2001:db8::/64."],
                exception=exc,
            )

        if network.version == 4:
            path = "/api/v1/ipv4/subnet-info"
            payload = {"network": str(network), "mode": mode}
        else:
            path = "/api/v1/ipv6/subnet-info"
            payload = {"network": str(network)}

        try:
            data = await self.subnetcalc_client.post(path, payload)
            return ok("subnetcalc_calculate", data, ["Use d2_render to visualize network relationships."])
        except Exception as exc:
            return exception_result("SUBNETCALC_REQUEST_FAILED", "Subnet calculator API request failed.", exc)

    async def sentiment_classify(self, text: str) -> dict[str, Any]:
        if not text.strip():
            return error_result(
                "SENTIMENT_EMPTY_TEXT",
                "text must contain non-whitespace content.",
                next_actions=["Retry with the comment or sentence to classify."],
            )

        try:
            data = await self.sentiment_client.post("/api/v1/comments", {"text": text})
            return ok("sentiment_classify", data, ["Compare the label and confidence before acting on the result."])
        except Exception as exc:
            return exception_result("SENTIMENT_REQUEST_FAILED", "Sentiment API request failed.", exc)

    async def d2_validate(self, source: str) -> dict[str, Any]:
        try:
            data = await self.d2_runner.validate(source)
            return ok("d2_validate", data, ["Call d2_render with output_format='svg' to produce an artifact."])
        except D2ExecutionError as exc:
            return d2_error_result(exc)

    async def d2_format(self, source: str) -> dict[str, Any]:
        try:
            data = await self.d2_runner.format(source)
            return ok("d2_format", data, ["Call d2_validate on the formatted source before rendering."])
        except D2ExecutionError as exc:
            return d2_error_result(exc)

    async def d2_render(self, source: str, output_format: str = "svg", layout: str = "elk") -> dict[str, Any]:
        try:
            data = await self.d2_runner.render(source, output_format=output_format, layout=layout)
            return ok("d2_render", data, ["Embed the returned SVG content where the caller can inspect it."])
        except D2ExecutionError as exc:
            return d2_error_result(exc)


def ok(tool: str, data: dict[str, Any], next_actions: list[str]) -> dict[str, Any]:
    return {"status": "ok", "tool": tool, "data": data, "next_actions": next_actions}


def error_result(
    code: str,
    message: str,
    *,
    data: dict[str, Any] | None = None,
    recoverable: bool = True,
    next_actions: list[str] | None = None,
    exception: Exception | None = None,
) -> dict[str, Any]:
    payload = {
        "status": "error",
        "error": {
            "code": code,
            "message": message,
            "recoverable": recoverable,
            "data": data or {},
        },
        "next_actions": next_actions or ["Check the error data, fix the input or runtime config, then retry."],
    }
    if exception is not None:
        payload["error"]["data"]["exception"] = type(exception).__name__
    return payload


def exception_result(code: str, message: str, exc: Exception) -> dict[str, Any]:
    data: dict[str, Any] = {"exception": type(exc).__name__}
    if isinstance(exc, httpx.HTTPStatusError):
        data.update({"status_code": exc.response.status_code, "response": exc.response.text[:1000]})
    else:
        data["detail"] = str(exc)
    return error_result(code, message, data=data)


def d2_error_result(exc: D2ExecutionError) -> dict[str, Any]:
    return error_result(
        exc.code,
        exc.message,
        data=exc.data,
        recoverable=exc.recoverable,
        next_actions=[
            "Confirm the D2 binary is present in the container.",
            "Reduce the diagram source size or simplify the graph if limits were hit.",
            "Retry with output_format='svg' and layout='elk' unless you need layout='dagre'.",
        ],
    )


def create_mcp_server(
    runtime: ToolRuntime | None = None,
    http_settings: HttpServerSettings | None = None,
) -> FastMCP:
    tools = runtime or ToolRuntime.from_env()
    server_settings = http_settings or HttpServerSettings.from_env()
    mcp = FastMCP(
        "platform-mcp",
        host=server_settings.host,
        port=server_settings.port,
        streamable_http_path=server_settings.streamable_http_path,
        stateless_http=True,
        json_response=True,
    )

    @mcp.custom_route("/health", methods=["GET"], include_in_schema=False)
    async def health_check(_request: object) -> JSONResponse:
        return JSONResponse({"status": "ok", "service": "platform-mcp"})

    @mcp.tool()
    async def platform_status() -> dict[str, Any]:
        """Read platform health through the IDP API."""
        return await observed_tool_call("platform_status", tools.platform_status)

    @mcp.tool()
    async def platform_catalog_list() -> dict[str, Any]:
        """List platform applications through the IDP API."""
        return await observed_tool_call("platform_catalog_list", tools.platform_catalog_list)

    @mcp.tool()
    async def subnetcalc_calculate(cidr: str, mode: str = "Azure") -> dict[str, Any]:
        """Calculate subnet details for IPv4 or IPv6 CIDR input."""
        return await observed_tool_call("subnetcalc_calculate", lambda: tools.subnetcalc_calculate(cidr=cidr, mode=mode))

    @mcp.tool()
    async def sentiment_classify(text: str) -> dict[str, Any]:
        """Classify a piece of text with the sentiment API."""
        return await observed_tool_call("sentiment_classify", lambda: tools.sentiment_classify(text=text))

    @mcp.tool()
    async def d2_validate(source: str) -> dict[str, Any]:
        """Validate D2 source without returning a rendered artifact."""
        return await observed_tool_call("d2_validate", lambda: tools.d2_validate(source=source))

    @mcp.tool()
    async def d2_format(source: str) -> dict[str, Any]:
        """Format D2 source using the pinned D2 runtime."""
        return await observed_tool_call("d2_format", lambda: tools.d2_format(source=source))

    @mcp.tool()
    async def d2_render(source: str, output_format: str = "svg", layout: str = "elk") -> dict[str, Any]:
        """Render D2 source to SVG with bounded execution."""
        return await observed_tool_call(
            "d2_render",
            lambda: tools.d2_render(source=source, output_format=output_format, layout=layout),
        )

    return mcp


def main() -> None:
    start_metrics_server()
    create_mcp_server().run(transport="streamable-http")


if __name__ == "__main__":
    main()
