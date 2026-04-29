from __future__ import annotations

import json
import logging
import os
from contextvars import ContextVar, Token
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

import httpx
from fastapi import FastAPI
from opentelemetry import _logs as otel_logs
from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

_CORRELATION_ID: ContextVar[str | None] = ContextVar("correlation_id", default=None)
_LOGGING_INSTRUMENTED = False
_RUNTIMES: dict[str, ObservabilityRuntime] = {}
_STANDARD_LOG_RECORD_ATTRS = frozenset(logging.makeLogRecord({}).__dict__.keys()) | {"message", "asctime"}


@dataclass(frozen=True)
class ObservabilityRuntime:
    enabled: bool
    service_name: str
    service_version: str
    logger: logging.Logger
    tracer: trace.Tracer
    meter: metrics.Meter
    tracer_provider: TracerProvider | None = None
    meter_provider: MeterProvider | None = None
    logger_provider: LoggerProvider | None = None


class JsonLogFormatter(logging.Formatter):
    def __init__(self, *, service_name: str) -> None:
        super().__init__()
        self._service_name = service_name

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=UTC).isoformat(timespec="milliseconds"),
            "severity": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "service.name": self._service_name,
        }

        correlation_id = getattr(record, "correlation_id", None) or get_correlation_id()
        if correlation_id:
            payload["correlation_id"] = correlation_id

        for field in ("trace_id", "span_id", "trace_sampled"):
            value = getattr(record, field, None)
            if value is not None and value != "":
                payload[field] = value

        for key, value in record.__dict__.items():
            if key in _STANDARD_LOG_RECORD_ATTRS or key in payload or key.startswith("_"):
                continue
            if value is None:
                continue
            payload[key] = value

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        if record.stack_info:
            payload["stack"] = self.formatStack(record.stack_info)

        return json.dumps(payload, default=str, separators=(",", ":"))


def _env_true(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def telemetry_enabled() -> bool:
    if _env_true("OTEL_SDK_DISABLED"):
        return False
    return any(
        os.getenv(name, "").strip()
        for name in (
            "OTEL_EXPORTER_OTLP_ENDPOINT",
            "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
            "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT",
            "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT",
        )
    )


def set_correlation_id(correlation_id: str) -> Token[str | None]:
    return _CORRELATION_ID.set(correlation_id)


def reset_correlation_id(token: Token[str | None]) -> None:
    _CORRELATION_ID.reset(token)


def get_correlation_id() -> str | None:
    return _CORRELATION_ID.get()


def _logging_level() -> int:
    level_name = os.getenv("LOG_LEVEL") or os.getenv("OTEL_PYTHON_LOG_LEVEL") or "INFO"
    return getattr(logging, level_name.upper(), logging.INFO)


def _configure_logging_instrumentor(tracer_provider: TracerProvider | None) -> None:
    global _LOGGING_INSTRUMENTED
    if _LOGGING_INSTRUMENTED:
        return

    def _log_hook(span: Any, record: logging.LogRecord) -> None:
        if span is None or not span.is_recording():
            return
        span_context = span.get_span_context()
        if not span_context.is_valid:
            return
        record.trace_id = format(span_context.trace_id, "032x")
        record.span_id = format(span_context.span_id, "016x")
        record.trace_sampled = bool(span_context.trace_flags.sampled)

    LoggingInstrumentor().instrument(
        tracer_provider=tracer_provider,
        set_logging_format=False,
        enable_log_auto_instrumentation=False,
        log_hook=_log_hook,
    )
    _LOGGING_INSTRUMENTED = True


def _configure_named_logger(
    *,
    logger_name: str,
    service_name: str,
    logger_provider: LoggerProvider | None,
    level: int,
    replace_handlers: bool = False,
) -> logging.Logger:
    logger = logging.getLogger(logger_name)
    logger.setLevel(level)
    logger.propagate = False

    if replace_handlers:
        logger.handlers.clear()

    if not any(getattr(handler, "_apim_stream_handler", False) for handler in logger.handlers):
        stream_handler = logging.StreamHandler()
        stream_handler._apim_stream_handler = True  # type: ignore[attr-defined]
        stream_handler.setFormatter(JsonLogFormatter(service_name=service_name))
        logger.addHandler(stream_handler)

    if logger_provider is not None and not any(
        getattr(handler, "_apim_otel_handler", False) for handler in logger.handlers
    ):
        otel_handler = LoggingHandler(level=logging.NOTSET, logger_provider=logger_provider)
        otel_handler._apim_otel_handler = True  # type: ignore[attr-defined]
        logger.addHandler(otel_handler)

    return logger


def _build_resource(*, service_name: str, service_version: str) -> Resource:
    resource_attributes: dict[str, Any] = {
        "service.name": os.getenv("OTEL_SERVICE_NAME", service_name),
        "service.version": service_version,
        "deployment.environment.name": os.getenv("OTEL_DEPLOYMENT_ENVIRONMENT", "local"),
    }
    service_namespace = os.getenv("OTEL_SERVICE_NAMESPACE", "").strip()
    if service_namespace:
        resource_attributes["service.namespace"] = service_namespace
    return Resource.create(resource_attributes)


def configure_observability(*, service_name: str, service_version: str) -> ObservabilityRuntime:
    existing = _RUNTIMES.get(service_name)
    if existing is not None:
        return existing

    enabled = telemetry_enabled()
    tracer_provider: TracerProvider | None = None
    meter_provider: MeterProvider | None = None
    logger_provider: LoggerProvider | None = None

    if enabled:
        shared_runtime = next((runtime for runtime in _RUNTIMES.values() if runtime.enabled), None)
        if shared_runtime is not None:
            tracer_provider = shared_runtime.tracer_provider
            meter_provider = shared_runtime.meter_provider
            logger_provider = shared_runtime.logger_provider
        else:
            resource = _build_resource(service_name=service_name, service_version=service_version)

            tracer_provider = TracerProvider(resource=resource)
            tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
            trace.set_tracer_provider(tracer_provider)

            metric_reader = PeriodicExportingMetricReader(
                OTLPMetricExporter(),
                export_interval_millis=int(os.getenv("OTEL_METRIC_EXPORT_INTERVAL_MS", "30000")),
            )
            meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
            metrics.set_meter_provider(meter_provider)

            logger_provider = LoggerProvider(resource=resource)
            logger_provider.add_log_record_processor(BatchLogRecordProcessor(OTLPLogExporter()))
            otel_logs.set_logger_provider(logger_provider)

    _configure_logging_instrumentor(tracer_provider)
    log_level = _logging_level()
    logger = _configure_named_logger(
        logger_name=service_name,
        service_name=service_name,
        logger_provider=logger_provider,
        level=log_level,
    )
    for logger_name in ("uvicorn", "uvicorn.error"):
        _configure_named_logger(
            logger_name=logger_name,
            service_name=service_name,
            logger_provider=logger_provider,
            level=log_level,
            replace_handlers=True,
        )

    runtime = ObservabilityRuntime(
        enabled=enabled,
        service_name=service_name,
        service_version=service_version,
        logger=logger,
        tracer=trace.get_tracer(service_name, service_version),
        meter=metrics.get_meter(service_name, service_version),
        tracer_provider=tracer_provider,
        meter_provider=meter_provider,
        logger_provider=logger_provider,
    )
    _RUNTIMES[service_name] = runtime
    return runtime


def instrument_fastapi_app(app: FastAPI, telemetry: ObservabilityRuntime) -> None:
    if not telemetry.enabled or getattr(app.state, "_otel_fastapi_instrumented", False):
        return
    FastAPIInstrumentor.instrument_app(
        app,
        tracer_provider=telemetry.tracer_provider,
        meter_provider=telemetry.meter_provider,
        exclude_spans=["receive", "send"],
    )
    app.state._otel_fastapi_instrumented = True


def instrument_httpx_client(client: httpx.AsyncClient | httpx.Client, telemetry: ObservabilityRuntime) -> None:
    if not telemetry.enabled or getattr(client, "_otel_httpx_instrumented", False):
        return
    HTTPXClientInstrumentor.instrument_client(
        client,
        tracer_provider=telemetry.tracer_provider,
        meter_provider=telemetry.meter_provider,
    )
    client._otel_httpx_instrumented = True  # type: ignore[attr-defined]


def set_current_span_attributes(**attributes: Any) -> None:
    span = trace.get_current_span()
    if span is None or not span.is_recording():
        return
    for key, value in attributes.items():
        if value is None:
            continue
        if isinstance(value, bool | str | int | float):
            span.set_attribute(key, value)
            continue
        if isinstance(value, list):
            if not value:
                continue
            if all(isinstance(item, bool | str | int | float) for item in value):
                span.set_attribute(key, value)
                continue
        span.set_attribute(key, str(value))
