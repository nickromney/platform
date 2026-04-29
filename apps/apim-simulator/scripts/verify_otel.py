from __future__ import annotations

import os
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

import httpx
from smoke_mcp import resolve_tls_verify

DEFAULT_CA_CERT = Path(__file__).resolve().parent.parent / "examples" / "edge" / "certs" / "dev-root-ca.crt"


def _env_true(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _wait_for(
    description: str,
    fn: Callable[[], Any],
    *,
    timeout_seconds: float = 90.0,
    interval_seconds: float = 2.0,
) -> Any:
    deadline = time.time() + timeout_seconds
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            value = fn()
            if value:
                return value
        except Exception as exc:  # noqa: BLE001
            last_error = exc
        time.sleep(interval_seconds)
    if last_error is not None:
        raise RuntimeError(f"{description} failed: {last_error}") from last_error
    raise RuntimeError(f"timed out waiting for {description}")


def _prom_query(client: httpx.Client, datasource_id: int, query: str) -> dict[str, Any]:
    response = client.get(
        f"/api/datasources/proxy/{datasource_id}/api/v1/query",
        params={"query": query},
    )
    response.raise_for_status()
    return response.json()


def _tempo_tag_values(client: httpx.Client, datasource_id: int, tag_name: str) -> list[str]:
    response = client.get(f"/api/datasources/proxy/{datasource_id}/api/search/tag/{tag_name}/values")
    response.raise_for_status()
    return list(response.json().get("tagValues", []))


def _loki_label_values(client: httpx.Client, datasource_id: int, label_name: str) -> list[str]:
    response = client.get(f"/api/datasources/proxy/{datasource_id}/loki/api/v1/label/{label_name}/values")
    response.raise_for_status()
    return list(response.json().get("data", []))


def _service_datasource_ids(client: httpx.Client) -> dict[str, int]:
    response = client.get("/api/datasources")
    response.raise_for_status()
    by_name: dict[str, int] = {}
    for item in response.json():
        uid = item.get("uid")
        if uid:
            by_name[uid] = item["id"]
    return by_name


def _exercise_traffic(apim_base_url: str, verify_todo: bool, todo_subscription_key: str) -> None:
    with httpx.Client(base_url=apim_base_url, timeout=10.0) as client:
        health = client.get("/apim/health")
        health.raise_for_status()
        startup = client.get("/apim/startup")
        startup.raise_for_status()

        if verify_todo:
            headers = {"Ocp-Apim-Subscription-Key": todo_subscription_key}
            todo_health = client.get("/api/health", headers=headers)
            todo_health.raise_for_status()

            list_before = client.get("/api/todos", headers=headers)
            list_before.raise_for_status()

            created = client.post("/api/todos", headers=headers, json={"title": "otel verification"})
            created.raise_for_status()
            todo_id = created.json()["id"]

            updated = client.patch(f"/api/todos/{todo_id}", headers=headers, json={"completed": True})
            updated.raise_for_status()


def main() -> None:
    grafana_base_url = os.getenv("GRAFANA_BASE_URL", "https://lgtm.apim.127.0.0.1.sslip.io:8443")
    grafana_user = os.getenv("GRAFANA_USER", "admin")
    grafana_password = os.getenv("GRAFANA_PASSWORD", "admin")
    apim_base_url = os.getenv("APIM_BASE_URL", "http://localhost:8000")
    verify_todo = _env_true("VERIFY_OTEL_TODO", default=False)
    todo_subscription_key = os.getenv("VERIFY_OTEL_TODO_SUBSCRIPTION_KEY", "todo-demo-key")
    verify_tls = resolve_tls_verify(
        default_ca=DEFAULT_CA_CERT if grafana_base_url.startswith("https://") else None,
        ca_env="VERIFY_OTEL_CA_CERT",
        verify_env="VERIFY_OTEL_VERIFY_TLS",
        insecure_env="VERIFY_OTEL_INSECURE_SKIP_VERIFY",
    )

    _exercise_traffic(apim_base_url, verify_todo, todo_subscription_key)

    with httpx.Client(
        base_url=grafana_base_url,
        auth=(grafana_user, grafana_password),
        timeout=15.0,
        verify=verify_tls,
        trust_env=False,
    ) as client:
        health = _wait_for("Grafana health", lambda: client.get("/api/health").json())
        print(f"Grafana healthy: version={health['version']}")

        datasource_ids = _service_datasource_ids(client)
        prometheus_id = datasource_ids["prometheus"]
        loki_id = datasource_ids["loki"]
        tempo_id = datasource_ids["tempo"]

        apim_metrics = _wait_for(
            "APIM metrics",
            lambda: _prom_query(client, prometheus_id, "apim_gateway_requests_total").get("data", {}).get("result", []),
        )
        print(f"APIM metrics visible: {len(apim_metrics)} series")

        loki_services = _wait_for("APIM logs", lambda: _loki_label_values(client, loki_id, "service_name"))
        if "apim-simulator" not in loki_services:
            raise RuntimeError("Loki does not include apim-simulator logs")
        print(f"Loki services: {', '.join(sorted(loki_services))}")

        tempo_services = _wait_for(
            "APIM traces",
            lambda: _tempo_tag_values(client, tempo_id, "service.name"),
        )
        if "apim-simulator" not in tempo_services:
            raise RuntimeError("Tempo does not include apim-simulator traces")
        print(f"Tempo services: {', '.join(sorted(tempo_services))}")

        if verify_todo:
            todo_metrics = _wait_for(
                "Todo metrics",
                lambda: _prom_query(client, prometheus_id, "todo_api_requests_total").get("data", {}).get("result", []),
            )
            if not any(item.get("metric", {}).get("service_name") == "todo-api" for item in todo_metrics):
                raise RuntimeError("Prometheus does not include todo-api metrics")

            if "todo-api" not in loki_services:
                raise RuntimeError("Loki does not include todo-api logs")
            if "todo-api" not in tempo_services:
                raise RuntimeError("Tempo does not include todo-api traces")

            apim_route_values = _wait_for(
                "APIM route tags in Tempo",
                lambda: _tempo_tag_values(client, tempo_id, "apim.route.name"),
            )
            if not any(value.startswith("Todo API:") for value in apim_route_values):
                raise RuntimeError("Tempo does not include Todo API route tags")

            print(f"Todo metrics visible: {len(todo_metrics)} series")
            print(f"Tempo APIM route tags: {', '.join(sorted(apim_route_values))}")

    print("otel verification passed")


if __name__ == "__main__":
    main()
