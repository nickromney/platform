from __future__ import annotations

import os
import time
from collections.abc import Callable

import httpx

GATEWAY_BASE_URL = os.getenv("SMOKE_HELLO_BASE_URL", "http://127.0.0.1:8000")
KEYCLOAK_BASE_URL = os.getenv("SMOKE_HELLO_KEYCLOAK_BASE_URL", "http://localhost:8180")
MODE = os.getenv("SMOKE_HELLO_MODE", "anonymous")
DEFAULT_ATTEMPTS = int(os.getenv("SMOKE_HELLO_ATTEMPTS", "30"))
DEFAULT_DELAY_SECONDS = float(os.getenv("SMOKE_HELLO_RETRY_DELAY_SECONDS", "1"))


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


def gateway_get(path: str, *, headers: dict[str, str] | None = None) -> httpx.Response:
    with httpx.Client(timeout=10.0) as client:
        return client.get(f"{GATEWAY_BASE_URL}{path}", headers=headers)


def expect_status(path: str, *, status_code: int, headers: dict[str, str] | None = None) -> httpx.Response:
    response = gateway_get(path, headers=headers)
    require(
        response.status_code == status_code,
        f"expected {path} to return {status_code}, got {response.status_code}: {response.text}",
    )
    return response


def fetch_token(*, username: str, password: str) -> str:
    token_url = f"{KEYCLOAK_BASE_URL}/realms/subnet-calculator/protocol/openid-connect/token"
    form = {
        "grant_type": "password",
        "client_id": "frontend-app",
        "username": username,
        "password": password,
    }
    with httpx.Client(timeout=20.0) as client:
        response = client.post(token_url, data=form)
        response.raise_for_status()
        return response.json()["access_token"]


def check_gateway_health() -> None:
    response = gateway_get("/apim/health")
    response.raise_for_status()


def smoke_anonymous() -> None:
    health = gateway_get("/api/health")
    health.raise_for_status()
    require(health.json()["service"] == "hello-api", f"unexpected health payload: {health.text}")

    hello = gateway_get("/api/hello?name=team")
    hello.raise_for_status()
    require(hello.json()["message"] == "hello, team", f"unexpected hello payload: {hello.text}")

    print("hello smoke passed")
    print("- mode: anonymous")
    print("- /api/health: 200")
    print("- /api/hello: 200")


def smoke_subscription() -> None:
    key = os.getenv("SMOKE_HELLO_SUBSCRIPTION_KEY", "hello-demo-key")
    invalid_key = os.getenv("SMOKE_HELLO_INVALID_SUBSCRIPTION_KEY", "hello-demo-key-invalid")

    missing = gateway_get("/api/health")
    require(missing.status_code == 401, f"expected missing subscription 401, got {missing.status_code}: {missing.text}")

    invalid = gateway_get("/api/health", headers={"Ocp-Apim-Subscription-Key": invalid_key})
    require(invalid.status_code == 401, f"expected invalid subscription 401, got {invalid.status_code}: {invalid.text}")

    success = gateway_get("/api/hello?name=subscription", headers={"Ocp-Apim-Subscription-Key": key})
    success.raise_for_status()
    require(success.json()["message"] == "hello, subscription", f"unexpected hello payload: {success.text}")
    require(
        success.headers.get("x-hello-policy") == "applied",
        f"expected x-hello-policy=applied, got {success.headers.get('x-hello-policy')!r}",
    )

    print("hello smoke passed")
    print("- mode: subscription")
    print("- missing subscription: 401")
    print("- invalid subscription: 401")
    print("- valid subscription: 200")


def smoke_oidc(*, require_subscription: bool) -> None:
    user = os.getenv("SMOKE_HELLO_OIDC_USERNAME", "demo@dev.test")
    password = os.getenv("SMOKE_HELLO_OIDC_PASSWORD", "demo-password")
    key = os.getenv("SMOKE_HELLO_SUBSCRIPTION_KEY", "hello-demo-key")

    token = retry_call(lambda: fetch_token(username=user, password=password))

    retry_call(
        lambda: expect_status(
            "/api/hello",
            status_code=401,
            headers={"Ocp-Apim-Subscription-Key": key} if require_subscription else None,
        )
    )

    headers = {"Authorization": f"Bearer {token}"}
    if require_subscription:
        headers["Ocp-Apim-Subscription-Key"] = key

    success = retry_call(lambda: expect_status("/api/hello?name=oidc", status_code=200, headers=headers))
    require(success.json()["message"] == "hello, oidc", f"unexpected hello payload: {success.text}")

    print("hello smoke passed")
    print(f"- mode: {'oidc-subscription' if require_subscription else 'oidc-jwt'}")
    print("- missing bearer: 401")
    print("- valid token: 200")


def main() -> int:
    retry_call(check_gateway_health)

    if MODE == "anonymous":
        smoke_anonymous()
        return 0
    if MODE == "subscription":
        smoke_subscription()
        return 0
    if MODE == "oidc-jwt":
        smoke_oidc(require_subscription=False)
        return 0
    if MODE == "oidc-subscription":
        smoke_oidc(require_subscription=True)
        return 0

    raise SystemExit(f"unsupported SMOKE_HELLO_MODE={MODE!r}")


if __name__ == "__main__":
    raise SystemExit(main())
