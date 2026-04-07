from __future__ import annotations

import os
import time
from collections.abc import Callable
from typing import Any

import httpx


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


def _loki_query_range(client: httpx.Client, datasource_id: int, query: str) -> list[dict[str, Any]]:
    end_ns = int(time.time() * 1_000_000_000)
    start_ns = end_ns - 5 * 60 * 1_000_000_000
    response = client.get(
        f"/api/datasources/proxy/{datasource_id}/loki/api/v1/query_range",
        params={
            "query": query,
            "start": str(start_ns),
            "end": str(end_ns),
            "limit": "5",
            "direction": "backward",
        },
    )
    response.raise_for_status()
    return list(response.json().get("data", {}).get("result", []))


def _service_datasource_ids(client: httpx.Client) -> dict[str, int]:
    response = client.get("/api/datasources")
    response.raise_for_status()
    by_name: dict[str, int] = {}
    for item in response.json():
        uid = item.get("uid")
        if uid:
            by_name[uid] = item["id"]
    return by_name


def _exercise_traffic(apim_base_url: str) -> None:
    with httpx.Client(base_url=apim_base_url, timeout=10.0) as client:
        client.get("/apim/health").raise_for_status()
        client.get("/apim/startup").raise_for_status()
        client.get("/api/health").raise_for_status()
        client.get("/api/hello", params={"name": "otel"}).raise_for_status()


def main() -> None:
    grafana_base_url = os.getenv("GRAFANA_BASE_URL", "http://localhost:3001")
    grafana_user = os.getenv("GRAFANA_USER", "admin")
    grafana_password = os.getenv("GRAFANA_PASSWORD", "admin")
    apim_base_url = os.getenv("APIM_BASE_URL", "http://localhost:8000")

    _exercise_traffic(apim_base_url)

    with httpx.Client(
        base_url=grafana_base_url,
        auth=(grafana_user, grafana_password),
        timeout=15.0,
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
        hello_metrics = _wait_for(
            "hello-api metrics",
            lambda: (
                _prom_query(client, prometheus_id, 'target_info{service_name="hello-api"}')
                .get("data", {})
                .get("result", [])
            ),
        )
        print(f"APIM metrics visible: {len(apim_metrics)} series")
        print(f"hello-api metrics visible: {len(hello_metrics)} series")

        loki_services = _wait_for("Loki service labels", lambda: _loki_label_values(client, loki_id, "service_name"))
        required_loki_services = {"apim-simulator", "hello-api"}
        missing_loki_services = required_loki_services.difference(loki_services)
        if missing_loki_services:
            missing = ", ".join(sorted(missing_loki_services))
            raise RuntimeError(f"Loki is missing expected services: {missing}")

        hello_logs = _wait_for(
            "hello-api logs",
            lambda: _loki_query_range(client, loki_id, '{service_name="hello-api"}'),
        )
        sample_log = hello_logs[0]["values"][0][1] if hello_logs and hello_logs[0].get("values") else "<none>"
        print(f"Loki services: {', '.join(sorted(loki_services))}")
        print(f"hello-api log sample: {sample_log}")

        tempo_services = _wait_for(
            "Tempo services",
            lambda: _tempo_tag_values(client, tempo_id, "service.name"),
        )
        required_tempo_services = {"apim-simulator", "hello-api"}
        missing_tempo_services = required_tempo_services.difference(tempo_services)
        if missing_tempo_services:
            missing = ", ".join(sorted(missing_tempo_services))
            raise RuntimeError(f"Tempo is missing expected services: {missing}")

        apim_route_values = _wait_for(
            "APIM route tags in Tempo",
            lambda: _tempo_tag_values(client, tempo_id, "apim.route.name"),
        )
        if "hello-api" not in apim_route_values:
            raise RuntimeError("Tempo does not include apim.route.name=hello-api")

        print(f"Tempo services: {', '.join(sorted(tempo_services))}")
        print(f"Tempo APIM route tags: {', '.join(sorted(apim_route_values))}")

    print("hello otel verification passed")


if __name__ == "__main__":
    main()
