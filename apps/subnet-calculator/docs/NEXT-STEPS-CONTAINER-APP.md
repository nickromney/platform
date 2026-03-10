# Next Steps: FastAPI Container App Implementation

## Overview

This document outlines the steps to create a non-Function-App version of our subnet calculator API that can run on:

- **Azure Container Apps** (recommended for microservices/containers)
- **Azure App Service** (traditional PaaS web apps)

Both can integrate with Azure API Management (APIM) using OpenAPI specifications.

## Key Differences from Azure Functions

### Current State (Azure Functions)

- Uses `azure-functions` Python library
- **Must use** `AsgiMiddleware` to bridge FastAPI → Azure Functions host
- Function-specific route pattern: `/api/{function_name}`
- Deployed as Function App with `func` CLI
- HTTP server: Azure Functions host (not Uvicorn)

**Why AsgiMiddleware?** Azure Functions requires it to translate between the ASGI protocol (FastAPI) and Azure Functions' HTTP trigger interface.

### Target State (Container App / App Service)

- Pure FastAPI application (no Azure Functions wrapper needed)
- **Uvicorn** as the ASGI server (FastAPI's recommended server)
- Direct route patterns: `/subnets/ipv4`, `/health`, etc.
- Deployed as container image or source code
- HTTP server: Uvicorn directly serving FastAPI

**Why Uvicorn?** It's the de facto standard ASGI server for FastAPI - fast, production-ready, and recommended by FastAPI documentation.

## Implementation Plan

### Phase 1: Create Standalone FastAPI Application

#### Step 1.1: Create New Directory Structure

```bash
mkdir -p subnet-calculator/api-fastapi-container-app
cd subnet-calculator/api-fastapi-container-app
```

**Files to create:**

```text
api-fastapi-container-app/
├── app/
│ ├── __init__.py
│ ├── main.py # FastAPI app entry point (no Azure Functions)
│ ├── config.py # Environment config (copy from api-fastapi-azure-function)
│ ├── auth.py # Authentication utilities (copy)
│ ├── routers/
│ │ ├── __init__.py
│ │ ├── health.py # Health check endpoints
│ │ └── subnets.py # Subnet calculation endpoints
│ └── models/
│ ├── __init__.py
│ └── subnet.py # Pydantic models
├── tests/
│ ├── __init__.py
│ ├── test_auth.py
│ ├── test_subnets.py
│ └── test_health.py
├── Dockerfile # Multi-stage build for production
├── docker-compose.yml # Local development
├── pyproject.toml # uv dependencies
├── .dockerignore
└── README.md
```

#### Step 1.2: Create Pure FastAPI Application

**app/main.py** (no Azure Functions wrapper):

```python
"""FastAPI application for subnet calculator - Container/App Service version."""

from fastapi import FastAPI, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from .config import get_settings, AuthMethod
from .auth import verify_api_key, get_current_user
from .routers import health, subnets
import time

# Create FastAPI app
app = FastAPI(
 title="Subnet Calculator API",
 description="IPv4 and IPv6 subnet calculator",
 version="1.0.0",
 docs_url="/docs", # Swagger UI
 redoc_url="/redoc", # ReDoc
 openapi_url="/openapi.json" # OpenAPI spec (for APIM import)
)

# Include routers
app.include_router(health.router)
app.include_router(subnets.router)

# Middleware for authentication and logging
@app.middleware("http")
async def auth_middleware(request: Request, call_next):
 """Handle authentication based on AUTH_METHOD."""
 settings = get_settings()

 # Skip auth for health and docs endpoints
 if request.url.path in ["/health", "/docs", "/redoc", "/openapi.json"]:
 return await call_next(request)

 # API key authentication via middleware
 if settings.auth_method == AuthMethod.API_KEY:
 api_key = request.headers.get("X-API-Key")
 if not verify_api_key(api_key):
 return JSONResponse(
 status_code=401,
 content={"detail": "Invalid or missing API key"}
 )

 # JWT, Azure SWA, APIM - handled by dependencies
 # Pass through to let get_current_user dependency handle it

 response = await call_next(request)
 return response

# Root endpoint
@app.get("/")
async def root():
 """Root endpoint with API information."""
 return {
 "name": "Subnet Calculator API",
 "version": "1.0.0",
 "docs": "/docs",
 "openapi": "/openapi.json"
 }
```

**app/routers/health.py**:

```python
"""Health check endpoints."""

from fastapi import APIRouter

router = APIRouter(prefix="", tags=["health"])

@router.get("/health")
async def health_check():
 """Health check endpoint (no authentication required)."""
 return {"status": "healthy"}
```

This is the starting point for a pure FastAPI implementation.
