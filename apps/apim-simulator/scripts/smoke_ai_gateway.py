from __future__ import annotations

import os
import time
from collections.abc import Callable
from typing import Any

import httpx

GATEWAY_BASE_URL = os.getenv("SMOKE_AI_GATEWAY_BASE_URL", "http://127.0.0.1:8000").rstrip("/")
DEFAULT_ATTEMPTS = int(os.getenv("SMOKE_AI_GATEWAY_ATTEMPTS", "30"))
DEFAULT_DELAY_SECONDS = float(os.getenv("SMOKE_AI_GATEWAY_RETRY_DELAY_SECONDS", "1"))
REQUIRE_FALLBACK = os.getenv("SMOKE_AI_GATEWAY_REQUIRE_FALLBACK", "true").lower() == "true"


def retry_call[T](
    operation: Callable[[], T],
    *,
    attempts: int = DEFAULT_ATTEMPTS,
    delay_seconds: float = DEFAULT_DELAY_SECONDS,
) -> T:
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            return operation()
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            if attempt == attempts:
                raise
            time.sleep(delay_seconds)
    if last_error is not None:
        raise last_error
    raise RuntimeError("retry_call exhausted without executing operation")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def request(method: str, path: str, **kwargs: Any) -> httpx.Response:
    with httpx.Client(timeout=15.0, trust_env=False) as client:
        return client.request(method, f"{GATEWAY_BASE_URL}{path}", **kwargs)


def expect_status(method: str, path: str, status_code: int, **kwargs: Any) -> httpx.Response:
    response = request(method, path, **kwargs)
    require(
        response.status_code == status_code,
        f"expected {method} {path} to return {status_code}, got {response.status_code}: {response.text}",
    )
    return response


def chat_payload(*, model: str = "gpt-4o-mini", content: str = "hello from the smoke test") -> dict[str, Any]:
    return {"model": model, "messages": [{"role": "user", "content": content}]}


def check_health() -> None:
    expect_status("GET", "/apim/health", 200)
    backend_health = expect_status("GET", "/ai/health", 200).json()
    require(backend_health.get("status") == "ok", f"unexpected backend health payload: {backend_health}")


def check_primary_success() -> dict[str, Any]:
    response = expect_status("POST", "/ai/v1/chat/completions", 200, json=chat_payload())
    payload = response.json()
    require(payload.get("backend") == "local-primary", f"expected primary backend, got {payload}")
    require(payload.get("region") == "local-eu", f"expected primary region, got {payload}")
    require(payload.get("usage", {}).get("total_tokens", 0) > 0, f"missing usage.total_tokens: {payload}")
    return payload


def check_fallback_on_429() -> dict[str, Any] | None:
    headers = {
        "x-ai-mock-fail-backend": "local-primary",
        "x-ai-mock-status": "429",
        "x-ai-mock-retry-after": "1",
    }
    response = request("POST", "/ai/v1/chat/completions", headers=headers, json=chat_payload(content="force fallback"))
    if response.status_code != 200:
        message = f"expected forced primary 429 to fall back to secondary, got {response.status_code}: {response.text}"
        if REQUIRE_FALLBACK:
            raise RuntimeError(message)
        print(f"- fallback on forced 429: skipped ({message})")
        return None
    payload = response.json()
    require(payload.get("backend") == "local-secondary", f"expected secondary backend fallback, got {payload}")
    require(payload.get("usage", {}).get("total_tokens", 0) > 0, f"missing usage.total_tokens: {payload}")
    return payload


def check_unsupported_deployment() -> None:
    response = expect_status(
        "POST",
        "/ai/v1/chat/completions",
        400,
        json=chat_payload(model="unsupported-local-deployment"),
    )
    payload = response.json()
    detail = str(payload.get("detail") or payload.get("error", {}).get("message") or "")
    require(
        "unsupported" in detail or "No AI gateway route" in detail,
        f"unexpected unsupported deployment error: {response.text}",
    )


def check_token_limit() -> bool:
    response = request(
        "POST",
        "/ai/v1/chat/completions",
        json=chat_payload(content="token-limit " * 3000),
    )
    if response.status_code == 429:
        require(response.headers.get("retry-after"), "expected retry-after on token limit 429")
        return True
    require(response.status_code == 200, f"expected token limit 429 or non-enforced 200, got {response.status_code}")
    return False


def main() -> int:
    retry_call(check_health)
    primary = check_primary_success()
    fallback = check_fallback_on_429()
    check_unsupported_deployment()
    token_limit_enforced = check_token_limit()

    print("AI gateway smoke passed")
    print(f"- health: 200 via {GATEWAY_BASE_URL}")
    print(f"- primary success: {primary['backend']} / {primary['region']}")
    if fallback is not None:
        print(f"- fallback on forced 429: {fallback['backend']} / {fallback['region']}")
    print("- unsupported deployment: 400")
    print(f"- token limit: {'429' if token_limit_enforced else 'not enforced by this runtime'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
