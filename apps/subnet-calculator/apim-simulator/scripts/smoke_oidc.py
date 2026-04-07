#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import time
from collections.abc import Callable

import httpx

KEYCLOAK_BASE_URL = "http://localhost:8180"
REALM = "subnet-calculator"
CLIENT_ID = "frontend-app"
GATEWAY_BASE_URL = "http://localhost:8000"
DEFAULT_ATTEMPTS = int(os.getenv("SMOKE_OIDC_ATTEMPTS", "20"))
DEFAULT_DELAY_SECONDS = float(os.getenv("SMOKE_OIDC_RETRY_DELAY_SECONDS", "1"))


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
        except Exception as exc:
            last_error = exc
            if attempt == attempts:
                raise
            time.sleep(delay_seconds)

    if last_error is not None:
        raise last_error
    raise RuntimeError("retry_call exhausted without executing operation")


def fetch_token(username: str, password: str) -> str:
    token_url = f"{KEYCLOAK_BASE_URL}/realms/{REALM}/protocol/openid-connect/token"
    form = {
        "grant_type": "password",
        "client_id": CLIENT_ID,
        "username": username,
        "password": password,
    }
    with httpx.Client(timeout=20.0) as client:
        response = client.post(token_url, data=form)
        response.raise_for_status()
        return response.json()["access_token"]


def gateway_get(path: str, *, token: str, subscription_key: str) -> httpx.Response:
    headers = {
        "Authorization": f"Bearer {token}",
        "Ocp-Apim-Subscription-Key": subscription_key,
    }
    with httpx.Client(timeout=20.0) as client:
        return client.get(f"{GATEWAY_BASE_URL}{path}", headers=headers)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def check_gateway_health() -> None:
    with httpx.Client(timeout=10.0) as client:
        health = client.get(f"{GATEWAY_BASE_URL}/apim/health")
        health.raise_for_status()


def main() -> int:
    try:
        retry_call(check_gateway_health)

        user_token = retry_call(lambda: fetch_token("demo@dev.test", "demo-password"))
        admin_token = retry_call(lambda: fetch_token("demo@admin.test", "demo-password"))

        user_resp = retry_call(lambda: gateway_get("/api/echo", token=user_token, subscription_key="oidc-demo-key"))
        require(user_resp.status_code == 200, f"/api/echo expected 200, got {user_resp.status_code}: {user_resp.text}")
        user_payload = user_resp.json()
        require(user_payload["path"] == "/api/echo", f"unexpected proxied path: {json.dumps(user_payload)}")

        denied_resp = retry_call(
            lambda: gateway_get("/admin/api/echo", token=user_token, subscription_key="oidc-demo-key")
        )
        require(
            denied_resp.status_code == 403,
            f"/admin/api/echo for demo user expected 403, got {denied_resp.status_code}: {denied_resp.text}",
        )

        admin_resp = retry_call(
            lambda: gateway_get("/admin/api/echo", token=admin_token, subscription_key="oidc-admin-key")
        )
        require(
            admin_resp.status_code == 200,
            f"/admin/api/echo for admin user expected 200, got {admin_resp.status_code}: {admin_resp.text}",
        )

        print("OIDC smoke passed")
        print("- user route: 200")
        print("- admin route with user token: 403")
        print("- admin route with admin token: 200")
        return 0
    except Exception as exc:
        sys.stderr.write(f"OIDC smoke failed: {exc}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
