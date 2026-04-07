from __future__ import annotations

import json
import os
import time
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import parse_qsl, urlsplit

import httpx

APIM_BASE_URL = os.environ.get("TODO_HAR_APIM_BASE_URL", "http://127.0.0.1:8000")
FRONTEND_BASE_URL = os.environ.get("TODO_HAR_FRONTEND_BASE_URL", "http://127.0.0.1:3000")
SUBSCRIPTION_KEY = os.environ.get("TODO_HAR_SUBSCRIPTION_KEY", "todo-demo-key")
INVALID_SUBSCRIPTION_KEY = os.environ.get("TODO_HAR_INVALID_SUBSCRIPTION_KEY", "todo-demo-key-invalid")
OUTPUT_PATH = Path(
    os.environ.get(
        "TODO_HAR_OUTPUT_PATH",
        "examples/todo-app/api-clients/proxyman/todo-through-apim.har",
    )
)


@dataclass
class CapturedExchange:
    started_at: datetime
    duration_ms: int
    request_method: str
    request_url: str
    request_headers: list[tuple[str, str]]
    request_body: str | None
    response: httpx.Response


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


def capture(
    client: httpx.Client,
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    json_body: dict[str, object] | None = None,
) -> CapturedExchange:
    payload = json.dumps(json_body) if json_body is not None else None
    request_headers = list((headers or {}).items())
    started_at = datetime.now(UTC)
    started_perf = time.perf_counter()
    response = client.request(method, url, headers=headers, json=json_body)
    duration_ms = round((time.perf_counter() - started_perf) * 1000)
    return CapturedExchange(
        started_at=started_at,
        duration_ms=duration_ms,
        request_method=method,
        request_url=url,
        request_headers=request_headers,
        request_body=payload,
        response=response,
    )


def header_items(headers: httpx.Headers) -> list[dict[str, str]]:
    return [{"name": key, "value": value} for key, value in headers.multi_items()]


def header_pairs(headers: list[tuple[str, str]]) -> list[dict[str, str]]:
    return [{"name": key, "value": value} for key, value in headers]


def query_items(url: str) -> list[dict[str, str]]:
    query = urlsplit(url).query
    return [{"name": key, "value": value} for key, value in parse_qsl(query, keep_blank_values=True)]


def response_content(response: httpx.Response) -> dict[str, object]:
    text = response.text
    mime_type = response.headers.get("content-type", "application/octet-stream")
    return {
        "size": len(response.content),
        "mimeType": mime_type,
        "text": text,
    }


def to_har_entry(exchange: CapturedExchange) -> dict[str, object]:
    response = exchange.response
    return {
        "startedDateTime": exchange.started_at.isoformat().replace("+00:00", "Z"),
        "time": exchange.duration_ms,
        "request": {
            "method": exchange.request_method,
            "url": exchange.request_url,
            "httpVersion": "HTTP/1.1",
            "cookies": [],
            "headers": header_pairs(exchange.request_headers),
            "queryString": query_items(exchange.request_url),
            "headersSize": -1,
            "bodySize": len(exchange.request_body.encode("utf-8")) if exchange.request_body is not None else 0,
            **(
                {
                    "postData": {
                        "mimeType": "application/json",
                        "text": exchange.request_body,
                    }
                }
                if exchange.request_body is not None
                else {}
            ),
        },
        "response": {
            "status": response.status_code,
            "statusText": response.reason_phrase,
            "httpVersion": "HTTP/1.1",
            "cookies": [],
            "headers": header_items(response.headers),
            "content": response_content(response),
            "redirectURL": "",
            "headersSize": -1,
            "bodySize": len(response.content),
        },
        "cache": {},
        "timings": {
            "blocked": 0,
            "dns": -1,
            "connect": -1,
            "ssl": -1,
            "send": 0,
            "wait": exchange.duration_ms,
            "receive": 0,
        },
    }


def main() -> None:
    wait_for(f"{APIM_BASE_URL}/apim/startup", "APIM startup")
    wait_for(FRONTEND_BASE_URL, "todo frontend")

    title = f"todo-har-{uuid.uuid4().hex[:8]}"
    exchanges: list[CapturedExchange] = []

    with httpx.Client(timeout=10.0) as client:
        exchanges.append(
            capture(
                client,
                "GET",
                f"{APIM_BASE_URL}/api/health",
                headers={
                    "Accept": "application/json",
                    "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
                },
            )
        )
        exchanges.append(
            capture(
                client,
                "OPTIONS",
                f"{APIM_BASE_URL}/api/todos",
                headers={
                    "Origin": FRONTEND_BASE_URL,
                    "Access-Control-Request-Method": "POST",
                    "Access-Control-Request-Headers": "content-type,ocp-apim-subscription-key",
                },
            )
        )
        exchanges.append(
            capture(
                client,
                "GET",
                f"{APIM_BASE_URL}/api/todos",
                headers={"Accept": "application/json"},
            )
        )
        exchanges.append(
            capture(
                client,
                "GET",
                f"{APIM_BASE_URL}/api/todos",
                headers={
                    "Accept": "application/json",
                    "Ocp-Apim-Subscription-Key": INVALID_SUBSCRIPTION_KEY,
                },
            )
        )
        exchanges.append(
            capture(
                client,
                "POST",
                f"{APIM_BASE_URL}/api/todos",
                headers={
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
                },
                json_body={"title": title},
            )
        )
        created = exchanges[-1].response.json()
        exchanges.append(
            capture(
                client,
                "PATCH",
                f"{APIM_BASE_URL}/api/todos/{created['id']}",
                headers={
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
                },
                json_body={"completed": True},
            )
        )
        exchanges.append(
            capture(
                client,
                "GET",
                f"{APIM_BASE_URL}/api/todos",
                headers={
                    "Accept": "application/json",
                    "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
                },
            )
        )

    for exchange in exchanges:
        if exchange.response.status_code >= 500:
            raise SystemExit(
                f"unexpected upstream failure while building HAR: {exchange.request_method} {exchange.request_url}"
            )

    har_payload = {
        "log": {
            "version": "1.2",
            "creator": {"name": "apim-simulator", "version": "0.1.0"},
            "browser": {"name": "todo-through-apim-exporter", "version": "1.0"},
            "pages": [],
            "entries": [to_har_entry(exchange) for exchange in exchanges],
        }
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(har_payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
