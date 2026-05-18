#!/usr/bin/env python3
"""Subnetcalc API conformance harness.

The contract source is docs/ddd/contracts.md plus the Go runtime's current
behavior for provider range and network planning examples.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlencode
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


@dataclass(frozen=True)
class ContractCase:
    case_id: str
    section: str
    level: str
    method: str
    path: str
    payload: dict[str, Any] | None
    status: int
    subset: dict[str, Any] | None = None
    contains: dict[str, Any] | None = None


CONTRACT_CASES: tuple[ContractCase, ...] = (
    ContractCase(
        case_id="SUBNETCALC-API-001",
        section="health",
        level="MUST",
        method="GET",
        path="/api/v1/health",
        payload=None,
        status=200,
        subset={"status": "healthy"},
    ),
    ContractCase(
        case_id="SUBNETCALC-API-010",
        section="ipv4-subnet-info",
        level="MUST",
        method="POST",
        path="/api/v1/ipv4/subnet-info",
        payload={"network": "10.0.0.0/24", "mode": "Standard"},
        status=200,
        subset={
            "network_address": "10.0.0.0",
            "broadcast_address": "10.0.0.255",
            "prefix_length": 24,
            "total_addresses": 256,
            "usable_addresses": 254,
            "first_usable_ip": "10.0.0.1",
            "last_usable_ip": "10.0.0.254",
        },
    ),
    ContractCase(
        case_id="SUBNETCALC-API-011",
        section="ipv4-subnet-info",
        level="MUST",
        method="POST",
        path="/api/v1/ipv4/subnet-info",
        payload={"network": "10.0.0.0/24", "mode": "Azure"},
        status=200,
        subset={"mode": "Azure", "usable_addresses": 251, "first_usable_ip": "10.0.0.4"},
    ),
    ContractCase(
        case_id="SUBNETCALC-API-012",
        section="ipv4-subnet-info",
        level="MUST",
        method="POST",
        path="/api/v1/ipv4/subnet-info",
        payload={"network": "10.0.0.0/24", "mode": "AWS"},
        status=200,
        subset={"mode": "AWS", "usable_addresses": 251, "first_usable_ip": "10.0.0.4"},
    ),
    ContractCase(
        case_id="SUBNETCALC-API-013",
        section="ipv4-subnet-info",
        level="MUST",
        method="POST",
        path="/api/v1/ipv4/subnet-info",
        payload={"network": "10.0.0.0/24", "mode": "OCI"},
        status=200,
        subset={"mode": "OCI", "usable_addresses": 253, "first_usable_ip": "10.0.0.2"},
    ),
    ContractCase(
        case_id="SUBNETCALC-API-020",
        section="ipv6-subnet-info",
        level="MUST",
        method="POST",
        path="/api/v1/ipv6/subnet-info",
        payload={"network": "2001:db8::/112"},
        status=200,
        subset={"network_address": "2001:db8::", "prefix_length": 112, "total_addresses": "65536"},
    ),
    ContractCase(
        case_id="SUBNETCALC-API-030",
        section="provider-ranges",
        level="MUST",
        method="POST",
        path="/api/v1/provider-ranges/check",
        payload={"provider": "aws", "address": "3.5.140.1"},
        status=200,
        subset={"provider": "aws", "is_provider_range": True, "ip_version": 4},
        contains={"matched_ranges": "3.5.140.0/22"},
    ),
    ContractCase(
        case_id="SUBNETCALC-API-031",
        section="provider-ranges",
        level="MUST",
        method="POST",
        path="/api/v1/provider-ranges/check",
        payload={"provider": "openai", "address": "3.5.140.1"},
        status=200,
        subset={"provider": "openai", "is_provider_range": False, "ip_version": 4},
    ),
    ContractCase(
        case_id="SUBNETCALC-API-032",
        section="provider-ranges",
        level="MUST",
        method="POST",
        path="/api/v1/provider-ranges/cache/invalidate",
        payload={"provider": "aws"},
        status=200,
        subset={"provider": "aws", "cache_status": "invalidated"},
    ),
    ContractCase(
        case_id="SUBNETCALC-API-040",
        section="network-plan",
        level="MUST",
        method="POST",
        path="/api/v1/network-plan/allocate",
        payload={
            "parent": "10.0.0.0/24",
            "mode": "Azure",
            "requirements": [{"name": "web", "hosts": 60}, {"name": "db", "hosts": 20}],
        },
        status=200,
        subset={"parent": "10.0.0.0/24", "mode": "Azure"},
        contains={"allocations": {"network": "10.0.0.0/25", "usable_addresses": 123}},
    ),
    ContractCase(
        case_id="SUBNETCALC-API-050",
        section="errors",
        level="MUST",
        method="POST",
        path="/api/v1/provider-ranges/check",
        payload={"provider": "unknown", "address": "3.5.140.1"},
        status=400,
    ),
    ContractCase(
        case_id="SUBNETCALC-API-051",
        section="errors",
        level="MUST",
        method="POST",
        path="/api/v1/ipv4/subnet-info",
        payload={"network": "10.0.0.0/24", "mode": "InvalidMode"},
        status=400,
    ),
)


def login(base_url: str, username: str, password: str, timeout: float) -> str:
    url = f"{base_url.rstrip('/')}/api/v1/auth/login"
    body = urlencode({"username": username, "password": password}).encode("utf-8")
    request = Request(
        url,
        data=body,
        method="POST",
        headers={"Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        payload = exc.read().decode("utf-8")
        raise RuntimeError(f"could not authenticate against {url}: status {exc.code}, body {payload}") from exc
    except URLError as exc:
        raise RuntimeError(f"could not reach auth endpoint {url}: {exc}") from exc

    token = payload.get("access_token")
    if not isinstance(token, str) or not token:
        raise RuntimeError(f"auth endpoint did not return access_token: {payload!r}")
    return token


def request_json(base_url: str, case: ContractCase, timeout: float, token: str | None = None) -> tuple[int, dict[str, Any]]:
    url = f"{base_url.rstrip('/')}{case.path}"
    body = None
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if case.payload is not None:
        body = json.dumps(case.payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = Request(url, data=body, method=case.method, headers=headers)
    try:
        with urlopen(request, timeout=timeout) as response:
            payload = response.read().decode("utf-8")
            return response.status, json.loads(payload) if payload else {}
    except HTTPError as exc:
        payload = exc.read().decode("utf-8")
        return exc.code, json.loads(payload) if payload else {}
    except URLError as exc:
        raise RuntimeError(f"{case.case_id} could not reach {url}: {exc}") from exc


def assert_subset(case: ContractCase, actual: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if not case.subset:
        return failures
    for key, expected in case.subset.items():
        if actual.get(key) != expected:
            failures.append(f"{key}: expected {expected!r}, got {actual.get(key)!r}")
    return failures


def assert_contains(case: ContractCase, actual: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if not case.contains:
        return failures
    for key, expected in case.contains.items():
        value = actual.get(key)
        if isinstance(value, list) and isinstance(expected, dict):
            if not any(isinstance(item, dict) and all(item.get(k) == v for k, v in expected.items()) for item in value):
                failures.append(f"{key}: expected list to contain object subset {expected!r}, got {value!r}")
        elif isinstance(value, list):
            if expected not in value:
                failures.append(f"{key}: expected list to contain {expected!r}, got {value!r}")
        else:
            failures.append(f"{key}: expected list, got {value!r}")
    return failures


def render_coverage(results: list[tuple[ContractCase, bool]]) -> str:
    by_section: dict[str, dict[str, int]] = {}
    for case, passed in results:
        stats = by_section.setdefault(case.section, {"must_total": 0, "must_pass": 0, "should_total": 0, "should_pass": 0})
        level = case.level.lower()
        stats[f"{level}_total"] += 1
        if passed:
            stats[f"{level}_pass"] += 1

    lines = [
        "| Contract Section | MUST | SHOULD | Score |",
        "| --- | ---: | ---: | ---: |",
    ]
    for section in sorted(by_section):
        stats = by_section[section]
        total = stats["must_total"] + stats["should_total"]
        passed = stats["must_pass"] + stats["should_pass"]
        score = "n/a" if total == 0 else f"{passed / total:.0%}"
        lines.append(
            f"| {section} | {stats['must_pass']}/{stats['must_total']} | "
            f"{stats['should_pass']}/{stats['should_total']} | {score} |"
        )
    return "\n".join(lines)


def run(base_url: str, case_filter: str | None, timeout: float, token: str | None) -> int:
    cases = [case for case in CONTRACT_CASES if case_filter in (None, case.case_id, case.section)]
    results: list[tuple[ContractCase, bool]] = []

    for case in cases:
        try:
            status, actual = request_json(base_url, case, timeout, token)
            failures = []
            if status != case.status:
                failures.append(f"status: expected {case.status}, got {status}")
            failures.extend(assert_subset(case, actual))
            failures.extend(assert_contains(case, actual))
        except Exception as exc:  # noqa: BLE001 - conformance runner should report all failures uniformly.
            failures = [str(exc)]
            actual = {}

        passed = not failures
        results.append((case, passed))
        verdict = "PASS" if passed else "FAIL"
        print(json.dumps({"case": case.case_id, "section": case.section, "level": case.level, "verdict": verdict}))
        if failures:
            print(f"  {case.method} {case.path}")
            print(f"  payload: {json.dumps(case.payload, sort_keys=True)}")
            print(f"  actual:  {json.dumps(actual, sort_keys=True)}")
            for failure in failures:
                print(f"  - {failure}")

    print()
    print(render_coverage(results))
    failed = sum(1 for _, passed in results if not passed)
    print(f"\n{subnetcalc_summary(len(results), failed)}")
    return 1 if failed else 0


def subnetcalc_summary(total: int, failed: int) -> str:
    passed = total - failed
    return f"Subnetcalc conformance: {passed}/{total} passed, {failed} failed"


def main() -> int:
    parser = argparse.ArgumentParser(description="Run subnetcalc API conformance checks")
    parser.add_argument("--base-url", required=True, help="Base API URL, for example http://127.0.0.1:8090")
    parser.add_argument("--case", help="Run one case id or section")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--jwt-username", help="Username for OAuth2 password-flow JWT authentication")
    parser.add_argument("--jwt-password", help="Password for OAuth2 password-flow JWT authentication")
    args = parser.parse_args()
    if bool(args.jwt_username) != bool(args.jwt_password):
        parser.error("--jwt-username and --jwt-password must be provided together")

    token = None
    if args.jwt_username and args.jwt_password:
        token = login(args.base_url, args.jwt_username, args.jwt_password, args.timeout)

    return run(args.base_url, args.case, args.timeout, token)


if __name__ == "__main__":
    sys.exit(main())
