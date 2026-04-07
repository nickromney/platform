#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

import httpx


def _load_cases(path: str) -> list[dict[str, Any]]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError("Verification cases must be a JSON array")
    return [item for item in data if isinstance(item, dict)]


def _response_body(response: httpx.Response) -> Any:
    content_type = response.headers.get("content-type", "")
    if content_type.startswith("application/json"):
        try:
            return response.json()
        except json.JSONDecodeError:
            return response.text
    return response.text


def _selected_headers(response: httpx.Response, names: list[str]) -> dict[str, str]:
    headers = {key.lower(): value for key, value in response.headers.items()}
    return {name.lower(): headers.get(name.lower(), "") for name in names}


def main() -> int:
    cases_path = os.environ.get("VERIFY_CASES", "").strip()
    if not cases_path:
        print("VERIFY_CASES must point to a JSON file describing replay cases.", file=sys.stderr)
        return 2

    simulator_base_url = os.environ.get("SIMULATOR_BASE_URL", "http://localhost:8000").rstrip("/")
    azure_base_url = os.environ.get("AZURE_APIM_BASE_URL", "").rstrip("/")
    if not azure_base_url:
        print("AZURE_APIM_BASE_URL must be set for live verification.", file=sys.stderr)
        return 2

    failures: list[str] = []
    with httpx.Client(timeout=60.0) as client:
        for case in _load_cases(cases_path):
            method = str(case.get("method") or "GET").upper()
            path = str(case.get("path") or "/")
            query = case.get("query") or {}
            headers = case.get("headers") or {}
            body = case.get("body_text")
            compare_headers = list(case.get("compare_headers") or [])

            simulator = client.request(
                method, f"{simulator_base_url}{path}", params=query, headers=headers, content=body
            )
            azure = client.request(method, f"{azure_base_url}{path}", params=query, headers=headers, content=body)

            if simulator.status_code != azure.status_code:
                failures.append(f"{path}: status {simulator.status_code} != {azure.status_code}")
                continue

            if compare_headers:
                simulator_headers = _selected_headers(simulator, compare_headers)
                azure_headers = _selected_headers(azure, compare_headers)
                if simulator_headers != azure_headers:
                    failures.append(f"{path}: header mismatch {simulator_headers} != {azure_headers}")
                    continue

            if _response_body(simulator) != _response_body(azure):
                failures.append(f"{path}: response body mismatch")

    if failures:
        print("Verification failures:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print("Azure verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
