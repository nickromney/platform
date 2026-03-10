from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from starlette.background import BackgroundTask
from starlette.responses import StreamingResponse

from app.config import GatewayConfig, Subscription, SubscriptionState, load_config
from app.policy import PolicyRequest, apply_inbound, apply_on_error, apply_outbound, parse_policies_xml
from app.proxy import build_upstream_headers, build_user_payload, filter_response_headers, resolve_route
from app.security import OIDCVerifier, authenticate_request, subscription_bypassed, validate_client_certificate
from app.terraform_import import config_from_tofu_show_json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("apim-sim-full")


def create_app(*, config: GatewayConfig | None = None, http_client: httpx.AsyncClient | None = None) -> FastAPI:
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

    oidc_verifiers = _build_oidc_verifiers(gateway_config)

    def _reload_config(app: FastAPI) -> GatewayConfig:
        """Reload configuration from file and update app state."""
        new_config = load_config()
        new_config.routes = new_config.materialize_routes()
        new_verifiers = _build_oidc_verifiers(new_config)
        app.state.gateway_config = new_config
        app.state.oidc_verifiers = new_verifiers
        app.state.policy_cache = {}  # Clear policy cache on reload
        logger.info(
            "config reloaded | routes=%d | origins=%s | anonymous=%s",
            len(new_config.routes),
            new_config.allowed_origins,
            new_config.allow_anonymous,
        )
        return new_config

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
                    _reload_config(app)
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
        app.state.gateway_config = gateway_config
        app.state.oidc_verifiers = oidc_verifiers
        app.state.cache = {}
        app.state.policy_cache = {}
        app.state.rate_limit_store = {}
        app.state.quota_store = {}
        app.state.trace_store = {}
        app.state.config_reload_fn = lambda: _reload_config(app)
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

    app = FastAPI(title="Subnet Calculator APIM Simulator (Full)", version="0.1.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=gateway_config.allowed_origins or ["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

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

    def _find_subscription_by_id(cfg: GatewayConfig, subscription_id: str) -> Subscription | None:
        for sub in cfg.subscription.subscriptions.values():
            if sub.id == subscription_id:
                return sub
        return None

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

    @app.get("/apim/management/status")
    async def management_status(request: Request) -> dict:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return {
            "routes": len(cfg.routes),
            "products": len(cfg.products),
            "subscriptions": len(cfg.subscription.subscriptions),
            "api_version_sets": len(cfg.api_version_sets),
        }

    @app.get("/apim/management/subscriptions")
    async def list_subscriptions(request: Request) -> list[dict]:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        return [sub.model_dump() for sub in cfg.subscription.subscriptions.values()]

    @app.post("/apim/management/subscriptions")
    async def create_subscription(request: Request, body: SubscriptionUpsert) -> dict:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        if _find_subscription_by_id(cfg, body.id) is not None:
            raise HTTPException(status_code=409, detail="Subscription already exists")

        primary = body.primary_key or f"sub-{body.id}-primary"
        secondary = body.secondary_key or f"sub-{body.id}-secondary"
        sub = Subscription(
            id=body.id,
            name=body.name,
            keys={"primary": primary, "secondary": secondary},
            state=body.state,
            products=body.products,
            created_by="management",
        )
        cfg.subscription.subscriptions[body.id] = sub
        return sub.model_dump()

    @app.patch("/apim/management/subscriptions/{subscription_id}")
    async def update_subscription(request: Request, subscription_id: str, body: SubscriptionUpdate) -> dict:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        sub = _find_subscription_by_id(cfg, subscription_id)
        if sub is None:
            raise HTTPException(status_code=404, detail="Subscription not found")

        if body.name is not None:
            sub.name = body.name
        if body.state is not None:
            sub.state = body.state
        if body.products is not None:
            sub.products = body.products
        return sub.model_dump()

    @app.post("/apim/management/subscriptions/{subscription_id}/rotate")
    async def management_rotate_subscription_key(
        subscription_id: str, request: Request, key: str = "secondary"
    ) -> dict:
        _require_tenant_access(request)
        cfg: GatewayConfig = request.app.state.gateway_config
        sub = _find_subscription_by_id(cfg, subscription_id)
        if sub is None:
            raise HTTPException(status_code=404, detail="Subscription not found")
        if key not in {"primary", "secondary"}:
            raise HTTPException(status_code=400, detail="Invalid key")

        new_key = f"rotated-{sub.id}-{key}"
        if key == "primary":
            sub.keys.primary = new_key
        else:
            sub.keys.secondary = new_key
        return {"subscription_id": sub.id, "subscription_name": sub.name, "rotated": key, "new_key": new_key}

    @app.post("/apim/management/import/tofu-show")
    async def import_tofu_show_json(request: Request, tf: dict[str, Any]) -> dict:
        _require_tenant_access(request)

        current: GatewayConfig = request.app.state.gateway_config
        imported = config_from_tofu_show_json(tf)

        # Preserve local runtime settings.
        imported.allowed_origins = current.allowed_origins
        imported.allow_anonymous = current.allow_anonymous
        imported.oidc = current.oidc
        imported.oidc_providers = current.oidc_providers
        imported.admin_token = current.admin_token
        imported.tenant_access = current.tenant_access
        imported.subscription.header_names = current.subscription.header_names
        imported.subscription.query_param_names = current.subscription.query_param_names

        imported.routes = imported.materialize_routes()
        request.app.state.gateway_config = imported
        request.app.state.oidc_verifiers = _build_oidc_verifiers(imported)
        request.app.state.cache = {}
        request.app.state.policy_cache = {}
        request.app.state.rate_limit_store = {}
        request.app.state.quota_store = {}
        request.app.state.trace_store = {}

        return {
            "routes": len(imported.routes),
            "products": len(imported.products),
            "subscriptions": len(imported.subscription.subscriptions),
            "apis": len(imported.apis),
        }

    @app.api_route("/{full_path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
    async def gateway_proxy(full_path: str, request: Request) -> Response:
        if request.method == "OPTIONS":
            return Response(status_code=204)

        cfg: GatewayConfig = request.app.state.gateway_config

        # mTLS validation (before route resolution)
        validate_client_certificate(request, cfg)

        resolved = resolve_route(cfg, request)
        if resolved is None:
            raise HTTPException(status_code=404, detail="No route")
        route = resolved.route

        verifiers: dict[str, OIDCVerifier] = request.app.state.oidc_verifiers
        auth = authenticate_request(request, cfg, verifiers)

        if route.authz is not None:
            scopes = _extract_scopes(auth.claims)
            roles = _extract_roles(auth.claims)
            if route.authz.required_scopes and not set(route.authz.required_scopes).issubset(scopes):
                raise HTTPException(status_code=403, detail="Missing required scope")
            if route.authz.required_roles and not set(route.authz.required_roles).issubset(roles):
                raise HTTPException(status_code=403, detail="Missing required role")
            for key, expected in route.authz.required_claims.items():
                actual = auth.claims.get(key)
                if actual is None or str(actual) != expected:
                    raise HTTPException(status_code=403, detail="Missing required claim")

        if route.product:
            # Back-compat: route.product.
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
                    raise HTTPException(status_code=401, detail="Missing subscription key")
                if not set(allowed_products).intersection(set(auth.subscription_products)):
                    raise HTTPException(status_code=403, detail="Subscription not authorized for product")

        policy_docs: list[Any] = []
        policy_cache: dict[str, Any] = request.app.state.policy_cache

        def _doc_for(xml: str) -> Any:
            cached = policy_cache.get(xml)
            if cached is not None:
                return cached
            doc = parse_policies_xml(xml)
            policy_cache[xml] = doc
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
            raise HTTPException(status_code=413, detail="Request body too large")
        headers = {k.lower(): v for k, v in build_upstream_headers(request, auth).items()}

        correlation_id = request.headers.get("x-correlation-id") or f"corr-{uuid.uuid4()}"
        headers.setdefault("x-correlation-id", correlation_id)

        xff = request.headers.get("x-forwarded-for", "")
        client_ip = xff.split(",", 1)[0].strip() if xff else (request.client.host if request.client else "")

        upstream_path = resolved.upstream_path
        upstream_query = dict(request.query_params)
        policy_req = PolicyRequest(
            method=request.method,
            path=upstream_path,
            query=upstream_query,
            headers=headers,
            variables={
                "route": route.name,
                "subscription_id": auth.subscription.id if auth.subscription else "",
                "products": auth.subscription_products,
                "client_ip": client_ip,
                "correlation_id": correlation_id,
                "rate_limit_store": request.app.state.rate_limit_store,
                "quota_store": request.app.state.quota_store,
            },
        )

        trace_requested = cfg.trace_enabled and request.headers.get("x-apim-trace", "").lower() == "true"
        trace_id = f"trace-{int(time.time() * 1000)}" if trace_requested else None

        def _store_trace(payload: dict[str, Any]) -> None:
            if not trace_id:
                return
            trace_store: dict[str, Any] = request.app.state.trace_store
            trace_store[trace_id] = payload

        if policy_docs:
            early = apply_inbound(policy_docs, policy_req)
            if early is not None:
                out_headers = dict(early.headers)
                out_headers["x-apim-simulator"] = "apim-sim-full"
                out_headers["x-correlation-id"] = correlation_id
                if trace_id:
                    out_headers["x-apim-trace-id"] = trace_id
                    trace = {
                        "route": route.name,
                        "correlation_id": correlation_id,
                        "upstream_url": None,
                        "attempts": 0,
                        "status": early.status_code,
                        "elapsed_ms": 0,
                        "cache": None,
                        "reason": "policy_inbound_short_circuit",
                    }
                    out_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode("utf-8")
                    _store_trace(trace)
                return Response(
                    content=early.body,
                    status_code=early.status_code,
                    headers=out_headers,
                    media_type=early.media_type,
                )

        upstream_base_url = route.upstream_base_url
        upstream_auth: tuple[str, str] | None = None
        if route.backend:
            backend = cfg.backends.get(route.backend)
            if backend is not None:
                upstream_base_url = backend.url
                policy_req.headers.setdefault("x-apim-backend-id", route.backend)

                auth_type = (backend.auth_type or "none").lower()
                if auth_type == "basic":
                    if "authorization" not in policy_req.headers and backend.basic_username and backend.basic_password:
                        upstream_auth = (backend.basic_username, backend.basic_password)
                elif auth_type == "managed_identity":
                    policy_req.headers.setdefault("x-apim-managed-identity", "true")
                    if backend.managed_identity_resource:
                        policy_req.headers.setdefault(
                            "x-apim-managed-identity-resource", backend.managed_identity_resource
                        )
                elif auth_type == "client_certificate":
                    policy_req.headers.setdefault("x-apim-client-certificate", "present")

        upstream_url = route.build_upstream_url(policy_req.path, upstream_base_url=upstream_base_url)
        client: httpx.AsyncClient = request.app.state.http_client

        cache_key = None
        if cfg.cache_enabled and (request.method == "GET") and (not cfg.proxy_streaming):
            authz = request.headers.get("authorization", "")
            sub_key = request.headers.get("ocp-apim-subscription-key", "")
            material = f"{request.method}|{upstream_url}|{request.url.query}|{authz}|{sub_key}"
            cache_key = str(hash(material))
            cached = request.app.state.cache.get(cache_key)
            if cached is not None:
                expires_at, cached_status, cached_headers, cached_media_type, cached_body = cached
                if time.time() < expires_at:
                    out_headers = dict(cached_headers)
                    out_headers["x-apim-cache"] = "hit"
                    out_headers["x-correlation-id"] = correlation_id
                    if trace_id:
                        out_headers["x-apim-trace-id"] = trace_id
                        trace = {
                            "route": route.name,
                            "correlation_id": correlation_id,
                            "upstream_url": upstream_url,
                            "attempts": 0,
                            "status": cached_status,
                            "elapsed_ms": 0,
                            "cache": "hit",
                        }
                        out_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode(
                            "utf-8"
                        )
                        _store_trace(trace)
                    return Response(
                        content=cached_body,
                        status_code=cached_status,
                        headers=out_headers,
                        media_type=cached_media_type,
                    )
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
                content=body,
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

        if upstream_response is None:
            if policy_docs:
                failure_req = PolicyRequest(
                    method=request.method,
                    path=policy_req.path,
                    query=policy_req.query,
                    headers=dict(policy_req.headers),
                    variables={"error": "upstream_unavailable"},
                )
                override = apply_on_error(policy_docs, failure_req)
                if override is not None:
                    out_headers = dict(override.headers)
                    out_headers["x-apim-simulator"] = "apim-sim-full"
                    out_headers["x-correlation-id"] = correlation_id
                    if trace_id:
                        out_headers["x-apim-trace-id"] = trace_id
                        trace = {
                            "route": route.name,
                            "correlation_id": correlation_id,
                            "upstream_url": upstream_url,
                            "attempts": attempts_used,
                            "status": override.status_code,
                            "elapsed_ms": int((time.perf_counter() - start) * 1000),
                            "cache": None,
                            "reason": "policy_on_error_override",
                        }
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

        if policy_docs:
            apply_outbound(policy_docs, headers=response_headers)

        if cache_key is not None:
            content = await upstream_response.aread()
            await upstream_response.aclose()
            response_headers["x-apim-cache"] = "miss"
            if len(request.app.state.cache) >= cfg.cache_max_entries:
                request.app.state.cache.clear()
            request.app.state.cache[cache_key] = (
                time.time() + cfg.cache_ttl_seconds,
                upstream_response.status_code,
                dict(response_headers),
                media_type,
                content,
            )
            if trace_requested:
                elapsed_ms = int((time.perf_counter() - start) * 1000)
                trace = {
                    "route": route.name,
                    "correlation_id": correlation_id,
                    "upstream_url": upstream_url,
                    "attempts": attempts_used,
                    "status": upstream_response.status_code,
                    "elapsed_ms": elapsed_ms,
                    "cache": "miss",
                }
                response_headers["x-apim-trace-id"] = trace_id
                response_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode("utf-8")
                _store_trace(trace)
            return Response(
                content=content,
                status_code=upstream_response.status_code,
                headers=response_headers,
                media_type=media_type,
            )

        if cfg.proxy_streaming:
            if trace_requested:
                elapsed_ms = int((time.perf_counter() - start) * 1000)
                trace = {
                    "route": route.name,
                    "correlation_id": correlation_id,
                    "upstream_url": upstream_url,
                    "attempts": attempts_used,
                    "status": upstream_response.status_code,
                    "elapsed_ms": elapsed_ms,
                    "cache": None,
                }
                response_headers["x-apim-trace-id"] = trace_id
                response_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode("utf-8")
                _store_trace(trace)
            return StreamingResponse(
                upstream_response.aiter_bytes(),
                status_code=upstream_response.status_code,
                headers=response_headers,
                media_type=media_type,
                background=BackgroundTask(upstream_response.aclose),
            )

        content = await upstream_response.aread()
        await upstream_response.aclose()
        if trace_requested:
            elapsed_ms = int((time.perf_counter() - start) * 1000)
            trace = {
                "route": route.name,
                "correlation_id": correlation_id,
                "upstream_url": upstream_url,
                "attempts": attempts_used,
                "status": upstream_response.status_code,
                "elapsed_ms": elapsed_ms,
                "cache": None,
            }
            response_headers["x-apim-trace-id"] = trace_id
            response_headers["x-apim-trace"] = base64.b64encode(json.dumps(trace).encode("utf-8")).decode("utf-8")
            _store_trace(trace)
        return Response(
            content=content,
            status_code=upstream_response.status_code,
            headers=response_headers,
            media_type=media_type,
        )

    return app


app = create_app()
