from __future__ import annotations

import json
import time
from collections.abc import Mapping, MutableMapping
from dataclasses import dataclass
from datetime import UTC
from email.utils import parsedate_to_datetime
from typing import Any

from app.config import AIGatewayCircuitBreakerConfig, AIGatewayPriorityStrategy, GatewayConfig

CircuitState = MutableMapping[str, dict[str, Any]]


@dataclass(frozen=True)
class AIGatewaySelection:
    deployment_name: str
    selected_backend_id: str | None
    selected_backend_url: str | None
    strategy: str
    reason: str
    considered_backend_ids: tuple[str, ...]
    skipped_backends: tuple[dict[str, Any], ...] = ()

    @property
    def available(self) -> bool:
        return bool(self.selected_backend_id and self.selected_backend_url)

    def policy_variables(self) -> dict[str, str]:
        if not self.available:
            return {}
        return {
            "selected_backend_id": self.selected_backend_id or "",
            "selected_backend_url": self.selected_backend_url or "",
        }

    def span_attributes(self) -> dict[str, str | int | bool]:
        return {
            "apim.ai_gateway.deployment": self.deployment_name,
            "apim.ai_gateway.available": self.available,
            "apim.ai_gateway.strategy": self.strategy,
            "apim.ai_gateway.reason": self.reason,
            "apim.ai_gateway.selected_backend_id": self.selected_backend_id or "",
            "apim.ai_gateway.considered_backends": len(self.considered_backend_ids),
            "apim.ai_gateway.skipped_backends": len(self.skipped_backends),
        }

    def trace_metadata(self) -> dict[str, Any]:
        return {
            "deployment": self.deployment_name,
            "available": self.available,
            "strategy": self.strategy,
            "reason": self.reason,
            "selected_backend_id": self.selected_backend_id,
            "selected_backend_url": self.selected_backend_url,
            "considered_backend_ids": list(self.considered_backend_ids),
            "skipped_backends": list(self.skipped_backends),
        }


def extract_openai_deployment_name(path: str, body: bytes = b"") -> str | None:
    """Return the deployment segment from common OpenAI-compatible request paths."""
    segments = [segment for segment in path.split("/") if segment]
    for index, segment in enumerate(segments):
        if segment == "deployments" and index + 1 < len(segments):
            return segments[index + 1]
    for index, segment in enumerate(segments):
        if segment == "engines" and index + 1 < len(segments):
            return segments[index + 1]
    if _looks_like_model_request(segments):
        return _model_from_body(body)
    return None


def select_ai_gateway_backend_for_path(
    config: GatewayConfig,
    path: str,
    circuit_state: CircuitState,
    *,
    body: bytes = b"",
    now: float | None = None,
) -> AIGatewaySelection | None:
    deployment_name = extract_openai_deployment_name(path, body)
    if deployment_name is None:
        return None
    return select_ai_gateway_backend(config, deployment_name, circuit_state, now=now)


def select_ai_gateway_backend(
    config: GatewayConfig,
    deployment_name: str,
    circuit_state: CircuitState,
    *,
    now: float | None = None,
) -> AIGatewaySelection | None:
    deployment = config.ai_gateway.deployments.get(deployment_name)
    if deployment is None:
        return None

    current_time = time.time() if now is None else now
    backend_ids = tuple(deployment.backend_ids)
    if config.ai_gateway.strategy != AIGatewayPriorityStrategy.Priority:
        return AIGatewaySelection(
            deployment_name=deployment_name,
            selected_backend_id=None,
            selected_backend_url=None,
            strategy=str(config.ai_gateway.strategy),
            reason="unsupported_strategy",
            considered_backend_ids=backend_ids,
        )

    skipped: list[dict[str, Any]] = []
    for backend_id in backend_ids:
        backend = config.backends.get(backend_id)
        if backend is None:
            skipped.append({"backend_id": backend_id, "reason": "unknown_backend"})
            continue

        open_until = _backend_open_until(circuit_state, backend_id, now=current_time)
        if open_until is not None:
            skipped.append({"backend_id": backend_id, "reason": "circuit_open", "open_until": open_until})
            continue

        return AIGatewaySelection(
            deployment_name=deployment_name,
            selected_backend_id=backend_id,
            selected_backend_url=backend.url,
            strategy=config.ai_gateway.strategy.value,
            reason="selected",
            considered_backend_ids=backend_ids,
            skipped_backends=tuple(skipped),
        )

    return AIGatewaySelection(
        deployment_name=deployment_name,
        selected_backend_id=None,
        selected_backend_url=None,
        strategy=config.ai_gateway.strategy.value,
        reason="no_available_backend",
        considered_backend_ids=backend_ids,
        skipped_backends=tuple(skipped),
    )


def record_ai_gateway_backend_response(
    config: GatewayConfig,
    backend_id: str,
    status_code: int,
    response_headers: Mapping[str, str],
    circuit_state: CircuitState,
    *,
    now: float | None = None,
) -> dict[str, Any]:
    breaker = config.ai_gateway.circuit_breaker
    current_time = time.time() if now is None else now
    if not breaker.enabled:
        circuit_state.pop(backend_id, None)
        return {"backend_id": backend_id, "tripped": False, "reason": "disabled"}

    if not _status_trips_breaker(status_code, breaker):
        circuit_state.pop(backend_id, None)
        return {"backend_id": backend_id, "tripped": False, "reason": "status_not_configured"}

    retry_after = _header_value(response_headers, "retry-after")
    retry_after_seconds = (
        _parse_retry_after_seconds(retry_after, now=current_time) if breaker.honor_retry_after and retry_after else None
    )
    open_seconds = retry_after_seconds if retry_after_seconds is not None else max(0.0, breaker.open_duration_seconds)
    open_until = current_time + open_seconds
    circuit_state[backend_id] = {
        "state": "open",
        "opened_at": current_time,
        "open_until": open_until,
        "status_code": status_code,
        "retry_after": retry_after,
    }
    return {
        "backend_id": backend_id,
        "tripped": True,
        "status_code": status_code,
        "open_until": open_until,
        "retry_after": retry_after,
    }


def _backend_open_until(circuit_state: CircuitState, backend_id: str, *, now: float) -> float | None:
    state = circuit_state.get(backend_id)
    if not state:
        return None

    open_until = state.get("open_until")
    if not isinstance(open_until, int | float):
        circuit_state.pop(backend_id, None)
        return None

    if float(open_until) <= now:
        circuit_state.pop(backend_id, None)
        return None
    return float(open_until)


def _status_trips_breaker(status_code: int, breaker: AIGatewayCircuitBreakerConfig) -> bool:
    if status_code in breaker.trip_status_codes:
        return True

    for status_range in breaker.trip_status_code_ranges:
        normalized = status_range.strip().lower()
        if len(normalized) == 3 and normalized.endswith("xx") and normalized[0].isdigit():
            lower = int(normalized[0]) * 100
            if lower <= status_code <= lower + 99:
                return True
            continue
        if "-" in normalized:
            left, right = normalized.split("-", 1)
            if left.isdigit() and right.isdigit() and int(left) <= status_code <= int(right):
                return True
    return False


def _parse_retry_after_seconds(value: str, *, now: float) -> float | None:
    stripped = value.strip()
    if not stripped:
        return None
    if stripped.isdigit():
        return float(stripped)

    try:
        retry_at = parsedate_to_datetime(stripped)
    except (TypeError, ValueError):
        return None
    if retry_at.tzinfo is None:
        retry_at = retry_at.replace(tzinfo=UTC)
    return max(0.0, retry_at.timestamp() - now)


def _header_value(headers: Mapping[str, str], name: str) -> str | None:
    expected = name.lower()
    for key, value in headers.items():
        if key.lower() == expected:
            return value
    return None


def _looks_like_model_request(segments: list[str]) -> bool:
    if not segments:
        return False
    if segments[-2:] == ["chat", "completions"]:
        return True
    return segments[-1] in {"completions", "embeddings", "responses"}


def _model_from_body(body: bytes) -> str | None:
    if not body:
        return None
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    model = payload.get("model")
    return model if isinstance(model, str) and model else None
