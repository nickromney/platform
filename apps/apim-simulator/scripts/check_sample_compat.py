#!/usr/bin/env python3
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx
from fastapi.testclient import TestClient

from app.config import GatewayConfig, RouteConfig
from app.main import create_app
from app.urls import http_url

FIXTURE_ROOT = Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "apim_samples"


@dataclass(frozen=True)
class FixtureEntry:
    id: str
    source: str
    status: str
    notes: str


def _load_manifest() -> list[FixtureEntry]:
    manifest_path = FIXTURE_ROOT / "manifest.json"
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    return [FixtureEntry(**entry) for entry in data]


def _load_fixture_file(fixture_id: str, name: str) -> Any:
    path = FIXTURE_ROOT / fixture_id / name
    if name.endswith(".json"):
        return json.loads(path.read_text(encoding="utf-8"))
    return path.read_text(encoding="utf-8")


def _decode_request_body(content: bytes) -> str:
    if not content:
        return ""
    try:
        return content.decode("utf-8")
    except UnicodeDecodeError:
        return content.decode("utf-8", errors="replace")


def _assert_subset(expected: Any, actual: Any, *, path: str = "root") -> None:
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            raise AssertionError(f"{path}: expected dict, got {type(actual).__name__}")
        for key, expected_value in expected.items():
            if key not in actual:
                raise AssertionError(f"{path}: missing key {key!r}")
            _assert_subset(expected_value, actual[key], path=f"{path}.{key}")
        return

    if isinstance(expected, list):
        if not isinstance(actual, list):
            raise AssertionError(f"{path}: expected list, got {type(actual).__name__}")
        if len(expected) != len(actual):
            raise AssertionError(f"{path}: expected list length {len(expected)}, got {len(actual)}")
        for index, expected_value in enumerate(expected):
            _assert_subset(expected_value, actual[index], path=f"{path}[{index}]")
        return

    if expected != actual:
        raise AssertionError(f"{path}: expected {expected!r}, got {actual!r}")


def _matches_mock(req: httpx.Request, match: dict[str, Any]) -> bool:
    if "method" in match and req.method.upper() != str(match["method"]).upper():
        return False
    if "url" in match and str(req.url) != str(match["url"]):
        return False
    if "path" in match and req.url.path != str(match["path"]):
        return False
    return True


def _build_mock_response(spec: dict[str, Any]) -> httpx.Response:
    status_code = int(spec.get("status_code") or 200)
    headers = spec.get("headers") or {}
    if "json" in spec:
        return httpx.Response(status_code, headers=headers, json=spec["json"])
    if "text" in spec:
        return httpx.Response(status_code, headers=headers, text=str(spec["text"]))
    return httpx.Response(status_code, headers=headers, content=(spec.get("body") or "").encode("utf-8"))


def _run_fixture(entry: FixtureEntry) -> None:
    policy_xml = _load_fixture_file(entry.id, "policy.xml")
    request_spec = _load_fixture_file(entry.id, "request.json")
    expected = _load_fixture_file(entry.id, "expected.json")

    captured_requests: list[dict[str, Any]] = []
    mock_responses = list(request_spec.get("mock_responses") or [])

    def handler(req: httpx.Request) -> httpx.Response:
        captured_requests.append(
            {
                "method": req.method,
                "url": str(req.url),
                "path": req.url.path,
                "query": dict(req.url.params),
                "headers": {key.lower(): value for key, value in req.headers.items()},
                "body": _decode_request_body(req.content),
            }
        )
        for index, item in enumerate(mock_responses):
            match = item.get("match") or {}
            if _matches_mock(req, match):
                response_spec = item.get("response") or {}
                mock_responses.pop(index)
                return _build_mock_response(response_spec)
        return httpx.Response(200, json={"ok": True})

    config_overrides = dict(request_spec.get("config", {}))
    path_prefix = config_overrides.pop("path_prefix", "/sample")
    upstream_path_prefix = config_overrides.pop("upstream_path_prefix", "")
    upstream_base_url = config_overrides.pop("upstream_base_url", http_url("upstream"))
    allow_anonymous = config_overrides.pop("allow_anonymous", True)
    policy_fragments = config_overrides.pop("policy_fragments", {})

    app = create_app(
        config=GatewayConfig(
            allow_anonymous=allow_anonymous,
            policy_fragments=policy_fragments,
            routes=[
                RouteConfig(
                    name="fixture",
                    path_prefix=path_prefix,
                    upstream_base_url=upstream_base_url,
                    upstream_path_prefix=upstream_path_prefix,
                    policies_xml=policy_xml,
                )
            ],
            **config_overrides,
        ),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )

    steps = request_spec.get("steps")
    actual_steps: list[dict[str, Any]] = []

    if steps is None:
        steps = [
            {
                "method": request_spec.get("method", "GET"),
                "path": request_spec["path"],
                "query": request_spec.get("query", {}),
                "headers": request_spec.get("headers", {}),
                "body": request_spec.get("body", ""),
            }
        ]

    with TestClient(app) as client:
        for step in steps:
            response = client.request(
                step.get("method", "GET"),
                step["path"],
                params=step.get("query", {}),
                headers=step.get("headers", {}),
                content=(step.get("body") or "").encode("utf-8"),
            )
            actual_step: dict[str, Any] = {
                "status_code": response.status_code,
                "headers": {key.lower(): value for key, value in response.headers.items()},
                "body_text": response.text,
            }
            if response.headers.get("content-type", "").startswith("application/json"):
                actual_step["json"] = response.json()
            actual_steps.append(actual_step)

    actual: dict[str, Any]
    if len(actual_steps) == 1 and "steps" not in expected:
        actual = {**actual_steps[0], "upstream": captured_requests[-1] if captured_requests else None}
    else:
        actual = {
            "steps": actual_steps,
            "upstream_call_count": len(captured_requests),
            "upstream_requests": captured_requests,
        }

    _assert_subset(expected, actual, path=entry.id)


def run_checks() -> dict[str, Any]:
    supported: list[str] = []
    adapted: list[str] = []
    unsupported: list[FixtureEntry] = []
    failures: list[str] = []

    for entry in _load_manifest():
        if entry.status == "unsupported":
            unsupported.append(entry)
            continue

        try:
            _run_fixture(entry)
        except Exception as exc:
            failures.append(f"{entry.id}: {exc}")
            continue

        if entry.status == "supported":
            supported.append(entry.id)
        elif entry.status == "adapted":
            adapted.append(entry.id)
        else:
            failures.append(f"{entry.id}: unknown status {entry.status}")

    return {
        "supported": supported,
        "adapted": adapted,
        "unsupported": unsupported,
        "failures": failures,
    }


def main() -> int:
    result = run_checks()

    if result["supported"]:
        print(f"Supported fixtures passed: {', '.join(result['supported'])}")
    if result["adapted"]:
        print(f"Adapted fixtures passed: {', '.join(result['adapted'])}")
    if result["unsupported"]:
        print("Unsupported fixtures:")
        for entry in result["unsupported"]:
            print(f"- {entry.id}: {entry.notes}")
    if result["failures"]:
        print("Compatibility failures:")
        for failure in result["failures"]:
            print(f"- {failure}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
