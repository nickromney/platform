from __future__ import annotations

import os
import time
import uuid

import httpx

APIM_BASE_URL = os.environ.get("TODO_APIM_BASE_URL", "http://127.0.0.1:8000")
FRONTEND_BASE_URL = os.environ.get("TODO_FRONTEND_BASE_URL", "http://127.0.0.1:3000")
SUBSCRIPTION_KEY = os.environ.get("TODO_SUBSCRIPTION_KEY", "todo-demo-key")
INVALID_SUBSCRIPTION_KEY = os.environ.get("TODO_INVALID_SUBSCRIPTION_KEY", "todo-demo-key-invalid")


def wait_for(url: str, label: str, timeout_seconds: float = 60.0) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            response = httpx.get(url, timeout=5.0)
            if response.is_success:
                return
        except httpx.HTTPError:
            pass
        time.sleep(1)
    raise SystemExit(f"timed out waiting for {label}: {url}")


def assert_header(response: httpx.Response, name: str, expected: str) -> None:
    actual = response.headers.get(name)
    if actual != expected:
        raise SystemExit(f"expected response header {name}={expected!r}, got {actual!r}")


def main() -> None:
    title = f"todo-smoke-{uuid.uuid4().hex[:8]}"

    wait_for(f"{APIM_BASE_URL}/apim/startup", "APIM startup")
    wait_for(FRONTEND_BASE_URL, "todo frontend")

    frontend_html = httpx.get(FRONTEND_BASE_URL, timeout=5.0)
    frontend_html.raise_for_status()
    if "Gateway-Proof Todo" not in frontend_html.text:
        raise SystemExit("frontend page did not render expected title")

    health = httpx.get(
        f"{APIM_BASE_URL}/api/health",
        headers={"Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY},
        timeout=5.0,
    )
    health.raise_for_status()
    assert health.json()["status"] == "ok"
    assert_header(health, "x-todo-demo-policy", "applied")

    preflight = httpx.options(
        f"{APIM_BASE_URL}/api/todos",
        headers={
            "Origin": FRONTEND_BASE_URL,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type,ocp-apim-subscription-key",
        },
        timeout=5.0,
    )
    if preflight.status_code != 200:
        raise SystemExit(f"expected CORS preflight 200, got {preflight.status_code}")
    if preflight.headers.get("access-control-allow-origin") != FRONTEND_BASE_URL:
        raise SystemExit("CORS preflight did not echo the allowed frontend origin")

    missing = httpx.get(f"{APIM_BASE_URL}/api/todos", timeout=5.0)
    if missing.status_code != 401 or missing.json().get("detail") != "Missing subscription key":
        raise SystemExit("missing subscription key did not return the expected 401 response")

    invalid = httpx.get(
        f"{APIM_BASE_URL}/api/todos",
        headers={"Ocp-Apim-Subscription-Key": INVALID_SUBSCRIPTION_KEY},
        timeout=5.0,
    )
    if invalid.status_code != 401 or invalid.json().get("detail") != "Invalid subscription key":
        raise SystemExit("invalid subscription key did not return the expected 401 response")

    create = httpx.post(
        f"{APIM_BASE_URL}/api/todos",
        headers={"Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY},
        json={"title": title},
        timeout=5.0,
    )
    create.raise_for_status()
    created = create.json()
    assert created["title"] == title
    assert created["completed"] is False
    assert_header(create, "x-todo-demo-policy", "applied")

    listed = httpx.get(
        f"{APIM_BASE_URL}/api/todos",
        headers={"Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY},
        timeout=5.0,
    )
    listed.raise_for_status()
    items = listed.json()["items"]
    matched = next((item for item in items if item["id"] == created["id"]), None)
    if matched is None or matched["title"] != title:
        raise SystemExit("created todo did not appear in the APIM-backed list response")

    updated = httpx.patch(
        f"{APIM_BASE_URL}/api/todos/{created['id']}",
        headers={"Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY},
        json={"completed": True},
        timeout=5.0,
    )
    updated.raise_for_status()
    if updated.json()["completed"] is not True:
        raise SystemExit("todo update through APIM did not persist completion state")
    assert_header(updated, "x-todo-demo-policy", "applied")

    print("todo smoke passed")


if __name__ == "__main__":
    main()
