from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx
from defusedxml import ElementTree
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from starlette.background import BackgroundTask
from starlette.responses import StreamingResponse

from app.config import (
    ApiConfig,
    ApiReleaseConfig,
    ApiRevisionConfig,
    ApiSchemaConfig,
    ApiVersioningScheme,
    ApiVersionSetConfig,
    BackendConfig,
    DiagnosticConfig,
    GatewayConfig,
    GroupConfig,
    KeyVaultNamedValueConfig,
    LoggerConfig,
    NamedValueConfig,
    OperationConfig,
    OperationParameterConfig,
    OperationRequestMetadataConfig,
    OperationResponseMetadataConfig,
    ProductConfig,
    RouteAuthzConfig,
    Subscription,
    SubscriptionState,
    TagConfig,
    UserConfig,
    load_config,
)
from app.management_service import ManagementService
from app.named_values import mask_secret_data
from app.openapi_import import parse_api_import
from app.policy import (
    PolicyRequest,
    PolicyRuntime,
    PolicyTraceCollector,
    apply_backend_async,
    apply_inbound_async,
    apply_on_error_async,
    apply_outbound_async,
    finalize_deferred_actions,
    parse_policies_xml,
)
from app.proxy import build_upstream_headers, build_user_payload, filter_response_headers, resolve_route
from app.resource_projection import (
    project_api,
    project_api_release,
    project_api_revision,
    project_api_schema,
    project_api_tag_link,
    project_api_version_set,
    project_backend,
    project_diagnostic,
    project_group,
    project_group_user_link,
    project_logger,
    project_named_value,
    project_operation,
    project_operation_tag_link,
    project_policy_fragment,
    project_product,
    project_product_group_link,
    project_product_tag_link,
    project_service,
    project_subscription,
    project_summary,
    project_tag,
    project_user,
)
from app.security import (
    OIDCVerifier,
    authenticate_request,
    build_client_principal,
    subscription_bypassed,
    validate_client_certificate,
)
from app.telemetry import (
    ObservabilityRuntime,
    configure_observability,
    get_correlation_id,
    instrument_fastapi_app,
    instrument_httpx_client,
    reset_correlation_id,
    set_correlation_id,
    set_current_span_attributes,
)
from app.terraform_import import import_from_tofu_show_json

logger = logging.getLogger("apim-simulator")

APIM_SERVICE_NAME = "apim-simulator"
APIM_SERVICE_VERSION = "0.3.0"
APIM_ROUTE_NAME_ATTR = "apim.route.name"
APIM_CACHE_RESULT_ATTR = "apim.cache.result"
APIM_BACKEND_ID_ATTR = "apim.backend.id"
APIM_TRACE_REQUESTED_ATTR = "apim.trace.requested"
APIM_RESULT_REASON_ATTR = "apim.result.reason"
APIM_UPSTREAM_ATTEMPTS_ATTR = "apim.upstream.attempts"
EMPTY_POLICY_XML = "<policies><inbound /><backend /><outbound /><on-error /></policies>"
POLICY_SECTION_NAMES = ("inbound", "backend", "outbound", "on-error")
_GATEWAY_METRICS: GatewayMetrics | None = None


@dataclass(frozen=True)
class GatewayMetrics:
    requests: Any
    request_duration: Any
    upstream_duration: Any
    cache_events: Any
    policy_short_circuits: Any
    config_reloads: Any


def _merge_policy_xml_documents(xml_documents: list[str]) -> str:
    if not xml_documents:
        return EMPTY_POLICY_XML
    if len(xml_documents) == 1:
        return xml_documents[0]

    root = ElementTree.Element("policies")
    sections = {name: ElementTree.SubElement(root, name) for name in POLICY_SECTION_NAMES}

    for xml in xml_documents:
        try:
            parsed = ElementTree.fromstring(xml)
        except ElementTree.ParseError:
            continue
        if parsed.tag != "policies":
            continue
        for section_name in POLICY_SECTION_NAMES:
            source = parsed.find(section_name)
            if source is None:
                continue
            for child in list(source):
                sections[section_name].append(deepcopy(child))

    return ElementTree.tostring(root, encoding="unicode")


def _effective_policy_xml(*groups: list[str] | None) -> str:
    xml_documents: list[str] = []
    for group in groups:
        if not group:
            continue
        xml_documents.extend(item for item in group if item)
    return _merge_policy_xml_documents(xml_documents)


def _serialize_gateway_config(cfg: GatewayConfig) -> str:
    payload = cfg.model_dump(mode="json")
    if payload.get("apis"):
        payload["routes"] = []
    return json.dumps(payload, indent=2) + "\n"


def _decode_body(content: bytes) -> dict[str, str | None]:
    if not content:
        return {"text": "", "base64": None}
    try:
        return {"text": content.decode("utf-8"), "base64": None}
    except UnicodeDecodeError:
        return {"text": None, "base64": base64.b64encode(content).decode("ascii")}


def _apply_claim_headers(headers: dict[str, str], claims: dict[str, Any]) -> None:
    headers["x-apim-user-object-id"] = str(claims.get("sub", ""))
    headers["x-apim-user-email"] = str(claims.get("email", ""))
    headers["x-apim-user-name"] = str(claims.get("name") or claims.get("preferred_username") or "")
    headers["x-apim-auth-method"] = "oidc"
    headers["x-ms-client-principal"] = build_client_principal(claims)
    headers["x-ms-client-principal-name"] = str(claims.get("preferred_username", ""))


def _trace_payload(
    *,
    trace_base: dict[str, Any],
    trace_collector: PolicyTraceCollector | None,
    cfg: GatewayConfig,
    extra: dict[str, Any],
) -> dict[str, Any]:
    payload = {
        **trace_base,
        "policy_steps": trace_collector.steps if trace_collector else [],
        "policy_variable_writes": trace_collector.variable_writes if trace_collector else [],
        "jwt_validations": trace_collector.jwt_validations if trace_collector else [],
        "send_requests": trace_collector.send_requests if trace_collector else [],
        "selected_backend": trace_collector.selected_backend if trace_collector else None,
        **extra,
    }
    return mask_secret_data(payload, cfg)


def _request_cache_key(
    *,
    method: str,
    upstream_url: str,
    query: dict[str, str],
    authorization: str,
    subscription_key: str,
) -> str:
    payload = json.dumps(
        {
            "method": method,
            "upstream_url": upstream_url,
            "query": query,
            "authorization": authorization,
            "subscription_key": subscription_key,
        },
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _cached_gateway_response(
    *,
    cached: tuple[float, int, dict[str, str], str | None, bytes] | None,
    request: Request,
    route_name: str,
    policy_req: PolicyRequest,
    policy_runtime: PolicyRuntime,
    trace_base: dict[str, Any],
    trace_collector: PolicyTraceCollector | None,
    cfg: GatewayConfig,
    gateway_metrics: Any,
    correlation_id: str,
    trace_id: str | None,
) -> Response | None:
    if cached is None:
        return None

    expires_at, cached_status, cached_headers, cached_media_type, cached_body = cached
    if time.time() >= expires_at:
        return None

    if not isinstance(cached_status, int) or not (100 <= cached_status <= 599):
        return None

    body_bytes = bytes(cached_body)
    out_headers = dict(cached_headers)
    media_type = (
        cached_media_type if cached_media_type is None or isinstance(cached_media_type, str) else str(cached_media_type)
    )

    request.state.apim_cache_result = "hit"
    request.state.apim_result_reason = "cache_hit"
    request.state.apim_upstream_attempts = 0
    gateway_metrics.cache_events.add(
        1,
        {
            APIM_ROUTE_NAME_ATTR: route_name,
            APIM_CACHE_RESULT_ATTR: "hit",
            "http.request.method": request.method,
        },
    )
    set_current_span_attributes(
        **{
            APIM_CACHE_RESULT_ATTR: "hit",
            APIM_RESULT_REASON_ATTR: "cache_hit",
            APIM_UPSTREAM_ATTEMPTS_ATTR: 0,
        }
    )
    final_req = PolicyRequest(
        method=policy_req.method,
        path=policy_req.path,
        query=dict(policy_req.query),
        headers=dict(policy_req.headers),
        variables=policy_req.variables,
        body=policy_req.body,
        response_status_code=cached_status,
        response_headers=out_headers,
        response_body=body_bytes,
        response_media_type=media_type,
    )
    finalize_deferred_actions(final_req, policy_runtime)
    out_headers["x-apim-cache"] = "hit"
    out_headers["x-correlation-id"] = correlation_id
    if trace_id:
        out_headers["x-apim-trace-id"] = trace_id
        trace = _trace_payload(
            trace_base=trace_base,
            trace_collector=trace_collector,
            cfg=cfg,
            extra={
                "attempts": 0,
                "status": cached_status,
                "elapsed_ms": 0,
                "cache": "hit",
            },
        )
        out_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode("utf-8")
        trace_store: dict[str, Any] = request.app.state.trace_store
        trace_store[trace_id] = {
            "trace_id": trace_id,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            **trace,
        }
    return Response(
        content=body_bytes,
        status_code=cached_status,
        headers=out_headers,
        media_type=media_type,
    )


def _render_backend_value(value: str | None, policy_req: PolicyRequest, cfg: GatewayConfig) -> str | None:
    if value is None:
        return None
    runtime = PolicyRuntime(gateway_config=cfg)
    from app.policy import render_policy_value

    return render_policy_value(value, policy_req, runtime)


def _get_gateway_metrics(telemetry: ObservabilityRuntime) -> GatewayMetrics:
    global _GATEWAY_METRICS
    if _GATEWAY_METRICS is not None:
        return _GATEWAY_METRICS

    meter = telemetry.meter
    _GATEWAY_METRICS = GatewayMetrics(
        requests=meter.create_counter(
            "apim.gateway.requests",
            description="Count of requests handled by the APIM simulator gateway",
        ),
        request_duration=meter.create_histogram(
            "apim.gateway.request.duration",
            unit="s",
            description="End-to-end gateway request duration",
        ),
        upstream_duration=meter.create_histogram(
            "apim.gateway.upstream.duration",
            unit="s",
            description="Duration spent waiting on upstream backends",
        ),
        cache_events=meter.create_counter(
            "apim.gateway.cache.events",
            description="Gateway response cache outcomes",
        ),
        policy_short_circuits=meter.create_counter(
            "apim.gateway.policy.short_circuits",
            description="Requests terminated by inbound or backend APIM policy stages",
        ),
        config_reloads=meter.create_counter(
            "apim.gateway.config.reloads",
            description="Gateway config reload attempts",
        ),
    )
    return _GATEWAY_METRICS


def _request_route_label(request: Request) -> str:
    apim_route_name = getattr(request.state, "apim_route_name", None)
    if apim_route_name:
        return apim_route_name

    route = request.scope.get("route")
    route_path = getattr(route, "path", None)
    if route_path:
        return str(route_path)
    return request.url.path


def _request_client_ip(request: Request) -> str:
    state_value = getattr(request.state, "apim_client_ip", None)
    if state_value:
        return state_value
    if request.client is not None:
        return request.client.host
    return ""


def _request_observation_attrs(request: Request, status_code: int) -> dict[str, str | int | bool]:
    return {
        "http.request.method": request.method,
        "http.response.status_code": status_code,
        "http.route": _request_route_label(request),
        APIM_ROUTE_NAME_ATTR: getattr(request.state, "apim_route_name", "none"),
        APIM_CACHE_RESULT_ATTR: getattr(request.state, "apim_cache_result", "none"),
        APIM_BACKEND_ID_ATTR: getattr(request.state, "apim_backend_id", "none"),
        APIM_TRACE_REQUESTED_ATTR: bool(getattr(request.state, "apim_trace_requested", False)),
    }


def _record_request_observation(request: Request, *, status_code: int, duration_seconds: float) -> None:
    metrics: GatewayMetrics = request.app.state.gateway_metrics
    attrs = _request_observation_attrs(request, status_code)
    metrics.requests.add(1, attrs)
    metrics.request_duration.record(duration_seconds, attrs)

    upstream_duration = getattr(request.state, "apim_upstream_duration_seconds", None)
    if upstream_duration is not None:
        metrics.upstream_duration.record(upstream_duration, attrs)


def _access_log_fields(request: Request, *, status_code: int, duration_seconds: float) -> dict[str, Any]:
    return {
        "event.name": "http.request.completed",
        "http.request.method": request.method,
        "url.path": request.url.path,
        "http.route": _request_route_label(request),
        "http.response.status_code": status_code,
        "duration_ms": round(duration_seconds * 1000, 3),
        "network.client.ip": _request_client_ip(request),
        "correlation_id": get_correlation_id() or getattr(request.state, "correlation_id", None),
        APIM_ROUTE_NAME_ATTR: getattr(request.state, "apim_route_name", None),
        APIM_BACKEND_ID_ATTR: getattr(request.state, "apim_backend_id", None),
        APIM_CACHE_RESULT_ATTR: getattr(request.state, "apim_cache_result", None),
        APIM_TRACE_REQUESTED_ATTR: getattr(request.state, "apim_trace_requested", False),
        APIM_UPSTREAM_ATTEMPTS_ATTR: getattr(request.state, "apim_upstream_attempts", None),
        APIM_RESULT_REASON_ATTR: getattr(request.state, "apim_result_reason", None),
    }


class SubscriptionUpsert(BaseModel):
    id: str
    name: str
    state: SubscriptionState = SubscriptionState.Active
    products: list[str] = Field(default_factory=list)
    primary_key: str | None = None
    secondary_key: str | None = None


class SubscriptionUpdate(BaseModel):
    name: str | None = None
    state: SubscriptionState | None = None
    products: list[str] | None = None


class ApiUpsert(BaseModel):
    name: str | None = None
    path: str
    upstream_base_url: str
    upstream_path_prefix: str = ""
    backend: str | None = None
    products: list[str] = Field(default_factory=list)
    api_version_set: str | None = None
    api_version: str | None = None
    subscription_header_names: list[str] | None = None
    subscription_query_param_names: list[str] | None = None
    policies_xml: str | None = None


class OperationUpsert(BaseModel):
    name: str | None = None
    method: str = "GET"
    url_template: str
    description: str | None = None
    upstream_base_url: str | None = None
    upstream_path_prefix: str | None = None
    backend: str | None = None
    products: list[str] | None = None
    api_version_set: str | None = None
    api_version: str | None = None
    subscription_header_names: list[str] | None = None
    subscription_query_param_names: list[str] | None = None
    authz: RouteAuthzConfig | None = None
    policies_xml: str | None = None
    tags: list[str] | None = None
    template_parameters: list[OperationParameterConfig] | None = None
    request: OperationRequestMetadataConfig | None = None
    responses: list[OperationResponseMetadataConfig] | None = None


class ApiImportRequest(BaseModel):
    name: str | None = None
    path: str | None = None
    content_format: str
    content_value: str
    upstream_base_url: str | None = None
    upstream_path_prefix: str = ""
    backend: str | None = None
    products: list[str] | None = None
    api_version_set: str | None = None
    api_version: str | None = None
    subscription_header_names: list[str] | None = None
    subscription_query_param_names: list[str] | None = None
    policies_xml: str | None = None


class ApiVersionSetUpsert(BaseModel):
    display_name: str
    description: str | None = None
    versioning_scheme: str
    version_header_name: str | None = None
    version_query_name: str | None = None
    default_version: str | None = None


class ApiRevisionUpsert(BaseModel):
    description: str | None = None
    is_current: bool | None = None
    is_online: bool | None = None
    source_api_id: str | None = None


class ApiReleaseUpsert(BaseModel):
    name: str | None = None
    api_id: str | None = None
    notes: str | None = None
    revision: str


class ProductUpsert(BaseModel):
    name: str
    description: str | None = None
    require_subscription: bool = True


class GroupUpsert(BaseModel):
    name: str
    description: str | None = None
    external_id: str | None = None
    type: str = "custom"


class UserUpsert(BaseModel):
    email: str | None = None
    first_name: str | None = None
    last_name: str | None = None
    note: str | None = None
    state: str | None = None
    confirmation: str | None = None


class TagUpsert(BaseModel):
    display_name: str | None = None


class BackendUpsert(BaseModel):
    url: str
    description: str | None = None
    auth_type: str = "none"
    basic_username: str | None = None
    basic_password: str | None = None
    managed_identity_resource: str | None = None
    authorization_scheme: str | None = None
    authorization_parameter: str | None = None
    header_credentials: dict[str, str] = Field(default_factory=dict)
    query_credentials: dict[str, str] = Field(default_factory=dict)
    client_certificate_thumbprints: list[str] = Field(default_factory=list)


class NamedValueUpsert(BaseModel):
    value: str | None = None
    secret: bool = False
    value_from_key_vault: KeyVaultNamedValueConfig | None = None


class PolicyUpdate(BaseModel):
    xml: str


class PolicyFragmentUpsert(BaseModel):
    xml: str


class ReplayRequestBody(BaseModel):
    method: str = "GET"
    path: str
    query: dict[str, str] = Field(default_factory=dict)
    headers: dict[str, str] = Field(default_factory=dict)
    body_text: str | None = None
    body_base64: str | None = None


OperationUpsert.model_rebuild()


def create_app(*, config: GatewayConfig | None = None, http_client: httpx.AsyncClient | None = None) -> FastAPI:
    telemetry = configure_observability(service_name=APIM_SERVICE_NAME, service_version=APIM_SERVICE_VERSION)
    gateway_config = config or load_config()
    gateway_config.routes = gateway_config.materialize_routes()

    def _build_oidc_verifiers(cfg: GatewayConfig) -> dict[str, OIDCVerifier]:
        verifiers: dict[str, OIDCVerifier] = {}
        if cfg.oidc_providers:
            for provider_id, provider in cfg.oidc_providers.items():
                verifiers[provider_id] = OIDCVerifier(
                    provider.issuer,
                    provider.audience,
                    jwks_uri=provider.jwks_uri,
                    jwks=provider.jwks,
                )
        elif cfg.oidc is not None:
            verifiers["default"] = OIDCVerifier(
                cfg.oidc.issuer,
                cfg.oidc.audience,
                jwks_uri=cfg.oidc.jwks_uri,
                jwks=cfg.oidc.jwks,
            )
        return verifiers

    management_plane: ManagementService | None = None

    def _require_management_plane() -> ManagementService:
        if management_plane is None:
            raise HTTPException(status_code=500, detail="Management service not initialized")
        return management_plane

    async def _config_watcher(app: FastAPI, config_path: str, interval: float = 5.0) -> None:
        """Watch config file for changes and reload when modified.

        Kubernetes ConfigMaps are mounted as symlinks that change on update.
        We track both mtime and resolved symlink target to detect changes.
        """
        path = Path(config_path)
        last_mtime: float = 0
        last_target: str = ""

        try:
            if path.exists():
                last_mtime = path.stat().st_mtime
                last_target = str(path.resolve()) if path.is_symlink() else ""
        except OSError:
            pass

        logger.info("config watcher started | path=%s | interval=%.1fs", config_path, interval)

        while True:
            await asyncio.sleep(interval)
            try:
                if not path.exists():
                    continue

                current_mtime = path.stat().st_mtime
                current_target = str(path.resolve()) if path.is_symlink() else ""

                changed = False
                if current_mtime != last_mtime:
                    changed = True
                    last_mtime = current_mtime
                if current_target and current_target != last_target:
                    changed = True
                    last_target = current_target

                if changed:
                    logger.info("config file changed, reloading...")
                    manager = management_plane
                    if manager is None:
                        logger.warning("config watcher skipped reload because management service was unavailable")
                        continue
                    manager.reload_config()
            except Exception as exc:
                logger.warning("config watcher error: %s", exc)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        created = False
        if http_client is None:
            app.state.http_client = httpx.AsyncClient(timeout=httpx.Timeout(30.0))
            created = True
        else:
            app.state.http_client = http_client
        instrument_httpx_client(app.state.http_client, telemetry)
        manager = _require_management_plane()
        manager.apply_runtime_config(gateway_config)
        app.state.cache = {}
        app.state.policy_cache = {}
        app.state.policy_response_cache = {}
        app.state.policy_value_cache = {}
        app.state.rate_limit_store = {}
        app.state.quota_store = {}
        app.state.trace_store = {}
        app.state.config_reload_fn = manager.reload_config
        app.state.startup_complete = True

        watcher_task: asyncio.Task | None = None
        config_path = os.getenv("APIM_CONFIG_PATH", "").strip()
        watch_enabled = os.getenv("APIM_CONFIG_WATCH", "false").lower() == "true"
        watch_interval = float(os.getenv("APIM_CONFIG_WATCH_INTERVAL", "5"))

        if config_path and watch_enabled:
            watcher_task = asyncio.create_task(_config_watcher(app, config_path, watch_interval))

        logger.info(
            "apim-sim ready | routes=%d | origins=%s | anonymous=%s | watch=%s",
            len(gateway_config.routes),
            gateway_config.allowed_origins,
            gateway_config.allow_anonymous,
            watch_enabled,
        )
        yield
        if watcher_task:
            watcher_task.cancel()
            try:
                await watcher_task
            except asyncio.CancelledError:
                pass
        if created:
            await app.state.http_client.aclose()

    app = FastAPI(title="Local APIM Simulator", version=APIM_SERVICE_VERSION, lifespan=lifespan)
    management_plane = ManagementService(
        app=app,
        serialize_gateway_config=_serialize_gateway_config,
        build_oidc_verifiers=_build_oidc_verifiers,
    )
    app.state.telemetry = telemetry
    app.state.gateway_metrics = _get_gateway_metrics(telemetry)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=gateway_config.allowed_origins or ["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
        expose_headers=["x-apim-simulator", "x-apim-trace-id", "x-correlation-id", "x-todo-demo-policy"],
    )

    @app.middleware("http")
    async def observe_requests(request: Request, call_next):
        correlation_id = request.headers.get("x-correlation-id") or f"corr-{uuid.uuid4()}"
        request.state.correlation_id = correlation_id
        request.state.apim_cache_result = "none"
        request.state.apim_backend_id = "none"
        request.state.apim_upstream_attempts = 0
        request.state.apim_trace_requested = False
        request.state.apim_result_reason = None
        token = set_correlation_id(correlation_id)
        start = time.perf_counter()

        try:
            response = await call_next(request)
        except Exception:
            duration_seconds = time.perf_counter() - start
            _record_request_observation(request, status_code=500, duration_seconds=duration_seconds)
            telemetry.logger.exception(
                "request failed",
                extra=_access_log_fields(request, status_code=500, duration_seconds=duration_seconds),
            )
            raise
        else:
            response.headers.setdefault("x-correlation-id", correlation_id)
            duration_seconds = time.perf_counter() - start
            _record_request_observation(request, status_code=response.status_code, duration_seconds=duration_seconds)
            telemetry.logger.info(
                "request completed",
                extra=_access_log_fields(request, status_code=response.status_code, duration_seconds=duration_seconds),
            )
            return response
        finally:
            reset_correlation_id(token)

    @app.get("/")
    async def root_hint(request: Request) -> dict[str, Any]:
        cfg: GatewayConfig = request.app.state.gateway_config
        route_prefixes = sorted({route.path_prefix or "/" for route in cfg.routes})
        operator_console_url = os.getenv("OPERATOR_CONSOLE_URL", "http://localhost:3007")
        return {
            "service": cfg.service.display_name,
            "message": "This is an API gateway. Try /apim/health, /apim/startup, or one of the configured route prefixes.",
            "gateway_endpoints": ["/apim/health", "/apim/startup"],
            "route_prefixes": route_prefixes,
            "management": {
                "enabled": cfg.tenant_access.enabled,
                "status_path": "/apim/management/status" if cfg.tenant_access.enabled else None,
                "required_header": "X-Apim-Tenant-Key" if cfg.tenant_access.enabled else None,
            },
            "operator_console": {
                "url": operator_console_url,
                "note": "Run make up-ui to start the operator console.",
            },
        }

    @app.get("/apim/health")
    async def health() -> dict[str, str]:
        return {"status": "healthy"}

    @app.get("/apim/startup")
    async def startup(request: Request) -> dict[str, str]:
        """Startup probe endpoint - returns 200 once app is ready to serve traffic."""
        if not getattr(request.app.state, "startup_complete", False):
            raise HTTPException(status_code=503, detail="Starting up")
        return {"status": "started"}

    @app.post("/apim/reload")
    async def reload_config(request: Request) -> dict[str, Any]:
        """Reload configuration from file. Requires admin token if configured."""
        cfg: GatewayConfig = request.app.state.gateway_config
        if cfg.admin_token:
            _require_admin(request)
        reload_fn = getattr(request.app.state, "config_reload_fn", None)
        if reload_fn is None:
            raise HTTPException(status_code=500, detail="Reload not available")
        new_cfg = reload_fn()
        return {
            "status": "reloaded",
            "routes": len(new_cfg.routes),
            "products": len(new_cfg.products),
            "subscriptions": len(new_cfg.subscription.subscriptions),
        }

    @app.get("/apim/trace/{trace_id}")
    async def get_trace(trace_id: str, request: Request) -> dict[str, Any]:
        cfg: GatewayConfig = request.app.state.gateway_config
        if not cfg.trace_enabled:
            raise HTTPException(status_code=404, detail="Not found")
        if cfg.admin_token:
            _require_admin(request)

        trace_store: dict[str, Any] = request.app.state.trace_store
        entry = trace_store.get(trace_id)
        if entry is None:
            raise HTTPException(status_code=404, detail="Not found")
        return entry

    @app.get("/apim/user")
    async def current_user(request: Request) -> dict:
        cfg: GatewayConfig = request.app.state.gateway_config
        verifiers: dict[str, OIDCVerifier] = request.app.state.oidc_verifiers
        auth = authenticate_request(request, cfg, verifiers)
        return build_user_payload(auth, None, None)

    def _extract_scopes(claims: dict) -> set[str]:
        scopes: set[str] = set()
        raw = claims.get("scope") or claims.get("scp")
        if isinstance(raw, str):
            scopes.update(s for s in raw.split() if s)
        if isinstance(raw, list):
            scopes.update(str(s) for s in raw if s)
        return scopes

    def _extract_roles(claims: dict) -> set[str]:
        roles: set[str] = set()
        raw = claims.get("roles")
        if isinstance(raw, str) and raw:
            roles.add(raw)
        if isinstance(raw, list):
            roles.update(str(r) for r in raw if r)

        realm_access = claims.get("realm_access")
        if isinstance(realm_access, dict):
            rr = realm_access.get("roles")
            if isinstance(rr, list):
                roles.update(str(r) for r in rr if r)

        # Keycloak client roles typically live under resource_access.{client}.roles.
        resource_access = claims.get("resource_access")
        if isinstance(resource_access, dict):
            for entry in resource_access.values():
                if not isinstance(entry, dict):
                    continue
                cr = entry.get("roles")
                if isinstance(cr, list):
                    roles.update(str(r) for r in cr if r)
        return roles

    def _require_admin(request: Request) -> None:
        cfg: GatewayConfig = request.app.state.gateway_config
        if not cfg.admin_token:
            raise HTTPException(status_code=404, detail="Not found")
        provided = request.headers.get("x-apim-admin-token", "")
        if provided != cfg.admin_token:
            raise HTTPException(status_code=403, detail="Forbidden")

    def _require_tenant_access(request: Request) -> None:
        cfg: GatewayConfig = request.app.state.gateway_config
        if not cfg.tenant_access.enabled:
            raise HTTPException(status_code=404, detail="Not found")

        # Allow admin token as a super-user escape hatch for local dev.
        admin = request.headers.get("x-apim-admin-token", "")
        if cfg.admin_token and admin == cfg.admin_token:
            return

        provided = request.headers.get("x-apim-tenant-key", "")
        if not provided:
            raise HTTPException(status_code=403, detail="Forbidden")

        if provided == (cfg.tenant_access.primary_key or ""):
            return
        if provided == (cfg.tenant_access.secondary_key or ""):
            return
        raise HTTPException(status_code=403, detail="Forbidden")

    def _find_subscription_entry(cfg: GatewayConfig, subscription_id: str) -> tuple[str, Subscription] | None:
        for config_key, sub in cfg.subscription.subscriptions.items():
            if sub.id == subscription_id:
                return config_key, sub
        return None

    def _find_subscription_by_id(cfg: GatewayConfig, subscription_id: str) -> Subscription | None:
        entry = _find_subscription_entry(cfg, subscription_id)
        return entry[1] if entry is not None else None

    @app.post("/apim/admin/subscriptions/{subscription_id}/rotate")
    async def rotate_subscription_key(subscription_id: str, request: Request, key: str = "secondary") -> dict:
        _require_admin(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        sub = _find_subscription_by_id(cfg, subscription_id)
        if sub is None:
            raise HTTPException(status_code=404, detail="Subscription not found")
        if key not in {"primary", "secondary"}:
            raise HTTPException(status_code=400, detail="Invalid key")

        # Keep this deterministic (non-secret) so we don't accidentally commit real keys.
        new_key = f"rotated-{sub.id}-{key}"
        if key == "primary":
            sub.keys.primary = new_key
        else:
            sub.keys.secondary = new_key
        return {"subscription_id": sub.id, "subscription_name": sub.name, "rotated": key, "new_key": new_key}

    def _persist_or_apply_config(request: Request, cfg: GatewayConfig) -> GatewayConfig:
        return _require_management_plane().persist_or_apply_config(cfg)

    def _policy_scope_target(cfg: GatewayConfig, scope_type: str, scope_name: str) -> Any:
        scope = scope_type.lower()
        if scope == "gateway":
            return cfg
        if scope == "api":
            api = cfg.apis.get(scope_name)
            if api is None:
                raise HTTPException(status_code=404, detail="API policy scope not found")
            return api
        if scope == "operation":
            api_name, sep, operation_name = scope_name.partition(":")
            if not sep:
                raise HTTPException(status_code=400, detail="Operation scope must use api:operation")
            api = cfg.apis.get(api_name)
            if api is None:
                raise HTTPException(status_code=404, detail="API policy scope not found")
            operation = api.operations.get(operation_name)
            if operation is None:
                raise HTTPException(status_code=404, detail="Operation policy scope not found")
            return operation
        if scope == "route":
            if cfg.apis:
                raise HTTPException(
                    status_code=400, detail="Route policy updates are unavailable for API-backed configs"
                )
            for route in cfg.routes:
                if route.name == scope_name:
                    return route
            raise HTTPException(status_code=404, detail="Route policy scope not found")
        raise HTTPException(status_code=404, detail="Unsupported policy scope")

    def _policy_xml_for_target(target: Any) -> str:
        docs = list(getattr(target, "policies_xml_documents", []) or [])
        xml = getattr(target, "policies_xml", None)
        if xml:
            docs.append(xml)
        return _effective_policy_xml(docs)

    def _set_policy_xml(target: Any, xml: str) -> None:
        target.policies_xml = xml
        if hasattr(target, "policies_xml_documents"):
            target.policies_xml_documents = []

    def _masked(cfg: GatewayConfig, payload: Any) -> Any:
        return mask_secret_data(payload, cfg)

    def _summary_payload(cfg: GatewayConfig, request: Request | None = None) -> dict[str, Any]:
        trace_store = getattr(request.app.state, "trace_store", None) if request is not None else None
        return project_summary(cfg, trace_store=trace_store)

    def _ensure_api_authoring_mode(cfg: GatewayConfig) -> None:
        if not cfg.apis and cfg.routes:
            raise HTTPException(
                status_code=400,
                detail="API CRUD requires api-authored config; convert legacy route configs before mutating APIs.",
            )

    def _get_api_or_404(cfg: GatewayConfig, api_id: str) -> ApiConfig:
        api = cfg.apis.get(api_id)
        if api is None:
            raise HTTPException(status_code=404, detail="API not found")
        return api

    def _get_operation_or_404(cfg: GatewayConfig, api_id: str, operation_id: str) -> OperationConfig:
        api = _get_api_or_404(cfg, api_id)
        operation = api.operations.get(operation_id)
        if operation is None:
            raise HTTPException(status_code=404, detail="Operation not found")
        return operation

    def _get_api_schema_or_404(cfg: GatewayConfig, api_id: str, schema_id: str) -> ApiSchemaConfig:
        api = _get_api_or_404(cfg, api_id)
        schema = api.schemas.get(schema_id)
        if schema is None:
            raise HTTPException(status_code=404, detail="API schema not found")
        return schema

    def _get_api_revision_or_404(cfg: GatewayConfig, api_id: str, revision_id: str) -> ApiRevisionConfig:
        api = _get_api_or_404(cfg, api_id)
        revision = api.revisions.get(revision_id)
        if revision is None:
            raise HTTPException(status_code=404, detail="API revision not found")
        return revision

    def _get_api_release_or_404(cfg: GatewayConfig, api_id: str, release_id: str) -> ApiReleaseConfig:
        api = _get_api_or_404(cfg, api_id)
        release = api.releases.get(release_id)
        if release is None:
            raise HTTPException(status_code=404, detail="API release not found")
        return release

    def _get_product_or_404(cfg: GatewayConfig, product_id: str) -> ProductConfig:
        product = cfg.products.get(product_id)
        if product is None:
            raise HTTPException(status_code=404, detail="Product not found")
        return product

    def _get_group_or_404(cfg: GatewayConfig, group_id: str) -> GroupConfig:
        group = cfg.groups.get(group_id)
        if group is None:
            raise HTTPException(status_code=404, detail="Group not found")
        return group

    def _get_user_or_404(cfg: GatewayConfig, user_id: str) -> UserConfig:
        user = cfg.users.get(user_id)
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")
        return user

    def _get_tag_or_404(cfg: GatewayConfig, tag_id: str) -> TagConfig:
        tag = cfg.tags.get(tag_id)
        if tag is None:
            raise HTTPException(status_code=404, detail="Tag not found")
        return tag

    def _get_backend_or_404(cfg: GatewayConfig, backend_id: str) -> BackendConfig:
        backend = cfg.backends.get(backend_id)
        if backend is None:
            raise HTTPException(status_code=404, detail="Backend not found")
        return backend

    def _get_logger_or_404(cfg: GatewayConfig, logger_id: str) -> LoggerConfig:
        logger_entry = cfg.loggers.get(logger_id)
        if logger_entry is None:
            raise HTTPException(status_code=404, detail="Logger not found")
        return logger_entry

    def _get_diagnostic_or_404(cfg: GatewayConfig, diagnostic_id: str) -> DiagnosticConfig:
        diagnostic = cfg.diagnostics.get(diagnostic_id)
        if diagnostic is None:
            raise HTTPException(status_code=404, detail="Diagnostic not found")
        return diagnostic

    def _get_named_value_or_404(cfg: GatewayConfig, named_value_id: str) -> NamedValueConfig:
        named_value = cfg.named_values.get(named_value_id)
        if named_value is None:
            raise HTTPException(status_code=404, detail="Named value not found")
        return named_value

    def _validate_fragment_xml(xml: str) -> None:
        try:
            ElementTree.fromstring(f"<fragment>{xml}</fragment>")
        except ElementTree.ParseError as exc:
            raise HTTPException(status_code=400, detail="Invalid policy fragment XML") from exc

    def _validate_policy_xml(cfg: GatewayConfig, xml: str | None) -> None:
        if xml is None:
            return
        parse_policies_xml(xml.strip() or EMPTY_POLICY_XML, policy_fragments=cfg.policy_fragments)

    def _coerce_api_versioning_scheme(raw: str) -> ApiVersioningScheme:
        normalized = (raw or "").strip().lower()
        mapping = {
            "header": ApiVersioningScheme.Header,
            "query": ApiVersioningScheme.Query,
            "segment": ApiVersioningScheme.Segment,
        }
        scheme = mapping.get(normalized)
        if scheme is None:
            raise HTTPException(status_code=400, detail="Unsupported API versioning scheme")
        return scheme

    def _default_release_api_id(cfg: GatewayConfig, api_id: str, revision_id: str) -> str:
        return f"service/{cfg.service.name}/apis/{api_id};rev={revision_id}"

    def _set_current_revision(api: ApiConfig, revision_id: str, revision: ApiRevisionConfig) -> None:
        for candidate_id, candidate in api.revisions.items():
            candidate.is_current = candidate_id == revision_id
        api.revision = revision_id
        api.revision_description = revision.description
        api.source_api_id = revision.source_api_id
        api.is_current = True
        api.is_online = revision.is_online

    def _link_list_item(values: list[str], item_id: str) -> bool:
        if item_id in values:
            return False
        values.append(item_id)
        return True

    def _unlink_list_item(values: list[str], item_id: str) -> bool:
        if item_id not in values:
            return False
        values[:] = [item for item in values if item != item_id]
        return True

    @app.get("/apim/management/status")
    async def management_status(request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        service = project_service(cfg, trace_store=request.app.state.trace_store)
        return {
            "service": {
                "id": service["id"],
                "name": service["name"],
                "display_name": service["display_name"],
            },
            "counts": service["counts"],
            "gateway_policy_scope": service["gateway_policy_scope"],
        }

    @app.get("/apim/management/service")
    async def management_service(request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return _masked(cfg, project_service(cfg, trace_store=request.app.state.trace_store))

    @app.get("/apim/management/summary")
    async def management_summary(request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return _summary_payload(cfg, request)

    @app.get("/apim/management/apis")
    async def list_apis(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [_masked(cfg, project_api(cfg, api_id, api)) for api_id, api in cfg.apis.items()]

    @app.get("/apim/management/apis/{api_id}")
    async def get_api(api_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        api = _get_api_or_404(cfg, api_id)
        return _masked(cfg, project_api(cfg, api_id, api))

    @app.post("/apim/management/apis/{api_id}/import")
    async def import_api(api_id: str, request: Request, body: ApiImportRequest) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _ensure_api_authoring_mode(cfg)
        _validate_policy_xml(cfg, body.policies_xml)

        try:
            imported = parse_api_import(content_format=body.content_format, content_value=body.content_value)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        existing = cfg.apis.get(api_id)
        upstream_base_url = body.upstream_base_url or imported.upstream_base_url
        if not upstream_base_url and existing is not None:
            upstream_base_url = existing.upstream_base_url
        if not upstream_base_url:
            raise HTTPException(
                status_code=400,
                detail="Imported API is missing an upstream base URL; provide upstream_base_url explicitly.",
            )

        operations: dict[str, OperationConfig] = {}
        existing_operations = existing.operations if existing is not None else {}
        for imported_operation in imported.operations:
            preserved = existing_operations.get(imported_operation.name)
            operations[imported_operation.name] = OperationConfig(
                name=preserved.name if preserved is not None else imported_operation.name,
                method=imported_operation.method,
                url_template=imported_operation.url_template,
                description=preserved.description if preserved is not None else None,
                upstream_base_url=preserved.upstream_base_url if preserved is not None else None,
                upstream_path_prefix=preserved.upstream_path_prefix if preserved is not None else None,
                backend=preserved.backend if preserved is not None else None,
                products=preserved.products if preserved is not None else None,
                api_version_set=preserved.api_version_set if preserved is not None else None,
                api_version=preserved.api_version if preserved is not None else None,
                subscription_header_names=preserved.subscription_header_names if preserved is not None else None,
                subscription_query_param_names=(
                    preserved.subscription_query_param_names if preserved is not None else None
                ),
                authz=preserved.authz if preserved is not None else None,
                policies_xml=preserved.policies_xml if preserved is not None else None,
                tags=preserved.tags if preserved is not None else [],
                template_parameters=preserved.template_parameters if preserved is not None else [],
                request=preserved.request if preserved is not None else None,
                responses=preserved.responses if preserved is not None else [],
            )

        cfg.apis[api_id] = ApiConfig(
            name=body.name or (existing.name if existing is not None else api_id),
            path=body.path or (existing.path if existing is not None else api_id),
            upstream_base_url=upstream_base_url,
            upstream_path_prefix=body.upstream_path_prefix,
            backend=body.backend if body.backend is not None else (existing.backend if existing is not None else None),
            products=body.products
            if body.products is not None
            else (existing.products if existing is not None else []),
            api_version_set=(
                body.api_version_set
                if body.api_version_set is not None
                else (existing.api_version_set if existing else None)
            ),
            api_version=body.api_version
            if body.api_version is not None
            else (existing.api_version if existing else None),
            revision=existing.revision if existing is not None else None,
            revision_description=existing.revision_description if existing is not None else None,
            version_description=existing.version_description if existing is not None else None,
            source_api_id=existing.source_api_id if existing is not None else None,
            is_current=existing.is_current if existing is not None else None,
            is_online=existing.is_online if existing is not None else None,
            subscription_header_names=(
                body.subscription_header_names
                if body.subscription_header_names is not None
                else (existing.subscription_header_names if existing else None)
            ),
            subscription_query_param_names=(
                body.subscription_query_param_names
                if body.subscription_query_param_names is not None
                else (existing.subscription_query_param_names if existing else None)
            ),
            policies_xml=body.policies_xml
            if body.policies_xml is not None
            else (existing.policies_xml if existing else None),
            tags=existing.tags if existing is not None else [],
            operations=operations,
            schemas=existing.schemas if existing is not None else {},
            revisions=existing.revisions if existing is not None else {},
            releases=existing.releases if existing is not None else {},
        )
        updated = _persist_or_apply_config(request, cfg)
        api = _get_api_or_404(updated, api_id)
        return {
            "api": _masked(updated, project_api(updated, api_id, api)),
            "import": {
                "format": imported.format,
                "operation_count": len(imported.operations),
                "upstream_base_url": imported.upstream_base_url,
                "diagnostics": imported.diagnostics,
            },
        }

    @app.put("/apim/management/apis/{api_id}")
    async def upsert_api(api_id: str, request: Request, body: ApiUpsert) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _ensure_api_authoring_mode(cfg)
        _validate_policy_xml(cfg, body.policies_xml)
        existing = cfg.apis.get(api_id)
        cfg.apis[api_id] = ApiConfig(
            name=body.name or api_id,
            path=body.path,
            upstream_base_url=body.upstream_base_url,
            upstream_path_prefix=body.upstream_path_prefix,
            backend=body.backend,
            products=body.products,
            api_version_set=body.api_version_set,
            api_version=body.api_version,
            revision=existing.revision if existing is not None else None,
            revision_description=existing.revision_description if existing is not None else None,
            version_description=existing.version_description if existing is not None else None,
            source_api_id=existing.source_api_id if existing is not None else None,
            is_current=existing.is_current if existing is not None else None,
            is_online=existing.is_online if existing is not None else None,
            subscription_header_names=body.subscription_header_names,
            subscription_query_param_names=body.subscription_query_param_names,
            policies_xml=body.policies_xml,
            tags=existing.tags if existing is not None else [],
            operations=existing.operations if existing is not None else {},
            schemas=existing.schemas if existing is not None else {},
            revisions=existing.revisions if existing is not None else {},
            releases=existing.releases if existing is not None else {},
        )
        updated = _persist_or_apply_config(request, cfg)
        api = _get_api_or_404(updated, api_id)
        return _masked(updated, project_api(updated, api_id, api))

    @app.delete("/apim/management/apis/{api_id}")
    async def delete_api(api_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _ensure_api_authoring_mode(cfg)
        _get_api_or_404(cfg, api_id)
        del cfg.apis[api_id]
        updated = _persist_or_apply_config(request, cfg)
        return {"deleted": True, "api_id": api_id, "remaining": len(updated.apis)}

    @app.get("/apim/management/operations")
    async def list_operations(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        operations: list[dict[str, Any]] = []
        for api_id, api in cfg.apis.items():
            for operation_id, operation in api.operations.items():
                operations.append(_masked(cfg, project_operation(cfg, api_id, operation_id, operation)))
        return operations

    @app.get("/apim/management/apis/{api_id}/operations")
    async def list_api_operations(api_id: str, request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        api = _get_api_or_404(cfg, api_id)
        return [
            _masked(cfg, project_operation(cfg, api_id, operation_id, operation))
            for operation_id, operation in api.operations.items()
        ]

    @app.get("/apim/management/apis/{api_id}/schemas")
    async def list_api_schemas(api_id: str, request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        api = _get_api_or_404(cfg, api_id)
        return [
            _masked(cfg, project_api_schema(cfg, api_id, schema_id, schema))
            for schema_id, schema in api.schemas.items()
        ]

    @app.get("/apim/management/apis/{api_id}/revisions")
    async def list_api_revisions(api_id: str, request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        api = _get_api_or_404(cfg, api_id)
        return [
            _masked(cfg, project_api_revision(cfg, api_id, revision_id, revision))
            for revision_id, revision in api.revisions.items()
        ]

    @app.get("/apim/management/apis/{api_id}/revisions/{revision_id}")
    async def get_api_revision(api_id: str, revision_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        revision = _get_api_revision_or_404(cfg, api_id, revision_id)
        return _masked(cfg, project_api_revision(cfg, api_id, revision_id, revision))

    @app.put("/apim/management/apis/{api_id}/revisions/{revision_id}")
    async def upsert_api_revision(
        api_id: str, revision_id: str, request: Request, body: ApiRevisionUpsert
    ) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _ensure_api_authoring_mode(cfg)
        api = _get_api_or_404(cfg, api_id)
        existing = api.revisions.get(revision_id)
        revision = ApiRevisionConfig(
            revision=revision_id,
            description=body.description
            if body.description is not None
            else (existing.description if existing else None),
            is_current=body.is_current if body.is_current is not None else (existing.is_current if existing else None),
            is_online=body.is_online if body.is_online is not None else (existing.is_online if existing else None),
            source_api_id=(
                body.source_api_id if body.source_api_id is not None else (existing.source_api_id if existing else None)
            ),
        )
        api.revisions[revision_id] = revision
        if revision.is_current:
            _set_current_revision(api, revision_id, revision)
        updated = _persist_or_apply_config(request, cfg)
        stored = _get_api_revision_or_404(updated, api_id, revision_id)
        return _masked(updated, project_api_revision(updated, api_id, revision_id, stored))

    @app.delete("/apim/management/apis/{api_id}/revisions/{revision_id}")
    async def delete_api_revision(api_id: str, revision_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _ensure_api_authoring_mode(cfg)
        api = _get_api_or_404(cfg, api_id)
        revision = _get_api_revision_or_404(cfg, api_id, revision_id)
        if revision.is_current or api.revision == revision_id:
            raise HTTPException(status_code=409, detail="Current API revision cannot be deleted")
        for release_id, release in api.releases.items():
            if release.revision == revision_id:
                raise HTTPException(
                    status_code=409,
                    detail=f"API revision is still referenced by release {release_id}",
                )
        del api.revisions[revision_id]
        updated = _persist_or_apply_config(request, cfg)
        return {
            "deleted": True,
            "api_id": api_id,
            "revision_id": revision_id,
            "remaining": len(updated.apis[api_id].revisions),
        }

    @app.get("/apim/management/apis/{api_id}/releases")
    async def list_api_releases(api_id: str, request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        api = _get_api_or_404(cfg, api_id)
        return [
            _masked(cfg, project_api_release(cfg, api_id, release_id, release))
            for release_id, release in api.releases.items()
        ]

    @app.get("/apim/management/apis/{api_id}/releases/{release_id}")
    async def get_api_release(api_id: str, release_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        release = _get_api_release_or_404(cfg, api_id, release_id)
        return _masked(cfg, project_api_release(cfg, api_id, release_id, release))

    @app.put("/apim/management/apis/{api_id}/releases/{release_id}")
    async def upsert_api_release(
        api_id: str, release_id: str, request: Request, body: ApiReleaseUpsert
    ) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _ensure_api_authoring_mode(cfg)
        api = _get_api_or_404(cfg, api_id)
        if body.revision not in api.revisions:
            raise HTTPException(status_code=404, detail="API revision not found")
        existing = api.releases.get(release_id)
        api.releases[release_id] = ApiReleaseConfig(
            name=body.name or (existing.name if existing is not None else release_id),
            api_id=body.api_id or _default_release_api_id(cfg, api_id, body.revision),
            notes=body.notes if body.notes is not None else (existing.notes if existing is not None else None),
            revision=body.revision,
        )
        updated = _persist_or_apply_config(request, cfg)
        stored = _get_api_release_or_404(updated, api_id, release_id)
        return _masked(updated, project_api_release(updated, api_id, release_id, stored))

    @app.delete("/apim/management/apis/{api_id}/releases/{release_id}")
    async def delete_api_release(api_id: str, release_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _ensure_api_authoring_mode(cfg)
        api = _get_api_or_404(cfg, api_id)
        _get_api_release_or_404(cfg, api_id, release_id)
        del api.releases[release_id]
        updated = _persist_or_apply_config(request, cfg)
        return {
            "deleted": True,
            "api_id": api_id,
            "release_id": release_id,
            "remaining": len(updated.apis[api_id].releases),
        }

    @app.get("/apim/management/apis/{api_id}/tags")
    async def list_api_tags(api_id: str, request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        api = _get_api_or_404(cfg, api_id)
        return [
            _masked(cfg, project_api_tag_link(cfg, api_id, tag_id, _get_tag_or_404(cfg, tag_id))) for tag_id in api.tags
        ]

    @app.get("/apim/management/apis/{api_id}/tags/{tag_id}")
    async def get_api_tag(api_id: str, tag_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        api = _get_api_or_404(cfg, api_id)
        if tag_id not in api.tags:
            raise HTTPException(status_code=404, detail="API tag link not found")
        return _masked(cfg, project_api_tag_link(cfg, api_id, tag_id, _get_tag_or_404(cfg, tag_id)))

    @app.put("/apim/management/apis/{api_id}/tags/{tag_id}")
    async def put_api_tag(api_id: str, tag_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        api = _get_api_or_404(cfg, api_id)
        _get_tag_or_404(cfg, tag_id)
        _link_list_item(api.tags, tag_id)
        updated = _persist_or_apply_config(request, cfg)
        return _masked(updated, project_api_tag_link(updated, api_id, tag_id, updated.tags[tag_id]))

    @app.delete("/apim/management/apis/{api_id}/tags/{tag_id}")
    async def delete_api_tag(api_id: str, tag_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        api = _get_api_or_404(cfg, api_id)
        if not _unlink_list_item(api.tags, tag_id):
            raise HTTPException(status_code=404, detail="API tag link not found")
        _persist_or_apply_config(request, cfg)
        return {"deleted": True, "api_id": api_id, "tag_id": tag_id}

    @app.get("/apim/management/apis/{api_id}/schemas/{schema_id}")
    async def get_api_schema(api_id: str, schema_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        schema = _get_api_schema_or_404(cfg, api_id, schema_id)
        return _masked(cfg, project_api_schema(cfg, api_id, schema_id, schema))

    @app.get("/apim/management/apis/{api_id}/operations/{operation_id}")
    async def get_api_operation(api_id: str, operation_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        operation = _get_operation_or_404(cfg, api_id, operation_id)
        return _masked(cfg, project_operation(cfg, api_id, operation_id, operation))

    @app.get("/apim/management/apis/{api_id}/operations/{operation_id}/tags")
    async def list_api_operation_tags(api_id: str, operation_id: str, request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        operation = _get_operation_or_404(cfg, api_id, operation_id)
        return [
            _masked(cfg, project_operation_tag_link(cfg, api_id, operation_id, tag_id, _get_tag_or_404(cfg, tag_id)))
            for tag_id in operation.tags
        ]

    @app.get("/apim/management/apis/{api_id}/operations/{operation_id}/tags/{tag_id}")
    async def get_api_operation_tag(api_id: str, operation_id: str, tag_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        operation = _get_operation_or_404(cfg, api_id, operation_id)
        if tag_id not in operation.tags:
            raise HTTPException(status_code=404, detail="Operation tag link not found")
        return _masked(
            cfg,
            project_operation_tag_link(cfg, api_id, operation_id, tag_id, _get_tag_or_404(cfg, tag_id)),
        )

    @app.put("/apim/management/apis/{api_id}/operations/{operation_id}/tags/{tag_id}")
    async def put_api_operation_tag(api_id: str, operation_id: str, tag_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        operation = _get_operation_or_404(cfg, api_id, operation_id)
        _get_tag_or_404(cfg, tag_id)
        _link_list_item(operation.tags, tag_id)
        updated = _persist_or_apply_config(request, cfg)
        return _masked(
            updated,
            project_operation_tag_link(updated, api_id, operation_id, tag_id, updated.tags[tag_id]),
        )

    @app.delete("/apim/management/apis/{api_id}/operations/{operation_id}/tags/{tag_id}")
    async def delete_api_operation_tag(api_id: str, operation_id: str, tag_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        operation = _get_operation_or_404(cfg, api_id, operation_id)
        if not _unlink_list_item(operation.tags, tag_id):
            raise HTTPException(status_code=404, detail="Operation tag link not found")
        _persist_or_apply_config(request, cfg)
        return {"deleted": True, "api_id": api_id, "operation_id": operation_id, "tag_id": tag_id}

    @app.put("/apim/management/apis/{api_id}/operations/{operation_id}")
    async def upsert_api_operation(
        api_id: str, operation_id: str, request: Request, body: OperationUpsert
    ) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _ensure_api_authoring_mode(cfg)
        api = _get_api_or_404(cfg, api_id)
        _validate_policy_xml(cfg, body.policies_xml)
        existing = api.operations.get(operation_id)
        api.operations[operation_id] = OperationConfig(
            name=body.name or (existing.name if existing is not None else operation_id),
            method=body.method,
            url_template=body.url_template,
            description=body.description
            if body.description is not None
            else (existing.description if existing else None),
            upstream_base_url=body.upstream_base_url,
            upstream_path_prefix=body.upstream_path_prefix,
            backend=body.backend,
            products=body.products,
            api_version_set=body.api_version_set,
            api_version=body.api_version,
            subscription_header_names=body.subscription_header_names,
            subscription_query_param_names=body.subscription_query_param_names,
            authz=body.authz,
            policies_xml=body.policies_xml,
            tags=body.tags if body.tags is not None else (existing.tags if existing is not None else []),
            template_parameters=(
                body.template_parameters
                if body.template_parameters is not None
                else (existing.template_parameters if existing is not None else [])
            ),
            request=body.request if body.request is not None else (existing.request if existing is not None else None),
            responses=body.responses
            if body.responses is not None
            else (existing.responses if existing is not None else []),
        )
        updated = _persist_or_apply_config(request, cfg)
        operation = _get_operation_or_404(updated, api_id, operation_id)
        return _masked(updated, project_operation(updated, api_id, operation_id, operation))

    @app.delete("/apim/management/apis/{api_id}/operations/{operation_id}")
    async def delete_api_operation(api_id: str, operation_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _ensure_api_authoring_mode(cfg)
        api = _get_api_or_404(cfg, api_id)
        _get_operation_or_404(cfg, api_id, operation_id)
        del api.operations[operation_id]
        updated = _persist_or_apply_config(request, cfg)
        return {
            "deleted": True,
            "api_id": api_id,
            "operation_id": operation_id,
            "remaining": len(updated.apis[api_id].operations),
        }

    @app.get("/apim/management/policies/{scope_type}/{scope_name:path}")
    async def management_get_policy(scope_type: str, scope_name: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        target = _policy_scope_target(cfg, scope_type, scope_name)
        return {
            "scope_type": scope_type,
            "scope_name": scope_name,
            "xml": _policy_xml_for_target(target),
        }

    @app.put("/apim/management/policies/{scope_type}/{scope_name:path}")
    async def management_put_policy(
        scope_type: str,
        scope_name: str,
        request: Request,
        body: PolicyUpdate,
    ) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        xml = body.xml.strip() or EMPTY_POLICY_XML
        parse_policies_xml(xml, policy_fragments=cfg.policy_fragments)
        target = _policy_scope_target(cfg, scope_type, scope_name)
        _set_policy_xml(target, xml)
        updated = _persist_or_apply_config(request, cfg)
        return {
            "scope_type": scope_type,
            "scope_name": scope_name,
            "xml": _policy_xml_for_target(_policy_scope_target(updated, scope_type, scope_name)),
        }

    @app.get("/apim/management/traces")
    async def management_traces(request: Request, limit: int = 50) -> dict[str, Any]:
        _require_tenant_access(request)
        trace_store: dict[str, Any] = request.app.state.trace_store
        items = sorted(trace_store.values(), key=lambda item: item.get("created_at", ""), reverse=True)
        return {"items": items[: max(1, min(limit, 200))]}

    @app.post("/apim/management/replay")
    async def management_replay(request: Request, body: ReplayRequestBody) -> dict[str, Any]:
        _require_tenant_access(request)
        path = body.path if body.path.startswith("/") else f"/{body.path}"
        if path.startswith("/apim/management") or path.startswith("/apim/admin"):
            raise HTTPException(status_code=400, detail="Replay path must target gateway routes")

        headers = dict(body.headers)
        headers.setdefault("x-apim-trace", "true")
        content = b""
        if body.body_base64 is not None:
            try:
                content = base64.b64decode(body.body_base64)
            except ValueError as exc:
                raise HTTPException(status_code=400, detail="Invalid base64 replay body") from exc
        elif body.body_text is not None:
            content = body.body_text.encode("utf-8")

        transport = httpx.ASGITransport(app=request.app)
        async with httpx.AsyncClient(transport=transport, base_url="https://apim-replay.local") as replay_client:
            response = await replay_client.request(
                body.method.upper(),
                path,
                params=body.query,
                headers=headers,
                content=content,
            )

        trace_id = response.headers.get("x-apim-trace-id")
        decoded = _decode_body(response.content)
        return {
            "request": body.model_dump(),
            "response": {
                "status_code": response.status_code,
                "headers": dict(response.headers),
                "body_text": decoded["text"],
                "body_base64": decoded["base64"],
            },
            "trace_id": trace_id,
            "trace": request.app.state.trace_store.get(trace_id) if trace_id else None,
        }

    @app.get("/apim/management/products")
    async def list_products(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [_masked(cfg, project_product(cfg, product_id, product)) for product_id, product in cfg.products.items()]

    @app.get("/apim/management/products/{product_id}")
    async def get_product(product_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        product = _get_product_or_404(cfg, product_id)
        return _masked(cfg, project_product(cfg, product_id, product))

    @app.put("/apim/management/products/{product_id}")
    async def upsert_product(product_id: str, request: Request, body: ProductUpsert) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        updated = _require_management_plane().upsert_product(cfg, product_id, body)
        product = _get_product_or_404(updated, product_id)
        return _masked(updated, project_product(updated, product_id, product))

    @app.delete("/apim/management/products/{product_id}")
    async def delete_product(product_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        updated = _require_management_plane().delete_product(cfg, product_id)
        return {"deleted": True, "product_id": product_id, "remaining": len(updated.products)}

    @app.get("/apim/management/products/{product_id}/groups")
    async def list_product_groups(product_id: str, request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        product = _get_product_or_404(cfg, product_id)
        return [
            _masked(cfg, project_product_group_link(cfg, product_id, group_id, _get_group_or_404(cfg, group_id)))
            for group_id in product.groups
        ]

    @app.get("/apim/management/products/{product_id}/groups/{group_id}")
    async def get_product_group(product_id: str, group_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        product = _get_product_or_404(cfg, product_id)
        if group_id not in product.groups:
            raise HTTPException(status_code=404, detail="Product group link not found")
        return _masked(cfg, project_product_group_link(cfg, product_id, group_id, _get_group_or_404(cfg, group_id)))

    @app.put("/apim/management/products/{product_id}/groups/{group_id}")
    async def put_product_group(product_id: str, group_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        product = _get_product_or_404(cfg, product_id)
        _get_group_or_404(cfg, group_id)
        _link_list_item(product.groups, group_id)
        updated = _persist_or_apply_config(request, cfg)
        return _masked(updated, project_product_group_link(updated, product_id, group_id, updated.groups[group_id]))

    @app.delete("/apim/management/products/{product_id}/groups/{group_id}")
    async def delete_product_group(product_id: str, group_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        product = _get_product_or_404(cfg, product_id)
        if not _unlink_list_item(product.groups, group_id):
            raise HTTPException(status_code=404, detail="Product group link not found")
        _persist_or_apply_config(request, cfg)
        return {"deleted": True, "product_id": product_id, "group_id": group_id}

    @app.get("/apim/management/products/{product_id}/tags")
    async def list_product_tags(product_id: str, request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        product = _get_product_or_404(cfg, product_id)
        return [
            _masked(cfg, project_product_tag_link(cfg, product_id, tag_id, _get_tag_or_404(cfg, tag_id)))
            for tag_id in product.tags
        ]

    @app.get("/apim/management/products/{product_id}/tags/{tag_id}")
    async def get_product_tag(product_id: str, tag_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        product = _get_product_or_404(cfg, product_id)
        if tag_id not in product.tags:
            raise HTTPException(status_code=404, detail="Product tag link not found")
        return _masked(cfg, project_product_tag_link(cfg, product_id, tag_id, _get_tag_or_404(cfg, tag_id)))

    @app.put("/apim/management/products/{product_id}/tags/{tag_id}")
    async def put_product_tag(product_id: str, tag_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        product = _get_product_or_404(cfg, product_id)
        _get_tag_or_404(cfg, tag_id)
        _link_list_item(product.tags, tag_id)
        updated = _persist_or_apply_config(request, cfg)
        return _masked(updated, project_product_tag_link(updated, product_id, tag_id, updated.tags[tag_id]))

    @app.delete("/apim/management/products/{product_id}/tags/{tag_id}")
    async def delete_product_tag(product_id: str, tag_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        product = _get_product_or_404(cfg, product_id)
        if not _unlink_list_item(product.tags, tag_id):
            raise HTTPException(status_code=404, detail="Product tag link not found")
        _persist_or_apply_config(request, cfg)
        return {"deleted": True, "product_id": product_id, "tag_id": tag_id}

    @app.get("/apim/management/tags")
    async def list_tags(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [_masked(cfg, project_tag(cfg, tag_id, tag)) for tag_id, tag in cfg.tags.items()]

    @app.get("/apim/management/tags/{tag_id}")
    async def get_tag(tag_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        tag = _get_tag_or_404(cfg, tag_id)
        return _masked(cfg, project_tag(cfg, tag_id, tag))

    @app.put("/apim/management/tags/{tag_id}")
    async def upsert_tag(tag_id: str, request: Request, body: TagUpsert) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        updated = _require_management_plane().upsert_tag(cfg, tag_id, body)
        tag = _get_tag_or_404(updated, tag_id)
        return _masked(updated, project_tag(updated, tag_id, tag))

    @app.delete("/apim/management/tags/{tag_id}")
    async def delete_tag(tag_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        updated = _require_management_plane().delete_tag(cfg, tag_id)
        return {"deleted": True, "tag_id": tag_id, "remaining": len(updated.tags)}

    @app.get("/apim/management/subscriptions")
    async def list_subscriptions(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [
            _masked(cfg, project_subscription(cfg, config_key, subscription))
            for config_key, subscription in cfg.subscription.subscriptions.items()
        ]

    @app.get("/apim/management/subscriptions/{subscription_id}")
    async def get_subscription(subscription_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        entry = _find_subscription_entry(cfg, subscription_id)
        if entry is None:
            raise HTTPException(status_code=404, detail="Subscription not found")
        config_key, subscription = entry
        return _masked(cfg, project_subscription(cfg, config_key, subscription))

    @app.post("/apim/management/subscriptions")
    async def create_subscription(request: Request, body: SubscriptionUpsert) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        manager = _require_management_plane()
        updated = manager.create_subscription(cfg, body)
        entry = manager.find_subscription_entry(updated, body.id)
        if entry is None:
            raise HTTPException(status_code=500, detail="Subscription persistence failed")
        config_key, subscription = entry
        return _masked(updated, project_subscription(updated, config_key, subscription))

    @app.patch("/apim/management/subscriptions/{subscription_id}")
    async def update_subscription(request: Request, subscription_id: str, body: SubscriptionUpdate) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        manager = _require_management_plane()
        updated = manager.update_subscription(cfg, subscription_id, body)
        entry = manager.find_subscription_entry(updated, subscription_id)
        if entry is None:
            raise HTTPException(status_code=500, detail="Subscription persistence failed")
        config_key, subscription = entry
        return _masked(updated, project_subscription(updated, config_key, subscription))

    @app.delete("/apim/management/subscriptions/{subscription_id}")
    async def delete_subscription(subscription_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        updated = _require_management_plane().delete_subscription(cfg, subscription_id)
        return {
            "deleted": True,
            "subscription_id": subscription_id,
            "remaining": len(updated.subscription.subscriptions),
        }

    @app.post("/apim/management/subscriptions/{subscription_id}/rotate")
    async def management_rotate_subscription_key(
        subscription_id: str, request: Request, key: str = "secondary"
    ) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        manager = _require_management_plane()
        updated, new_key = manager.rotate_subscription_key(cfg, subscription_id, key)
        entry = manager.find_subscription_entry(updated, subscription_id)
        if entry is None:
            raise HTTPException(status_code=500, detail="Subscription persistence failed")
        config_key, subscription = entry
        return {
            "subscription_id": subscription.id,
            "subscription_name": subscription.name,
            "rotated": key,
            "new_key": new_key,
            "subscription": _masked(updated, project_subscription(updated, config_key, subscription)),
        }

    @app.get("/apim/management/backends")
    async def list_backends(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [_masked(cfg, project_backend(cfg, backend_id, backend)) for backend_id, backend in cfg.backends.items()]

    @app.get("/apim/management/backends/{backend_id}")
    async def get_backend(backend_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        backend = _get_backend_or_404(cfg, backend_id)
        return _masked(cfg, project_backend(cfg, backend_id, backend))

    @app.put("/apim/management/backends/{backend_id}")
    async def upsert_backend(backend_id: str, request: Request, body: BackendUpsert) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        cfg.backends[backend_id] = BackendConfig(**body.model_dump(mode="json"))
        updated = _persist_or_apply_config(request, cfg)
        backend = _get_backend_or_404(updated, backend_id)
        return _masked(updated, project_backend(updated, backend_id, backend))

    @app.delete("/apim/management/backends/{backend_id}")
    async def delete_backend(backend_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _get_backend_or_404(cfg, backend_id)
        del cfg.backends[backend_id]
        updated = _persist_or_apply_config(request, cfg)
        return {"deleted": True, "backend_id": backend_id, "remaining": len(updated.backends)}

    @app.get("/apim/management/named-values")
    async def list_named_values(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [
            _masked(cfg, project_named_value(cfg, named_value_id, named_value))
            for named_value_id, named_value in cfg.named_values.items()
        ]

    @app.get("/apim/management/named-values/{named_value_id}")
    async def get_named_value(named_value_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        named_value = _get_named_value_or_404(cfg, named_value_id)
        return _masked(cfg, project_named_value(cfg, named_value_id, named_value))

    @app.get("/apim/management/loggers")
    async def list_loggers(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [_masked(cfg, project_logger(cfg, logger_id, logger)) for logger_id, logger in cfg.loggers.items()]

    @app.get("/apim/management/loggers/{logger_id}")
    async def get_logger(logger_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        logger_entry = _get_logger_or_404(cfg, logger_id)
        return _masked(cfg, project_logger(cfg, logger_id, logger_entry))

    @app.get("/apim/management/diagnostics")
    async def list_diagnostics(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [
            _masked(cfg, project_diagnostic(cfg, diagnostic_id, diagnostic))
            for diagnostic_id, diagnostic in cfg.diagnostics.items()
        ]

    @app.get("/apim/management/diagnostics/{diagnostic_id}")
    async def get_diagnostic(diagnostic_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        diagnostic = _get_diagnostic_or_404(cfg, diagnostic_id)
        return _masked(cfg, project_diagnostic(cfg, diagnostic_id, diagnostic))

    @app.put("/apim/management/named-values/{named_value_id}")
    async def upsert_named_value(named_value_id: str, request: Request, body: NamedValueUpsert) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        cfg.named_values[named_value_id] = NamedValueConfig(**body.model_dump(mode="json"))
        updated = _persist_or_apply_config(request, cfg)
        named_value = _get_named_value_or_404(updated, named_value_id)
        return _masked(updated, project_named_value(updated, named_value_id, named_value))

    @app.delete("/apim/management/named-values/{named_value_id}")
    async def delete_named_value(named_value_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _get_named_value_or_404(cfg, named_value_id)
        del cfg.named_values[named_value_id]
        updated = _persist_or_apply_config(request, cfg)
        return {"deleted": True, "named_value_id": named_value_id, "remaining": len(updated.named_values)}

    @app.get("/apim/management/api-version-sets")
    async def list_api_version_sets(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [
            _masked(cfg, project_api_version_set(cfg, version_set_id, version_set))
            for version_set_id, version_set in cfg.api_version_sets.items()
        ]

    @app.get("/apim/management/api-version-sets/{version_set_id}")
    async def get_api_version_set(version_set_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        version_set = cfg.api_version_sets.get(version_set_id)
        if version_set is None:
            raise HTTPException(status_code=404, detail="API version set not found")
        return _masked(cfg, project_api_version_set(cfg, version_set_id, version_set))

    @app.put("/apim/management/api-version-sets/{version_set_id}")
    async def upsert_api_version_set(
        version_set_id: str, request: Request, body: ApiVersionSetUpsert
    ) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _ensure_api_authoring_mode(cfg)
        cfg.api_version_sets[version_set_id] = ApiVersionSetConfig(
            display_name=body.display_name,
            description=body.description,
            versioning_scheme=_coerce_api_versioning_scheme(body.versioning_scheme),
            version_header_name=body.version_header_name,
            version_query_name=body.version_query_name,
            default_version=body.default_version,
        )
        updated = _persist_or_apply_config(request, cfg)
        return _masked(
            updated,
            project_api_version_set(updated, version_set_id, updated.api_version_sets[version_set_id]),
        )

    @app.delete("/apim/management/api-version-sets/{version_set_id}")
    async def delete_api_version_set(version_set_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _ensure_api_authoring_mode(cfg)
        version_set = cfg.api_version_sets.get(version_set_id)
        if version_set is None:
            raise HTTPException(status_code=404, detail="API version set not found")

        for api_id, api in cfg.apis.items():
            if api.api_version_set == version_set_id:
                raise HTTPException(
                    status_code=409,
                    detail=f"API version set is still in use by API {api_id}",
                )
            for operation_id, operation in api.operations.items():
                if operation.api_version_set == version_set_id:
                    raise HTTPException(
                        status_code=409,
                        detail=f"API version set is still in use by operation {api_id}:{operation_id}",
                    )

        del cfg.api_version_sets[version_set_id]
        updated = _persist_or_apply_config(request, cfg)
        return {"deleted": True, "version_set_id": version_set_id, "remaining": len(updated.api_version_sets)}

    @app.get("/apim/management/policy-fragments")
    async def list_policy_fragments(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [
            _masked(cfg, project_policy_fragment(cfg, fragment_id, xml))
            for fragment_id, xml in cfg.policy_fragments.items()
        ]

    @app.get("/apim/management/policy-fragments/{fragment_id}")
    async def get_policy_fragment(fragment_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        xml = cfg.policy_fragments.get(fragment_id)
        if xml is None:
            raise HTTPException(status_code=404, detail="Policy fragment not found")
        return _masked(cfg, project_policy_fragment(cfg, fragment_id, xml))

    @app.put("/apim/management/policy-fragments/{fragment_id}")
    async def upsert_policy_fragment(fragment_id: str, request: Request, body: PolicyFragmentUpsert) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        _validate_fragment_xml(body.xml)
        cfg.policy_fragments[fragment_id] = body.xml
        updated = _persist_or_apply_config(request, cfg)
        return _masked(updated, project_policy_fragment(updated, fragment_id, updated.policy_fragments[fragment_id]))

    @app.delete("/apim/management/policy-fragments/{fragment_id}")
    async def delete_policy_fragment(fragment_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        if fragment_id not in cfg.policy_fragments:
            raise HTTPException(status_code=404, detail="Policy fragment not found")
        del cfg.policy_fragments[fragment_id]
        updated = _persist_or_apply_config(request, cfg)
        return {"deleted": True, "fragment_id": fragment_id, "remaining": len(updated.policy_fragments)}

    @app.get("/apim/management/users")
    async def list_users(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [_masked(cfg, project_user(cfg, user_id, user)) for user_id, user in cfg.users.items()]

    @app.get("/apim/management/users/{user_id}")
    async def get_user(user_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        user = _get_user_or_404(cfg, user_id)
        return _masked(cfg, project_user(cfg, user_id, user))

    @app.put("/apim/management/users/{user_id}")
    async def upsert_user(user_id: str, request: Request, body: UserUpsert) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        updated = _require_management_plane().upsert_user(cfg, user_id, body)
        user = _get_user_or_404(updated, user_id)
        return _masked(updated, project_user(updated, user_id, user))

    @app.delete("/apim/management/users/{user_id}")
    async def delete_user(user_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        updated = _require_management_plane().delete_user(cfg, user_id)
        return {"deleted": True, "user_id": user_id, "remaining": len(updated.users)}

    @app.get("/apim/management/groups")
    async def list_groups(request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [_masked(cfg, project_group(cfg, group_id, group)) for group_id, group in cfg.groups.items()]

    @app.get("/apim/management/groups/{group_id}/users")
    async def list_group_users(group_id: str, request: Request) -> list[dict[str, Any]]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        group = _get_group_or_404(cfg, group_id)
        return [
            _masked(cfg, project_group_user_link(cfg, group_id, user_id, _get_user_or_404(cfg, user_id)))
            for user_id in group.users
        ]

    @app.get("/apim/management/groups/{group_id}/users/{user_id}")
    async def get_group_user(group_id: str, user_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        group = _get_group_or_404(cfg, group_id)
        if user_id not in group.users:
            raise HTTPException(status_code=404, detail="Group user link not found")
        return _masked(cfg, project_group_user_link(cfg, group_id, user_id, _get_user_or_404(cfg, user_id)))

    @app.put("/apim/management/groups/{group_id}/users/{user_id}")
    async def put_group_user(group_id: str, user_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        group = _get_group_or_404(cfg, group_id)
        _get_user_or_404(cfg, user_id)
        _link_list_item(group.users, user_id)
        updated = _persist_or_apply_config(request, cfg)
        return _masked(updated, project_group_user_link(updated, group_id, user_id, updated.users[user_id]))

    @app.delete("/apim/management/groups/{group_id}/users/{user_id}")
    async def delete_group_user(group_id: str, user_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        group = _get_group_or_404(cfg, group_id)
        if not _unlink_list_item(group.users, user_id):
            raise HTTPException(status_code=404, detail="Group user link not found")
        _persist_or_apply_config(request, cfg)
        return {"deleted": True, "group_id": group_id, "user_id": user_id}

    @app.get("/apim/management/groups/{group_id}")
    async def get_group(group_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        group = _get_group_or_404(cfg, group_id)
        return _masked(cfg, project_group(cfg, group_id, group))

    @app.put("/apim/management/groups/{group_id}")
    async def upsert_group(group_id: str, request: Request, body: GroupUpsert) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        updated = _require_management_plane().upsert_group(cfg, group_id, body)
        group = _get_group_or_404(updated, group_id)
        return _masked(updated, project_group(updated, group_id, group))

    @app.delete("/apim/management/groups/{group_id}")
    async def delete_group(group_id: str, request: Request) -> dict[str, Any]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        updated = _require_management_plane().delete_group(cfg, group_id)
        return {"deleted": True, "group_id": group_id, "remaining": len(updated.groups)}

    @app.post("/apim/management/import/tofu-show")
    async def import_tofu_show_json(request: Request, tf: dict[str, Any]) -> dict:
        _require_tenant_access(request)

        current: GatewayConfig = request.app.state.gateway_config
        result = import_from_tofu_show_json(tf)
        imported = result.config

        # Preserve local runtime settings.
        imported.allowed_origins = current.allowed_origins
        imported.allow_anonymous = current.allow_anonymous
        imported.oidc = current.oidc
        imported.oidc_providers = current.oidc_providers
        imported.admin_token = current.admin_token
        imported.tenant_access = current.tenant_access
        imported.trace_enabled = current.trace_enabled
        imported.policy_fragments = current.policy_fragments
        imported_client_certificate_mode = imported.client_certificate.mode
        imported.client_certificate = current.client_certificate.model_copy(deep=True)
        if imported_client_certificate_mode.value != "disabled":
            imported.client_certificate.mode = imported_client_certificate_mode
        if not result.service_imported:
            imported.service = current.service

        _require_management_plane().apply_runtime_config(imported)
        request.app.state.cache = {}
        request.app.state.policy_cache = {}
        request.app.state.policy_response_cache = {}
        request.app.state.policy_value_cache = {}
        request.app.state.rate_limit_store = {}
        request.app.state.quota_store = {}
        request.app.state.trace_store = {}

        return {
            "routes": len(imported.routes),
            "products": len(imported.products),
            "loggers": len(imported.loggers),
            "apim_diagnostics": len(imported.diagnostics),
            "groups": len(imported.groups),
            "tags": len(imported.tags),
            "subscriptions": len(imported.subscription.subscriptions),
            "apis": len(imported.apis),
            "api_revisions": sum(len(api.revisions) for api in imported.apis.values()),
            "api_releases": sum(len(api.releases) for api in imported.apis.values()),
            "diagnostics": [item.__dict__ for item in result.diagnostics],
        }

    @app.api_route("/{full_path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
    async def gateway_proxy(full_path: str, request: Request) -> Response:
        if request.method == "OPTIONS":
            return Response(status_code=204)

        cfg: GatewayConfig = request.app.state.gateway_config
        gateway_metrics: GatewayMetrics = request.app.state.gateway_metrics

        # mTLS validation (before route resolution)
        validate_client_certificate(request, cfg)

        resolved = resolve_route(cfg, request)
        if resolved is None:
            request.state.apim_result_reason = "no_route"
            raise HTTPException(status_code=404, detail="No route")
        route = resolved.route
        request.state.apim_route_name = route.name

        verifiers: dict[str, OIDCVerifier] = request.app.state.oidc_verifiers
        auth = authenticate_request(request, cfg, verifiers, route)

        if route.product:
            allowed_products = [route.product]
        else:
            allowed_products = []

        if route.products:
            allowed_products = list(route.products)

        if allowed_products:
            require_sub = any(
                (cfg.products.get(p).require_subscription if cfg.products.get(p) else True) for p in allowed_products
            )
            if require_sub and subscription_bypassed(request, cfg):
                require_sub = False
            if require_sub:
                if auth.subscription is None:
                    request.state.apim_result_reason = "missing_subscription"
                    raise HTTPException(status_code=401, detail="Missing subscription key")
                if not set(allowed_products).intersection(set(auth.subscription_products)):
                    request.state.apim_result_reason = "subscription_not_authorized"
                    raise HTTPException(status_code=403, detail="Subscription not authorized for product")

        set_current_span_attributes(
            **{
                APIM_ROUTE_NAME_ATTR: route.name,
                "apim.route.path_prefix": route.path_prefix,
                "apim.subscription.present": auth.subscription is not None,
                "apim.allowed_products.count": len(allowed_products),
            }
        )

        policy_docs: list[Any] = []
        policy_cache: dict[str, Any] = request.app.state.policy_cache

        def _doc_for(xml: str) -> Any:
            cache_key = (xml, tuple(sorted(cfg.policy_fragments.items())))
            cached = policy_cache.get(cache_key)
            if cached is not None:
                return cached
            doc = parse_policies_xml(xml, policy_fragments=cfg.policy_fragments)
            policy_cache[cache_key] = doc
            return doc

        for xml in cfg.policies_xml_documents:
            policy_docs.append(_doc_for(xml))
        if cfg.policies_xml:
            policy_docs.append(_doc_for(cfg.policies_xml))
        for xml in route.policies_xml_documents:
            policy_docs.append(_doc_for(xml))
        if route.policies_xml:
            policy_docs.append(_doc_for(route.policies_xml))

        body = await request.body()
        if len(body) > cfg.max_request_body_bytes:
            request.state.apim_result_reason = "request_body_too_large"
            raise HTTPException(status_code=413, detail="Request body too large")
        headers = {k.lower(): v for k, v in build_upstream_headers(request, auth).items()}

        correlation_id = getattr(request.state, "correlation_id", None) or request.headers.get("x-correlation-id")
        headers.setdefault("x-correlation-id", correlation_id)

        incoming_host = request.headers.get("host", "")
        forwarded_host = request.headers.get("x-forwarded-host", "")
        forwarded_proto = request.headers.get("x-forwarded-proto", "")
        forwarded_for = request.headers.get("x-forwarded-for", "")
        client_ip = (
            forwarded_for.split(",", 1)[0].strip() if forwarded_for else (request.client.host if request.client else "")
        )
        request.state.apim_client_ip = client_ip
        subscription_record = _find_subscription_by_id(cfg, auth.subscription.id) if auth.subscription else None
        subscription_owner = subscription_record.created_by if subscription_record is not None else None
        subscription_groups = (
            sorted(
                group.id for group in cfg.groups.values() if subscription_owner and subscription_owner in group.users
            )
            if subscription_owner
            else []
        )

        upstream_path = resolved.upstream_path
        upstream_query = dict(request.query_params)
        policy_req = PolicyRequest(
            method=request.method,
            path=upstream_path,
            query=upstream_query,
            headers=headers,
            variables={
                "route": route.name,
                "api_id": route.api_id or "",
                "operation_id": route.operation_id or "",
                "subscription_id": auth.subscription.id if auth.subscription else "",
                "products": auth.subscription_products,
                "client_ip": client_ip,
                "correlation_id": correlation_id,
                "incoming_host": incoming_host,
                "forwarded_host": forwarded_host,
                "forwarded_proto": forwarded_proto,
                "forwarded_for": forwarded_for,
                "subscription_owner": subscription_owner or "",
                "subscription_groups": subscription_groups,
                "rate_limit_store": request.app.state.rate_limit_store,
                "quota_store": request.app.state.quota_store,
                "original_request_url": str(request.url),
                "_request_headers": dict(headers),
                "_request_query": dict(upstream_query),
            },
            body=body,
        )

        trace_requested = cfg.trace_enabled and request.headers.get("x-apim-trace", "").lower() == "true"
        request.state.apim_trace_requested = trace_requested
        trace_id = f"trace-{int(time.time() * 1000)}" if trace_requested else None
        trace_collector = PolicyTraceCollector() if trace_requested else None
        client: httpx.AsyncClient = request.app.state.http_client
        policy_runtime = PolicyRuntime(
            gateway_config=cfg,
            http_client=client,
            timeout_seconds=cfg.proxy_timeout_seconds,
            trace=trace_collector,
            response_cache=request.app.state.policy_response_cache,
            value_cache=request.app.state.policy_value_cache,
        )

        set_current_span_attributes(
            **{
                "apim.trace.requested": trace_requested,
                "apim.subscription.authorized": auth.subscription is not None,
            }
        )

        def _store_trace(payload: dict[str, Any]) -> None:
            if not trace_id:
                return
            trace_store: dict[str, Any] = request.app.state.trace_store
            trace_store[trace_id] = {
                "trace_id": trace_id,
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                **payload,
            }

        def _finalize_policy_response(
            *,
            status_code: int,
            headers: dict[str, str],
            body_bytes: bytes = b"",
            media_type: str | None = None,
        ) -> None:
            final_req = PolicyRequest(
                method=policy_req.method,
                path=policy_req.path,
                query=dict(policy_req.query),
                headers=dict(policy_req.headers),
                variables=policy_req.variables,
                body=policy_req.body,
                response_status_code=status_code,
                response_headers=headers,
                response_body=body_bytes,
                response_media_type=media_type,
            )
            finalize_deferred_actions(final_req, policy_runtime)

        trace_base = {
            "route": route.name,
            "correlation_id": correlation_id,
            "incoming_host": incoming_host,
            "forwarded_host": forwarded_host,
            "forwarded_proto": forwarded_proto,
            "forwarded_for": forwarded_for,
            "client_ip": client_ip,
            "upstream_url": None,
        }

        if policy_docs:
            early = await apply_inbound_async(policy_docs, policy_req, policy_runtime)
            if early is not None:
                request.state.apim_result_reason = "policy_inbound_short_circuit"
                request.state.apim_upstream_attempts = 0
                gateway_metrics.policy_short_circuits.add(
                    1,
                    {
                        APIM_ROUTE_NAME_ATTR: route.name,
                        "apim.policy.stage": "inbound",
                        "http.request.method": request.method,
                    },
                )
                set_current_span_attributes(
                    **{
                        APIM_RESULT_REASON_ATTR: "policy_inbound_short_circuit",
                        APIM_UPSTREAM_ATTEMPTS_ATTR: 0,
                    }
                )
                out_headers = dict(early.headers)
                _finalize_policy_response(
                    status_code=early.status_code,
                    headers=out_headers,
                    body_bytes=early.body,
                    media_type=early.media_type,
                )
                out_headers["x-apim-simulator"] = "apim-sim-full"
                out_headers["x-correlation-id"] = correlation_id
                if trace_id:
                    out_headers["x-apim-trace-id"] = trace_id
                    trace = _trace_payload(
                        trace_base=trace_base,
                        trace_collector=trace_collector,
                        cfg=cfg,
                        extra={
                            "upstream_url": None,
                            "attempts": 0,
                            "status": early.status_code,
                            "elapsed_ms": 0,
                            "cache": None,
                            "reason": "policy_inbound_short_circuit",
                        },
                    )
                    out_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode("utf-8")
                    _store_trace(trace)
                return Response(
                    content=early.body,
                    status_code=early.status_code,
                    headers=out_headers,
                    media_type=early.media_type,
                )

            backend_early = await apply_backend_async(policy_docs, policy_req, policy_runtime)
            if backend_early is not None:
                request.state.apim_result_reason = "policy_backend_short_circuit"
                request.state.apim_upstream_attempts = 0
                gateway_metrics.policy_short_circuits.add(
                    1,
                    {
                        APIM_ROUTE_NAME_ATTR: route.name,
                        "apim.policy.stage": "backend",
                        "http.request.method": request.method,
                    },
                )
                set_current_span_attributes(
                    **{
                        APIM_RESULT_REASON_ATTR: "policy_backend_short_circuit",
                        APIM_UPSTREAM_ATTEMPTS_ATTR: 0,
                    }
                )
                out_headers = dict(backend_early.headers)
                _finalize_policy_response(
                    status_code=backend_early.status_code,
                    headers=out_headers,
                    body_bytes=backend_early.body,
                    media_type=backend_early.media_type,
                )
                out_headers["x-apim-simulator"] = "apim-sim-full"
                out_headers["x-correlation-id"] = correlation_id
                if trace_id:
                    out_headers["x-apim-trace-id"] = trace_id
                    trace = _trace_payload(
                        trace_base=trace_base,
                        trace_collector=trace_collector,
                        cfg=cfg,
                        extra={
                            "upstream_url": None,
                            "attempts": 0,
                            "status": backend_early.status_code,
                            "elapsed_ms": 0,
                            "cache": None,
                            "reason": "policy_backend_short_circuit",
                        },
                    )
                    out_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode("utf-8")
                    _store_trace(trace)
                return Response(
                    content=backend_early.body,
                    status_code=backend_early.status_code,
                    headers=out_headers,
                    media_type=backend_early.media_type,
                )

        effective_claims = auth.claims
        jwt_claims = policy_req.variables.get("_last_jwt_claims")
        if isinstance(jwt_claims, dict):
            effective_claims = jwt_claims
            _apply_claim_headers(policy_req.headers, effective_claims)

        if route.authz is not None:
            scopes = _extract_scopes(effective_claims)
            roles = _extract_roles(effective_claims)
            if route.authz.required_scopes and not set(route.authz.required_scopes).issubset(scopes):
                request.state.apim_result_reason = "missing_required_scope"
                raise HTTPException(status_code=403, detail="Missing required scope")
            if route.authz.required_roles and not set(route.authz.required_roles).issubset(roles):
                request.state.apim_result_reason = "missing_required_role"
                raise HTTPException(status_code=403, detail="Missing required role")
            for key, expected in route.authz.required_claims.items():
                actual = effective_claims.get(key)
                if actual is None or str(actual) != expected:
                    request.state.apim_result_reason = "missing_required_claim"
                    raise HTTPException(status_code=403, detail="Missing required claim")

        upstream_base_url = route.upstream_base_url
        upstream_auth: tuple[str, str] | None = None
        selected_backend_url = str(policy_req.variables.get("selected_backend_url") or "")
        selected_backend_id = str(policy_req.variables.get("selected_backend_id") or "")
        backend_id = selected_backend_id or (route.backend or "" if not selected_backend_url else "")
        if selected_backend_url:
            upstream_base_url = selected_backend_url
        if backend_id:
            backend = cfg.backends.get(backend_id)
            if backend is not None:
                upstream_base_url = selected_backend_url or (
                    _render_backend_value(backend.url, policy_req, cfg) or backend.url
                )
                policy_req.headers.setdefault("x-apim-backend-id", backend_id)

                auth_type = (backend.auth_type or "none").lower()
                if auth_type == "basic":
                    username = _render_backend_value(backend.basic_username, policy_req, cfg)
                    password = _render_backend_value(backend.basic_password, policy_req, cfg)
                    if "authorization" not in policy_req.headers and username and password:
                        upstream_auth = (username, password)
                elif auth_type == "managed_identity":
                    policy_req.headers.setdefault("x-apim-managed-identity", "true")
                    if backend.managed_identity_resource:
                        policy_req.headers.setdefault(
                            "x-apim-managed-identity-resource",
                            _render_backend_value(backend.managed_identity_resource, policy_req, cfg),
                        )
                elif auth_type == "client_certificate":
                    policy_req.headers.setdefault("x-apim-client-certificate", "present")

                if (
                    backend.authorization_scheme
                    and backend.authorization_parameter
                    and "authorization" not in policy_req.headers
                ):
                    scheme = _render_backend_value(backend.authorization_scheme, policy_req, cfg) or ""
                    parameter = _render_backend_value(backend.authorization_parameter, policy_req, cfg) or ""
                    policy_req.headers["authorization"] = f"{scheme} {parameter}".strip()

                for header_name, header_value in backend.header_credentials.items():
                    rendered = _render_backend_value(header_value, policy_req, cfg)
                    if rendered is not None:
                        policy_req.headers[header_name.lower()] = rendered

                for query_name, query_value in backend.query_credentials.items():
                    rendered = _render_backend_value(query_value, policy_req, cfg)
                    if rendered is not None:
                        policy_req.query[query_name] = rendered

                if backend.client_certificate_thumbprints:
                    policy_req.headers.setdefault(
                        "x-apim-client-certificate-thumbprints",
                        ",".join(backend.client_certificate_thumbprints),
                    )

        request.state.apim_backend_id = backend_id or "direct"
        set_current_span_attributes(
            **{
                APIM_BACKEND_ID_ATTR: request.state.apim_backend_id,
                "apim.policy.documents": len(policy_docs),
            }
        )

        if trace_collector is not None and trace_collector.selected_backend is None:
            trace_collector.selected_backend = {
                "backend_id": backend_id or None,
                "base_url": upstream_base_url,
            }

        upstream_url = route.build_upstream_url(policy_req.path, upstream_base_url=upstream_base_url)
        policy_req.variables["upstream_url"] = upstream_url

        trace_base["upstream_url"] = upstream_url

        policy_response_cache_active = bool(policy_req.variables.get("_policy_response_cache_active"))
        cache_key = None
        if (
            cfg.cache_enabled
            and (request.method == "GET")
            and (not cfg.proxy_streaming)
            and not policy_response_cache_active
        ):
            authz = request.headers.get("authorization", "")
            sub_key = request.headers.get("ocp-apim-subscription-key", "")
            cache_key = _request_cache_key(
                method=request.method,
                upstream_url=upstream_url,
                query=policy_req.query,
                authorization=authz,
                subscription_key=sub_key,
            )
            cached = request.app.state.cache.get(cache_key)
            if cached is not None:
                cached_response = _cached_gateway_response(
                    cached=cached,
                    request=request,
                    route_name=route.name,
                    policy_req=policy_req,
                    policy_runtime=policy_runtime,
                    trace_base=trace_base,
                    trace_collector=trace_collector,
                    cfg=cfg,
                    gateway_metrics=gateway_metrics,
                    correlation_id=correlation_id,
                    trace_id=trace_id,
                )
                if cached_response is not None:
                    return cached_response
                request.app.state.cache.pop(cache_key, None)

        timeout = httpx.Timeout(cfg.proxy_timeout_seconds)
        max_attempts = max(1, cfg.proxy_max_attempts)
        last_exc: Exception | None = None
        upstream_response: httpx.Response | None = None
        start = time.perf_counter()
        attempts_used = 0

        for attempt in range(1, max_attempts + 1):
            attempts_used = attempt
            req = client.build_request(
                request.method,
                upstream_url,
                content=policy_req.body,
                headers=policy_req.headers,
                params=policy_req.query,
                timeout=timeout,
            )
            try:
                upstream_response = await client.send(req, stream=cfg.proxy_streaming, auth=upstream_auth)
            except httpx.RequestError as exc:
                last_exc = exc
                if attempt >= max_attempts:
                    break
                continue

            if upstream_response.status_code in cfg.proxy_retry_statuses and attempt < max_attempts:
                await upstream_response.aclose()
                upstream_response = None
                continue
            break

        elapsed_seconds = time.perf_counter() - start
        request.state.apim_upstream_attempts = attempts_used

        if upstream_response is None:
            request.state.apim_result_reason = "upstream_unavailable"
            request.state.apim_upstream_duration_seconds = elapsed_seconds
            set_current_span_attributes(
                **{
                    APIM_RESULT_REASON_ATTR: "upstream_unavailable",
                    APIM_UPSTREAM_ATTEMPTS_ATTR: attempts_used,
                }
            )
            if policy_docs:
                failure_req = PolicyRequest(
                    method=request.method,
                    path=policy_req.path,
                    query=dict(policy_req.query),
                    headers=dict(policy_req.headers),
                    variables={**policy_req.variables, "error": "upstream_unavailable"},
                )
                override = await apply_on_error_async(policy_docs, failure_req, policy_runtime)
                if override is not None:
                    request.state.apim_result_reason = "policy_on_error_override"
                    out_headers = dict(override.headers)
                    _finalize_policy_response(
                        status_code=override.status_code,
                        headers=out_headers,
                        body_bytes=override.body,
                        media_type=override.media_type,
                    )
                    out_headers["x-apim-simulator"] = "apim-sim-full"
                    out_headers["x-correlation-id"] = correlation_id
                    if trace_id:
                        out_headers["x-apim-trace-id"] = trace_id
                        trace = _trace_payload(
                            trace_base=trace_base,
                            trace_collector=trace_collector,
                            cfg=cfg,
                            extra={
                                "attempts": attempts_used,
                                "status": override.status_code,
                                "elapsed_ms": int(elapsed_seconds * 1000),
                                "cache": None,
                                "reason": "policy_on_error_override",
                            },
                        )
                        out_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode(
                            "utf-8"
                        )
                        _store_trace(trace)
                    return Response(
                        content=override.body,
                        status_code=override.status_code,
                        headers=out_headers,
                        media_type=override.media_type,
                    )
            logger.exception("Unable to reach upstream", exc_info=last_exc)
            raise HTTPException(status_code=502, detail="Backend API unavailable")

        response_headers = filter_response_headers(dict(upstream_response.headers))
        media_type = upstream_response.headers.get("content-type")
        response_headers["x-correlation-id"] = correlation_id
        request.state.apim_upstream_duration_seconds = elapsed_seconds
        upstream_status_code = int(upstream_response.status_code)
        if not (100 <= upstream_status_code <= 599):
            raise HTTPException(status_code=502, detail="Backend API returned invalid status code")
        requires_buffering = cache_key is not None or policy_response_cache_active or not cfg.proxy_streaming
        content = b""
        if requires_buffering:
            content = await upstream_response.aread()
            await upstream_response.aclose()

        if policy_docs:
            outbound_req = PolicyRequest(
                method=request.method,
                path=policy_req.path,
                query=dict(policy_req.query),
                headers=response_headers,
                variables=policy_req.variables,
                body=policy_req.body,
                response_status_code=upstream_status_code,
                response_headers=response_headers,
                response_body=content,
                response_media_type=media_type,
            )
            await apply_outbound_async(policy_docs, outbound_req, policy_runtime)
            response_headers = outbound_req.headers
            content = outbound_req.response_body
            media_type = outbound_req.response_media_type or media_type

        _finalize_policy_response(
            status_code=upstream_status_code,
            headers=response_headers,
            body_bytes=content,
            media_type=media_type,
        )

        if cache_key is not None:
            request.state.apim_cache_result = "miss"
            request.state.apim_result_reason = "upstream_response"
            gateway_metrics.cache_events.add(
                1,
                {
                    APIM_ROUTE_NAME_ATTR: route.name,
                    APIM_CACHE_RESULT_ATTR: "miss",
                    "http.request.method": request.method,
                },
            )
            set_current_span_attributes(
                **{
                    APIM_CACHE_RESULT_ATTR: "miss",
                    APIM_RESULT_REASON_ATTR: "upstream_response",
                    APIM_UPSTREAM_ATTEMPTS_ATTR: attempts_used,
                }
            )
            response_headers["x-apim-cache"] = "miss"
            if len(request.app.state.cache) >= cfg.cache_max_entries:
                request.app.state.cache.clear()
            request.app.state.cache[cache_key] = (
                time.time() + cfg.cache_ttl_seconds,
                upstream_status_code,
                dict(response_headers),
                media_type,
                content,
            )
            if trace_requested:
                elapsed_ms = int(elapsed_seconds * 1000)
                trace = _trace_payload(
                    trace_base=trace_base,
                    trace_collector=trace_collector,
                    cfg=cfg,
                    extra={
                        "attempts": attempts_used,
                        "status": upstream_status_code,
                        "elapsed_ms": elapsed_ms,
                        "cache": "miss",
                    },
                )
                response_headers["x-apim-trace-id"] = trace_id
                response_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode("utf-8")
                _store_trace(trace)
            return Response(
                content=content,
                status_code=upstream_status_code,
                headers=response_headers,
                media_type=media_type,
            )

        if cfg.proxy_streaming and not requires_buffering:
            request.state.apim_result_reason = "upstream_stream"
            set_current_span_attributes(
                **{
                    APIM_RESULT_REASON_ATTR: "upstream_stream",
                    APIM_UPSTREAM_ATTEMPTS_ATTR: attempts_used,
                }
            )
            if trace_requested:
                elapsed_ms = int(elapsed_seconds * 1000)
                trace = _trace_payload(
                    trace_base=trace_base,
                    trace_collector=trace_collector,
                    cfg=cfg,
                    extra={
                        "attempts": attempts_used,
                        "status": upstream_status_code,
                        "elapsed_ms": elapsed_ms,
                        "cache": None,
                    },
                )
                response_headers["x-apim-trace-id"] = trace_id
                response_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode("utf-8")
                _store_trace(trace)
            return StreamingResponse(
                upstream_response.aiter_bytes(),
                status_code=upstream_status_code,
                headers=response_headers,
                media_type=media_type,
                background=BackgroundTask(upstream_response.aclose),
            )

        request.state.apim_result_reason = "upstream_response"
        set_current_span_attributes(
            **{
                APIM_RESULT_REASON_ATTR: "upstream_response",
                APIM_UPSTREAM_ATTEMPTS_ATTR: attempts_used,
            }
        )
        if trace_requested:
            elapsed_ms = int(elapsed_seconds * 1000)
            trace = _trace_payload(
                trace_base=trace_base,
                trace_collector=trace_collector,
                cfg=cfg,
                extra={
                    "attempts": attempts_used,
                    "status": upstream_status_code,
                    "elapsed_ms": elapsed_ms,
                    "cache": None,
                },
            )
            response_headers["x-apim-trace-id"] = trace_id
            response_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode("utf-8")
            _store_trace(trace)
        return Response(
            content=content,
            status_code=upstream_status_code,
            headers=response_headers,
            media_type=media_type,
        )

    instrument_fastapi_app(app, telemetry)
    return app


app = create_app()
