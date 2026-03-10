"""Health check endpoints.

These endpoints are used by container orchestrators (Kubernetes, Container Apps)
to determine application health, readiness, and liveness.

- /health: General health check (no auth required)
- /health/ready: Readiness probe (can accept traffic?)
- /health/live: Liveness probe (is the app running?)
"""

from fastapi import APIRouter

from ..cloudflare_ips import is_using_live_cloudflare_ranges

router = APIRouter(prefix="/api/v1", tags=["health"])


@router.get("/health")
async def health_check():
    """Health check endpoint (no authentication required).

    Returns:
        Simple status indicating the application is healthy
    """
    return {
        "status": "healthy",
        "service": "Subnet Calculator API (Container App)",
        "version": "1.0.0",
        "using_live_cloudflare_ranges": is_using_live_cloudflare_ranges(),
    }


@router.get("/health/ready")
async def readiness_check():
    """Readiness check for Kubernetes/Container Apps.

    This should verify that the application can accept traffic.
    Add checks for:
    - Database connections
    - External service dependencies
    - Cache availability
    - etc.

    Returns:
        Status indicating application is ready to serve traffic
    """
    # TODO: Add dependency checks here (database, cache, etc.)
    return {"status": "ready"}


@router.get("/health/live")
async def liveness_check():
    """Liveness check for Kubernetes/Container Apps.

    This should verify that the application is still running.
    If this fails, the orchestrator will restart the container.

    Returns:
        Status indicating application is alive
    """
    return {"status": "alive"}
