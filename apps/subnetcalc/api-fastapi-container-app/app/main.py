"""FastAPI application for subnet calculator - Container/App Service version.

This version runs directly on Uvicorn (ASGI server) without Azure Functions wrapper.
Key differences from Azure Functions version:
- No AsgiMiddleware (FastAPI runs directly on Uvicorn)
- Standard routes (/subnets/ipv4) instead of function routes (/api/calculate_ipv4)
- Direct HTTP server instead of Azure Functions host

Environment Variables:
    AUTH_METHOD: Authentication method (none, api_key, jwt, azure_swa, apim, azure_ad)

    CORS Configuration:
        CORS_ORIGINS: Comma-separated list of allowed CORS origins
                     If not set or empty, no origins allowed (same-origin only)
                     Example: http://localhost:3000,http://localhost:5173

    SWA Host Validation (only applies when AUTH_METHOD=none):
        ALLOWED_SWA_HOSTS: Comma-separated list of allowed SWA hostnames
                          Validates X-Forwarded-Host header for security
                          Example: app.azurestaticapps.net,custom-domain.com

    API Key Authentication (AUTH_METHOD=api_key):
        API_KEYS: Comma-separated list of valid API keys

    JWT Authentication (AUTH_METHOD=jwt):
        JWT_SECRET_KEY: Secret key for signing JWTs (min 32 characters)
        JWT_ALGORITHM: Signing algorithm (default: HS256)
        JWT_ACCESS_TOKEN_EXPIRE_MINUTES: Token expiration (default: 30)
        JWT_TEST_USERS: JSON object with test users (development only)
"""

import logging
import os

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .auth import validate_api_key
from .config import (
    AuthMethod,
    get_allowed_swa_hosts,
    get_api_keys,
    get_auth_method,
    get_cors_origins,
)
from .routers import auth, health, network, subnets

# Configure logging
logger = logging.getLogger(__name__)
_OTEL_CONFIGURED = False


def configure_opentelemetry(app: FastAPI) -> None:
    """Enable OTLP trace export when OTEL_EXPORTER_OTLP_ENDPOINT is set."""
    global _OTEL_CONFIGURED
    if _OTEL_CONFIGURED:
        return

    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    if not endpoint:
        return

    try:
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
    except Exception as exc:  # pragma: no cover
        logger.warning("OpenTelemetry init failed; tracing disabled: %s", exc)
        return

    service_name = os.getenv("OTEL_SERVICE_NAME", "subnetcalc-api")
    namespace = os.getenv("POD_NAMESPACE", "local")
    resource_attrs = {
        "service.name": service_name,
        "deployment.environment": namespace,
    }
    if os.getenv("POD_NAMESPACE"):
        resource_attrs["k8s.namespace.name"] = os.getenv("POD_NAMESPACE", "")

    traces_endpoint = endpoint.rstrip("/")
    if not traces_endpoint.endswith("/v1/traces"):
        traces_endpoint = f"{traces_endpoint}/v1/traces"

    try:
        tracer_provider = TracerProvider(resource=Resource.create(resource_attrs))
        tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=traces_endpoint)))
        trace.set_tracer_provider(tracer_provider)

        FastAPIInstrumentor().instrument_app(app)
        HTTPXClientInstrumentor().instrument()
    except Exception as exc:  # pragma: no cover
        logger.warning("OpenTelemetry exporter init failed; tracing disabled: %s", exc)
        return

    _OTEL_CONFIGURED = True
    logger.info("OpenTelemetry enabled (service.name=%s endpoint=%s)", service_name, traces_endpoint)

# Create FastAPI app
app = FastAPI(
    title="Subnet Calculator API",
    description="IPv4 and IPv6 subnet calculator with multiple authentication methods",
    version="1.0.0",
    docs_url="/api/v1/docs",  # Swagger UI
    redoc_url="/api/v1/redoc",  # ReDoc
    openapi_url="/api/v1/openapi.json",  # OpenAPI spec (for APIM import)
)

# Enable tracing when OTEL_EXPORTER_OTLP_ENDPOINT is configured.
configure_opentelemetry(app)

# Configure CORS origins from environment
# CORS_ORIGINS: Comma-separated list of allowed origins
# If not set or empty, only allows same-origin (no wildcard)
cors_origins = get_cors_origins()
if not cors_origins:
    # Default to localhost origins for development
    cors_origins = [
        "http://localhost:3000",  # TypeScript Vite frontend
        "http://localhost:8001",  # Static HTML frontend
        "http://localhost:5173",  # Vite dev server
    ]
    logger.warning("CORS: Using default localhost origins for development")
else:
    logger.info(f"CORS: Allowed origins: {', '.join(cors_origins)}")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(health.router)
app.include_router(auth.router)
app.include_router(subnets.router)
app.include_router(subnets.router_ipv6)
app.include_router(network.router)


# Middleware for X-Forwarded-Host validation
@app.middleware("http")
async def swa_host_validation_middleware(request: Request, call_next):
    """
    Validate X-Forwarded-Host header when AUTH_METHOD=none.

    This middleware protects unauthenticated APIs deployed behind Azure Static Web Apps
    by ensuring requests come from the expected SWA hostname.

    Configuration:
        ALLOWED_SWA_HOSTS: Comma-separated list of allowed SWA hostnames
                          Example: app.azurestaticapps.net,custom-domain.com
                          If not set, validation is skipped

    Only applies when AUTH_METHOD=none (Stack 06 pattern).
    """
    auth_method = get_auth_method()

    # Skip validation for health, docs, and auth endpoints
    if request.url.path in [
        "/api/v1/health",
        "/api/v1/health/ready",
        "/api/v1/health/live",
        "/api/v1/docs",
        "/api/v1/redoc",
        "/api/v1/openapi.json",
        "/api/v1/auth/login",
        "/",
    ]:
        response = await call_next(request)
        return response

    # Only validate when AUTH_METHOD=none and ALLOWED_SWA_HOSTS is configured
    if auth_method == AuthMethod.NONE:
        allowed_hosts = get_allowed_swa_hosts()

        if allowed_hosts:
            # Extract X-Forwarded-Host header (set by Azure Static Web Apps)
            forwarded_host = request.headers.get("X-Forwarded-Host")

            if not forwarded_host:
                logger.warning(
                    "SWA Host Validation: Missing X-Forwarded-Host header",
                    extra={
                        "path": request.url.path,
                        "client_host": request.client.host if request.client else "unknown",
                    },
                )
                return JSONResponse(
                    status_code=403,
                    content={"detail": "Missing X-Forwarded-Host header"},
                )

            # Check if forwarded host matches any allowed host
            if forwarded_host not in allowed_hosts:
                logger.warning(
                    "SWA Host Validation: Invalid X-Forwarded-Host",
                    extra={
                        "forwarded_host": forwarded_host,
                        "allowed_hosts": allowed_hosts,
                        "path": request.url.path,
                    },
                )
                return JSONResponse(
                    status_code=403,
                    content={"detail": "Invalid X-Forwarded-Host header"},
                )

            logger.debug(
                "SWA Host Validation: Passed",
                extra={"forwarded_host": forwarded_host, "path": request.url.path},
            )

    # Pass through to next middleware
    response = await call_next(request)
    return response


# Middleware for authentication
@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    """Handle authentication based on AUTH_METHOD."""
    auth_method = get_auth_method()

    # Skip auth for health, docs, and auth endpoints
    if request.url.path in [
        "/api/v1/health",
        "/api/v1/health/ready",
        "/api/v1/health/live",
        "/api/v1/docs",
        "/api/v1/redoc",
        "/api/v1/openapi.json",
        "/api/v1/auth/login",
        "/",
    ]:
        response = await call_next(request)
        return response

    # API key authentication via middleware
    if auth_method == AuthMethod.API_KEY:
        api_key = request.headers.get("X-API-Key")
        valid_keys = get_api_keys()
        if not validate_api_key(api_key, valid_keys):
            return JSONResponse(status_code=401, content={"detail": "Invalid or missing API key"})

    # JWT, Azure SWA, APIM - handled by dependencies in route handlers
    # Pass through to let get_current_user dependency handle it
    if auth_method in (AuthMethod.JWT, AuthMethod.AZURE_SWA, AuthMethod.APIM):
        response = await call_next(request)
        return response

    # No authentication required (AUTH_METHOD=none)
    response = await call_next(request)
    return response


# Root endpoint
@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "name": "Subnet Calculator API",
        "version": "1.0.0",
        "docs": "/api/v1/docs",
        "openapi": "/api/v1/openapi.json",
        "health": "/api/v1/health",
    }
