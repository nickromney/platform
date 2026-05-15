from __future__ import annotations

import json
import os
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse

BACKEND_ID = os.getenv("AI_MOCK_BACKEND_ID", "local-primary")
REGION = os.getenv("AI_MOCK_REGION", "local")
DEPLOYMENTS = {
    item.strip()
    for item in os.getenv("AI_MOCK_DEPLOYMENTS", "gpt-4o-mini,text-embedding-3-small").split(",")
    if item.strip()
}
TOKEN_LIMIT = int(os.getenv("AI_MOCK_TOKEN_LIMIT", "512"))
DEFAULT_RETRY_AFTER = os.getenv("AI_MOCK_RETRY_AFTER", "1")


def _json_bytes(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, separators=(",", ":")).encode("utf-8")


def _estimate_tokens(value: Any) -> int:
    if value is None:
        return 0
    if isinstance(value, str):
        return max(1, (len(value) + 3) // 4)
    if isinstance(value, list):
        return sum(_estimate_tokens(item) for item in value)
    if isinstance(value, dict):
        return sum(_estimate_tokens(item) for item in value.values())
    return _estimate_tokens(str(value))


def _requested_model(path: str, payload: dict[str, Any]) -> str:
    parts = [part for part in urlparse(path).path.split("/") if part]
    if len(parts) >= 3 and parts[0] == "openai" and parts[1] == "deployments":
        return parts[2]
    model = payload.get("model")
    return model if isinstance(model, str) else ""


class Handler(BaseHTTPRequestHandler):
    server_version = "apim-simulator-ai-mock/0.1"

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("content-length", "0") or "0")
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        if not raw:
            return {}
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            self._write_json(400, {"error": {"message": "request body must be JSON", "type": "invalid_request_error"}})
            raise
        return payload if isinstance(payload, dict) else {}

    def _write_json(self, status_code: int, payload: dict[str, Any], *, retry_after: str | None = None) -> None:
        body = _json_bytes(payload)
        self.send_response(status_code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.send_header("x-ai-mock-backend", BACKEND_ID)
        self.send_header("x-ai-mock-region", REGION)
        if retry_after:
            self.send_header("retry-after", retry_after)
        self.end_headers()
        self.wfile.write(body)

    def _forced_status(self) -> tuple[int, str] | None:
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        fail_backend = (
            self.headers.get("x-ai-mock-fail-backend")
            or query.get("mock_fail_backend", [""])[0]
            or os.getenv("AI_MOCK_FAIL_BACKEND", "")
        ).strip()
        if fail_backend and fail_backend != BACKEND_ID:
            return None

        raw_status = (
            self.headers.get("x-ai-mock-status")
            or query.get("mock_status", [""])[0]
            or query.get("fail_status", [""])[0]
            or os.getenv("AI_MOCK_FORCE_STATUS", "")
        ).strip()
        if not raw_status:
            return None
        try:
            status_code = int(raw_status)
        except ValueError:
            status_code = 500
        if status_code < 400 or status_code > 599:
            status_code = 500
        retry_after = (
            self.headers.get("x-ai-mock-retry-after")
            or query.get("mock_retry_after", [""])[0]
            or os.getenv("AI_MOCK_FORCE_RETRY_AFTER", "")
            or DEFAULT_RETRY_AFTER
        )
        return status_code, retry_after

    def _error_payload(self, status_code: int, message: str, *, error_type: str = "mock_error") -> dict[str, Any]:
        return {
            "error": {
                "message": message,
                "type": error_type,
                "code": status_code,
                "backend": BACKEND_ID,
                "region": REGION,
            }
        }

    def _check_common_failures(self, payload: dict[str, Any]) -> bool:
        forced = self._forced_status()
        if forced is not None:
            status_code, retry_after = forced
            self._write_json(
                status_code,
                self._error_payload(status_code, f"forced {status_code} from {BACKEND_ID}"),
                retry_after=retry_after,
            )
            return True

        model = _requested_model(self.path, payload)
        if model and model not in DEPLOYMENTS:
            self._write_json(
                400,
                self._error_payload(400, f"unsupported deployment {model!r}", error_type="invalid_request_error"),
            )
            return True

        total_tokens = _estimate_tokens(payload)
        if TOKEN_LIMIT > 0 and total_tokens > TOKEN_LIMIT:
            self._write_json(
                429,
                self._error_payload(429, f"estimated token limit exceeded: {total_tokens}>{TOKEN_LIMIT}"),
                retry_after=DEFAULT_RETRY_AFTER,
            )
            return True

        return False

    def _chat_completion(self, payload: dict[str, Any]) -> None:
        if self._check_common_failures(payload):
            return
        prompt_tokens = _estimate_tokens(payload.get("messages", []))
        completion = f"mock chat completion from {BACKEND_ID} in {REGION}"
        completion_tokens = _estimate_tokens(completion)
        self._write_json(
            200,
            {
                "id": f"chatcmpl-{uuid.uuid4().hex[:16]}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": _requested_model(self.path, payload) or "gpt-4o-mini",
                "backend": BACKEND_ID,
                "region": REGION,
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": completion},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {
                    "prompt_tokens": prompt_tokens,
                    "completion_tokens": completion_tokens,
                    "total_tokens": prompt_tokens + completion_tokens,
                },
            },
        )

    def _embeddings(self, payload: dict[str, Any]) -> None:
        if self._check_common_failures(payload):
            return
        prompt_tokens = _estimate_tokens(payload.get("input", ""))
        self._write_json(
            200,
            {
                "object": "list",
                "model": _requested_model(self.path, payload) or "text-embedding-3-small",
                "backend": BACKEND_ID,
                "region": REGION,
                "data": [{"object": "embedding", "index": 0, "embedding": [0.01, 0.02, 0.03, 0.04]}],
                "usage": {"prompt_tokens": prompt_tokens, "total_tokens": prompt_tokens},
            },
        )

    def do_GET(self) -> None:
        if urlparse(self.path).path in {"/health", "/startup"}:
            self._write_json(
                200,
                {"status": "ok", "backend": BACKEND_ID, "region": REGION, "deployments": sorted(DEPLOYMENTS)},
            )
            return
        self._write_json(404, self._error_payload(404, "not found", error_type="not_found"))

    def do_POST(self) -> None:
        try:
            payload = self._read_json()
        except json.JSONDecodeError:
            return
        path = urlparse(self.path).path
        if path == "/v1/chat/completions" or path.endswith("/chat/completions"):
            self._chat_completion(payload)
            return
        if path == "/v1/embeddings" or path.endswith("/embeddings"):
            self._embeddings(payload)
            return
        self._write_json(404, self._error_payload(404, "not found", error_type="not_found"))

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("access-control-allow-origin", "*")
        self.send_header("access-control-allow-methods", "GET,POST,OPTIONS")
        self.send_header("access-control-allow-headers", "*")
        self.end_headers()


def main() -> None:
    port = int(os.getenv("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
