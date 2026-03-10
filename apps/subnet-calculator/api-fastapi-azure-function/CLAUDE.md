# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Project Overview

This is an Azure Functions project that provides an IPv4/IPv6 address
validation and analysis microservice. Built with Python 3.11 using FastAPI
with Azure Functions ASGI middleware.

The API provides:

- IPv4/IPv6 address and CIDR network validation
- RFC1918 (private) and RFC6598 (shared address space) detection
- Cloudflare IP range detection (both IPv4 and IPv6)
- Auto-generated OpenAPI/Swagger documentation

## Architecture

- **Framework**: FastAPI with Pydantic models for request validation
- **Function App Entry Point**: `function_app.py` - FastAPI app wrapped in
  Azure Functions ASGI middleware
- **Core Library**: Python's built-in `ipaddress` module for IP address
  operations
- **Azure Functions Runtime**: ASGI middleware (`func.AsgiMiddleware`)
  bridges FastAPI to Azure Functions
- **Python Version**: 3.11 (specified in `.python-version`, compatible with Azure Static Web Apps)
- **Package Manager**: Uses `uv` for dependency management (evidenced by
  `uv.lock` file)
- **OpenAPI Docs**: Auto-generated at `/api/v1/docs` (Swagger UI) and
  `/api/v1/redoc` (ReDoc)

## Development Commands

### Local Development

```bash
# Install dependencies
uv sync

# Install dev dependencies (includes pytest)
uv sync --extra dev

# Run tests
uv run pytest

# Run tests with verbose output
uv run pytest -v

# Run tests with coverage
uv run pytest --cov=function_app

# Run Azure Functions locally
func start
```

### Docker

```bash
# Build Docker image
docker build -t python-api .

# The Dockerfile uses the official Azure Functions Python 4 runtime
# with Python 3.11
```

### Testing Functions Locally

All endpoints are accessible at `http://localhost:7071/api/v1/` when
running locally.

#### Health Check

```bash
curl http://localhost:7071/api/v1/health
```

#### Validate IPv4/IPv6 Address

```bash
curl -X POST http://localhost:7071/api/v1/ipv4/validate \
  -H "Content-Type: application/json" \
  -d '{"address": "192.168.1.1"}'

curl -X POST http://localhost:7071/api/v1/ipv4/validate \
  -H "Content-Type: application/json" \
  -d '{"address": "192.168.1.0/24"}'
```

#### Check RFC1918/RFC6598 Private Address

```bash
curl -X POST http://localhost:7071/api/v1/ipv4/check-private \
  -H "Content-Type: application/json" \
  -d '{"address": "192.168.1.1"}'

curl -X POST http://localhost:7071/api/v1/ipv4/check-private \
  -H "Content-Type: application/json" \
  -d '{"address": "100.64.0.1"}'
```

#### Check Cloudflare IP Range

```bash
curl -X POST http://localhost:7071/api/v1/ipv4/check-cloudflare \
  -H "Content-Type: application/json" \
  -d '{"address": "104.16.1.1"}'

curl -X POST http://localhost:7071/api/v1/ipv4/check-cloudflare \
  -H "Content-Type: application/json" \
  -d '{"address": "2606:4700::1"}'
```

#### Get Subnet Information (with Cloud Provider Modes)

```bash
# Default (Azure mode)
curl -X POST http://localhost:7071/api/v1/ipv4/subnet-info \
  -H "Content-Type: application/json" \
  -d '{"network": "192.168.1.0/24"}'

# AWS mode
curl -X POST http://localhost:7071/api/v1/ipv4/subnet-info \
  -H "Content-Type: application/json" \
  -d '{"network": "10.0.0.0/24", "mode": "AWS"}'

# OCI mode
curl -X POST http://localhost:7071/api/v1/ipv4/subnet-info \
  -H "Content-Type: application/json" \
  -d '{"network": "10.0.0.0/24", "mode": "OCI"}'

# Standard mode
curl -X POST http://localhost:7071/api/v1/ipv4/subnet-info \
  -H "Content-Type: application/json" \
  -d '{"network": "10.0.0.0/24", "mode": "Standard"}'
```

### Automated Endpoint Testing

You can run the `test_endpoints.sh` script to test all API endpoints:

```bash
# Smoke test on local API (port 7071) - 5 key endpoints
./test_endpoints.sh

# Detailed test - all 17 endpoints with commands shown
./test_endpoints.sh --detailed

# Test containerized API (port 8080)
./test_endpoints.sh --container

# Test Azure deployment
./test_endpoints.sh --detailed https://your-api.azurewebsites.net/api
```

The script automatically detects and uses `xh` (HTTPie) if available,
otherwise falls back to `curl`.

## Configuration Files

- `host.json` - Azure Functions host configuration using Extension Bundle
  v4, includes CORS settings for cross-origin requests
- `local.settings.json` - Local development settings (not committed to
  source control)
- `function_app.py` - Function app definition with decorator-based triggers
- `pyproject.toml` - Project metadata and dependencies
- `requirements.txt` - Python dependencies (generated from pyproject.toml)

## CORS Configuration

CORS is configured in `host.json` to allow cross-origin requests from
frontend applications:

- **Allowed Origins**: `*` (all origins - configure specific domains for
  production)
- **Allowed Methods**: GET, POST, OPTIONS
- **Allowed Headers**: Content-Type, Accept

For production deployments, update the `allowedOrigins` array in
`host.json` to specify your frontend domain(s).

## Key Dependencies

- `azure-functions>=1.23.0` - Azure Functions runtime with ASGI middleware
  support
- `fastapi[standard]>=0.118.0` - FastAPI framework with standard extras
  (uvicorn, httptools, Pydantic, etc.)

**Development Dependencies:**

- `pytest>=8.0.0` - Testing framework
- `httpx` - Required by FastAPI's TestClient (auto-installed with FastAPI)

## Interactive API Documentation

FastAPI auto-generates interactive API documentation:

- **Swagger UI**: `http://localhost:7071/api/v1/docs`
  - Interactive API explorer with "Try it out" functionality
  - Auto-generated from endpoint definitions and Pydantic models

- **ReDoc**: `http://localhost:7071/api/v1/redoc`
  - Alternative documentation with clean, responsive design

- **OpenAPI Schema**: `http://localhost:7071/api/v1/openapi.json`
  - Raw OpenAPI 3.0 specification (version 1.0.0)
  - Use for client code generation (TypeScript, Python, etc.)

When deployed to Azure, replace `localhost:7071` with your Azure Functions
URL.

## API Endpoints

All endpoints are versioned under `/api/v1/`.

### GET /api/v1/health

Health check endpoint. Returns API status and version.

**Response:**

```json
{
  "status": "healthy",
  "service": "Subnet Calculator API (Azure Function)",
  "version": "1.0.0"
}
```

### POST /api/v1/ipv4/validate

Validate if an IPv4/IPv6 address or CIDR range is well-formed.

**Request:**

```json
{"address": "192.168.1.1"}
```

**Response (address):**

```json
{
  "valid": true,
  "type": "address",
  "address": "192.168.1.1",
  "is_ipv4": true,
  "is_ipv6": false
}
```

**Response (network):**

```json
{
  "valid": true,
  "type": "network",
  "address": "192.168.1.0/24",
  "network_address": "192.168.1.0",
  "netmask": "255.255.255.0",
  "prefix_length": 24,
  "num_addresses": 256,
  "is_ipv4": true,
  "is_ipv6": false
}
```

### POST /api/v1/ipv4/check-private

Check if an IPv4 address or range is RFC1918 (private: 10.0.0.0/8,
172.16.0.0/12, 192.168.0.0/16) or RFC6598 (shared: 100.64.0.0/10).

**Request:**

```json
{"address": "192.168.1.1"}
```

**Response:**

```json
{
  "address": "192.168.1.1",
  "is_rfc1918": true,
  "is_rfc6598": false,
  "matched_rfc1918_range": "192.168.0.0/16"
}
```

### POST /api/v1/ipv4/check-cloudflare

Check if an IP address or range is within Cloudflare's IPv4 or IPv6 ranges.

**Request:**

```json
{"address": "104.16.1.1"}
```

**Response:**

```json
{
  "address": "104.16.1.1",
  "is_cloudflare": true,
  "ip_version": 4,
  "matched_ranges": ["104.16.0.0/13"]
}
```

### POST /api/v1/ipv4/subnet-info

Calculate subnet information including usable IP ranges with cloud provider
reservation modes.

**Cloud Provider IP Reservations:**

- **Azure/AWS**: Reserve 5 IPs (.0, .1, .2, .3, and broadcast)
- **OCI**: Reserve 3 IPs (.0, .1, and broadcast)
- **Standard**: Reserve 2 IPs (.0 and broadcast)
- **/31 and /32**: No reservations (point-to-point and host routes)

**Request:**

```json
{
  "network": "192.168.1.0/24",
  "mode": "Azure"
}
```

**Response:**

```json
{
  "network": "192.168.1.0/24",
  "mode": "Azure",
  "network_address": "192.168.1.0",
  "broadcast_address": "192.168.1.255",
  "netmask": "255.255.255.0",
  "wildcard_mask": "0.0.0.255",
  "prefix_length": 24,
  "total_addresses": 256,
  "usable_addresses": 251,
  "first_usable_ip": "192.168.1.4",
  "last_usable_ip": "192.168.1.254"
}
```

**Special Cases:**

/31 (Point-to-Point):

```json
{
  "network": "10.0.0.0/31",
  "total_addresses": 2,
  "usable_addresses": 2,
  "first_usable_ip": "10.0.0.0",
  "last_usable_ip": "10.0.0.1",
  "broadcast_address": null,
  "note": "RFC 3021 point-to-point link (no broadcast)"
}
```

/32 (Host Route):

```json
{
  "network": "10.0.0.5/32",
  "total_addresses": 1,
  "usable_addresses": 1,
  "first_usable_ip": "10.0.0.5",
  "last_usable_ip": "10.0.0.5",
  "broadcast_address": null,
  "note": "Single host address"
}
```

## Function Structure

This project uses FastAPI wrapped in Azure Functions ASGI middleware:

```python
# 1. Create FastAPI app with OpenAPI documentation
api = fastapi.FastAPI(
    title="IPv4 Subnet Validation API",
    version="1.0.0",
    docs_url="/api/v1/docs",
    openapi_url="/api/v1/openapi.json"
)

# 2. Define Pydantic models for request validation
class ValidateRequest(BaseModel):
    address: str = Field(..., description="IP address or CIDR notation")

# 3. Define FastAPI endpoints with async functions
@api.post("/api/v1/ipv4/validate")
async def validate_ipv4(request: ValidateRequest):
    # Automatic request validation via Pydantic
    # Return dict (auto-converted to JSON)
    return {"valid": True, "address": request.address}

# 4. Create Azure Function wrapper (single catch-all route)
app = func.FunctionApp()

@app.function_name(name="HttpTrigger")
@app.route(route="{*route}", auth_level=func.AuthLevel.ANONYMOUS)
async def http_trigger(
    req: func.HttpRequest,
    context: func.Context
) -> func.HttpResponse:
    """Forwards all requests to FastAPI via ASGI middleware"""
    return await func.AsgiMiddleware(api).handle_async(req, context)
```

**Key Benefits:**

- Pydantic automatic validation (422 errors for invalid input)
- FastAPI's `HTTPException` for custom errors
- Auto-generated OpenAPI/Swagger docs
- Cleaner async/await syntax
- Type hints throughout

## Testing

The project uses **FastAPI's TestClient** for testing, which properly
handles the ASGI app without requiring Azure Functions runtime:

```python
from fastapi.testclient import TestClient
from function_app import api

client = TestClient(api)

# Test example
def test_valid_ipv4_address():
    response = client.post(
        "/api/v1/ipv4/validate",
        json={"address": "192.168.1.1"}
    )
    assert response.status_code == 200
    assert response.json()["valid"] is True
```

The project includes pytest-based tests in `test_function_app.py` that
cover:

- **Health Check**: Validates the health endpoint returns correct status
- **API Documentation**: Tests Swagger UI and OpenAPI schema accessibility
- **IPv4/IPv6 Validation**: Tests valid/invalid addresses and networks,
  CIDR notation
- **RFC1918/RFC6598 Detection**: Tests all private ranges (10.x, 172.16.x,
  192.168.x) and shared address space (100.64.x)
- **Cloudflare Range Detection**: Tests both IPv4 and IPv6 Cloudflare
  addresses and networks
- **Subnet Calculations**: Tests all cloud provider modes (Azure, AWS, OCI,
  Standard), /31 and /32 special cases, wildcard masks
- **Error Handling**: Tests invalid inputs, missing fields, and edge cases
  (422 for Pydantic validation, 400 for business logic errors)

Run tests with:

```bash
uv run pytest                    # Run all tests (30 tests)
uv run pytest -v                 # Verbose output
uv run pytest test_function_app.py::TestSubnetInfo  # Run specific test
```

## IP Address Ranges

**RFC1918 Private Ranges:**

- 10.0.0.0/8
- 172.16.0.0/12
- 192.168.0.0/16

**RFC6598 Shared Address Space:**

- 100.64.0.0/10

**Cloudflare IPv4 Ranges:** See `CLOUDFLARE_IPV4_RANGES` in
function_app.py:20-36

**Cloudflare IPv6 Ranges:** See `CLOUDFLARE_IPV6_RANGES` in
function_app.py:39-47
