from __future__ import annotations

import json
import logging
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Awaitable, Callable, TypeVar

T = TypeVar("T")


class JsonLogFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "severity": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "service.name": "platform-mcp",
        }
        for key, value in record.__dict__.items():
            if key.startswith("platform_"):
                payload[key.removeprefix("platform_")] = value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, sort_keys=True)


def configure_logging() -> logging.Logger:
    logger = logging.getLogger("platform-mcp")
    logger.setLevel(os.environ.get("PLATFORM_MCP_LOG_LEVEL", "INFO").upper())
    logger.propagate = False
    logger.handlers.clear()
    handler = logging.StreamHandler()
    if os.environ.get("PLATFORM_MCP_LOG_FORMAT", "json").lower() == "json":
        handler.setFormatter(JsonLogFormatter())
    logger.addHandler(handler)
    return logger


class MetricsRegistry:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._tool_calls: dict[tuple[str, str], int] = {}
        self._tool_duration_sum: dict[tuple[str, str], float] = {}

    def record_tool_call(self, tool: str, status: str, duration_seconds: float) -> None:
        key = (tool, status)
        with self._lock:
            self._tool_calls[key] = self._tool_calls.get(key, 0) + 1
            self._tool_duration_sum[key] = self._tool_duration_sum.get(key, 0.0) + duration_seconds

    def render(self) -> str:
        lines = [
            "# HELP platform_mcp_tool_calls_total MCP tool calls by tool and status.",
            "# TYPE platform_mcp_tool_calls_total counter",
        ]
        with self._lock:
            for (tool, status), value in sorted(self._tool_calls.items()):
                lines.append(f'platform_mcp_tool_calls_total{{tool="{tool}",status="{status}"}} {value}')
            lines.extend(
                [
                    "# HELP platform_mcp_tool_duration_seconds_sum Total MCP tool call duration in seconds.",
                    "# TYPE platform_mcp_tool_duration_seconds_sum counter",
                ]
            )
            for (tool, status), value in sorted(self._tool_duration_sum.items()):
                lines.append(f'platform_mcp_tool_duration_seconds_sum{{tool="{tool}",status="{status}"}} {value:.6f}')
        lines.append("")
        return "\n".join(lines)


metrics = MetricsRegistry()
logger = configure_logging()


async def observed_tool_call(tool: str, call: Callable[[], Awaitable[dict]]) -> dict:
    started = time.monotonic()
    status = "error"
    try:
        result = await call()
        status = str(result.get("status", "unknown"))
        return result
    finally:
        duration = time.monotonic() - started
        metrics.record_tool_call(tool, status, duration)
        logger.info(
            "mcp tool call completed",
            extra={
                "platform_tool": tool,
                "platform_status": status,
                "platform_duration_ms": round(duration * 1000, 3),
            },
        )


def start_metrics_server() -> ThreadingHTTPServer | None:
    if os.environ.get("PLATFORM_MCP_METRICS_ENABLED", "true").lower() not in {"1", "true", "yes"}:
        return None

    port = int(os.environ.get("PLATFORM_MCP_METRICS_PORT", "9090"))

    class MetricsHandler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if self.path != "/metrics":
                self.send_response(404)
                self.end_headers()
                return
            body = metrics.render().encode("utf-8")
            self.send_response(200)
            self.send_header("content-type", "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, _format: str, *_args: object) -> None:
            return

    server = ThreadingHTTPServer(("0.0.0.0", port), MetricsHandler)
    thread = threading.Thread(target=server.serve_forever, name="platform-mcp-metrics", daemon=True)
    thread.start()
    logger.info("metrics endpoint started", extra={"platform_metrics_port": port})
    return server
