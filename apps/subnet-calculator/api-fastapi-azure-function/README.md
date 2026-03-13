# IPv4 Subnet Validation API

A lightweight microservice API for IPv4/IPv6 address validation, subnet calculations, and cloud provider IP analysis. Built with FastAPI and Azure Functions on Python 3.11.

## Overview

This is the **backend API** for a subnet calculator project. It provides RESTful endpoints for network address validation and subnet calculations with support for cloud provider-specific IP reservations (Azure, AWS, OCI).

**Related Repositories:**

- Frontend: `frontend-python-flask`

## Features

- **IPv4/IPv6 Validation**: Validate IP addresses and CIDR notation
- **RFC1918 Detection**: Identify private address spaces (10.x, 172.16.x, 192.168.x)
- **RFC6598 Detection**: Identify shared address space (100.64.x/10)
- **Cloudflare Range Detection**: Check if IPs belong to Cloudflare's IPv4/IPv6 ranges
- **Subnet Calculations**: Calculate usable IP ranges with cloud provider modes
  - Azure/AWS: 5 IP reservations
  - OCI: 3 IP reservations
  - Standard: 2 IP reservations
  - Special handling for /31 (point-to-point) and /32 (host routes)
- **Interactive API Documentation**: Auto-generated Swagger UI and ReDoc interfaces
- **Flexible Authentication**: Progressive enhancement with feature flags
  - API Keys (X-API-Key header)
  - No auth mode (backward compatible)
  - Future: JWT, Azure AD/Entra ID

## Authentication

The API supports multiple authentication modes via the `AUTH_METHOD` environment variable:

### No Authentication (Default)

```bash
# Default mode - no authentication required
export AUTH_METHOD=none
# Or simply omit AUTH_METHOD
```

All requests succeed without authentication headers. This maintains backward compatibility with existing deployments.

### API Key Authentication

```bash
export AUTH_METHOD=api_key
export API_KEYS=your-key-1,your-key-2,your-key-3
```

**Usage:**

```bash
curl -H "X-API-Key: your-key-1" http://localhost:7071/api/v1/health
```

**Behavior:**

- Returns `401 Unauthorized` if `X-API-Key` header is missing
- Returns `401 Unauthorized` if API key is invalid
- API keys are case-sensitive
- Multiple keys supported (comma-separated)
- Leading/trailing whitespace is stripped from keys

**Example responses:**

```json
// Missing header
{"detail": "Missing X-API-Key header"}

// Invalid key
{"detail": "Invalid API key"}
```

### Testing Authentication

```bash
# Unit tests
uv run pytest test_auth.py -v

# Integration tests with curl
./test_auth.sh
```

### Future Authentication Methods

- **JWT**: Token-based authentication with claims
- **Azure AD/Entra ID**: Enterprise SSO integration

All authentication methods use the same codebase with feature flags for easy switching.

### Managed Identity Proxy Regression Test

When working on the Web App → Function App proxy, run the dedicated Easy Auth suite to confirm the backend still accepts requests that arrive with managed identity headers instead of direct user principals:

```bash
uv run pytest test_azure_swa.py -k managed_identity
```

Those tests also cover the nested claim parsing added for Azure Easy Auth, so run them whenever you change `function_app.py`.

## Interactive API Documentation

FastAPI auto-generates interactive API documentation that you can use to explore and test endpoints directly in your browser:

- **Swagger UI**: `http://localhost:7071/api/v1/docs`

  - Interactive API explorer with "Try it out" functionality
  - Test endpoints directly from the browser

- **ReDoc**: `http://localhost:7071/api/v1/redoc`

  - Clean, responsive API documentation

- **OpenAPI Schema**: `http://localhost:7071/api/v1/openapi.json`
  - Raw OpenAPI 3.0 specification (version 1.0.0)
  - Use for client code generation

When running in a container, use `http://localhost:8080/api/v1/docs` instead.

## API Endpoints

All endpoints are versioned under `/api/v1/`.

### Health Check

```http
GET /api/v1/health
```

### Validate IP Address

```http
POST /api/v1/ipv4/validate
Content-Type: application/json

{
  "address": "192.168.1.1" or "192.168.1.0/24"
}
```

### Check RFC1918/RFC6598

```http
POST /api/v1/ipv4/check-private
Content-Type: application/json

{
  "address": "192.168.1.1"
}
```

### Check Cloudflare Range

```http
POST /api/v1/ipv4/check-cloudflare
Content-Type: application/json

{
  "address": "104.16.1.1"
}
```

### Subnet Information

```http
POST /api/v1/ipv4/subnet-info
Content-Type: application/json

{
  "network": "192.168.1.0/24",
  "mode": "Azure"  // Optional: Azure, AWS, OCI, Standard
}
```

The examples above cover the main endpoints. For the current implementation
details, see `function_app.py` and the test suite in this directory.

## Local Development

### Prerequisites

- Python 3.11+
- [uv](https://github.com/astral-sh/uv) package manager
- Azure Functions Core Tools

### Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/python-api.git
cd python-api

# Install dependencies
uv sync

# Install dev dependencies (includes pytest)
uv sync --extra dev

# Run tests
uv run pytest -v

# Start the API locally
uv run func start
```

The API will be available at `http://localhost:7071/api/`

### Testing the API

Use the included test script to verify endpoints are working. By default, it runs a quick smoke test:

```bash
# Smoke test on local Azure Functions API (port 7071)
./test_endpoints.sh

# Smoke test on containerized API (port 8080)
./test_endpoints.sh --container

# Detailed test of all endpoints with command output
./test_endpoints.sh --detailed

# Detailed test on container
./test_endpoints.sh --detailed --container

# Test Azure deployment (HTTPS on port 443)
./test_endpoints.sh --detailed https://your-api.azurewebsites.net/api
```

The script automatically detects and uses `xh` (HTTPie) if available, otherwise falls back to `curl`.

**Smoke test** runs 5 key endpoints to verify the API is working.

**Detailed test** runs all 17 endpoints and shows the full commands (copy-pasteable for manual testing).

**Manual testing examples:**

Using xh:

```bash
# Set your API URL (choose one based on where you're testing)
API_URL="http://localhost:7071/api/v1"           # Local Azure Functions
# API_URL="http://localhost:8080/api/v1"         # Container
# API_URL="https://your-api.azurewebsites.net/api/v1"  # Azure deployment

# Health check
xh GET $API_URL/health

# Validate IP address
xh POST $API_URL/ipv4/validate address=192.168.1.1

# Check private address
xh POST $API_URL/ipv4/check-private address=192.168.1.1

# Check Cloudflare range
xh POST $API_URL/ipv4/check-cloudflare address=104.16.1.1

# Get subnet info (Azure mode)
xh POST $API_URL/ipv4/subnet-info network=192.168.1.0/24 mode=Azure
```

Using curl:

```bash
# Set your API URL (choose one based on where you're testing)
API_URL="http://localhost:7071/api/v1"           # Local Azure Functions
# API_URL="http://localhost:8080/api/v1"         # Container
# API_URL="https://your-api.azurewebsites.net/api/v1"  # Azure deployment

# Health check
curl $API_URL/health

# Validate IP address
curl -X POST $API_URL/ipv4/validate \
  -H "Content-Type: application/json" \
  -d '{"address": "192.168.1.1"}'

# Check private address
curl -X POST $API_URL/ipv4/check-private \
  -H "Content-Type: application/json" \
  -d '{"address": "192.168.1.1"}'

# Get subnet info (Azure mode)
curl -X POST $API_URL/ipv4/subnet-info \
  -H "Content-Type: application/json" \
  -d '{"network": "192.168.1.0/24", "mode": "Azure"}'
```

### Running Tests

```bash
# Run all tests (30 tests: 28 endpoint tests + 2 documentation tests)
uv run pytest

# Run with verbose output
uv run pytest -v

# Run specific test class
uv run pytest test_function_app.py::TestSubnetInfo
```

## Example Usage

### Validate an IP Address

```bash
curl -X POST http://localhost:7071/api/v1/ipv4/validate \
  -H "Content-Type: application/json" \
  -d '{"address": "192.168.1.1"}'
```

**Response:**

```json
{
  "valid": true,
  "type": "address",
  "address": "192.168.1.1",
  "is_ipv4": true,
  "is_ipv6": false
}
```

### Calculate Subnet Information (Azure Mode)

```bash
curl -X POST http://localhost:7071/api/v1/ipv4/subnet-info \
  -H "Content-Type: application/json" \
  -d '{"network": "192.168.1.0/24", "mode": "Azure"}'
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

### Check if IP is in Cloudflare Range

```bash
curl -X POST http://localhost:7071/api/v1/ipv4/check-cloudflare \
  -H "Content-Type: application/json" \
  -d '{"address": "104.16.1.1"}'
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

## Tech Stack

- **Runtime**: Python 3.11
- **Framework**: FastAPI with Azure Functions ASGI middleware
- **Core Library**: Python's built-in `ipaddress` module
- **API Documentation**: Auto-generated OpenAPI/Swagger via FastAPI
- **Testing**: pytest with FastAPI TestClient (28 comprehensive tests)
- **Package Manager**: uv
- **Deployment**: Azure Functions

## CORS Configuration

CORS is enabled in `host.json` to allow cross-origin requests from frontend applications:

```json
{
  "allowedOrigins": ["*"],
  "allowedMethods": ["GET", "POST", "OPTIONS"],
  "allowedHeaders": ["Content-Type", "Accept"]
}
```

**Note**: For production, replace `"*"` with your specific frontend domain(s).

## Architecture

This API follows a microservice architecture pattern:

```text
Frontend (Static Web App)
    ↓ HTTP/JSON
Backend API (Azure Functions) ← You are here
    ↓
Python ipaddress library
```

### Benefits

- Stateless API design
- Auto-scaling with Azure Functions
- Independently deployable
- Reusable across multiple frontends

## Project Structure

```text
subnet-calculator-python-api/
├── function_app.py          # Azure Functions API endpoints
├── test_function_app.py     # Pytest test suite (28 tests)
├── test_endpoints.sh        # API endpoint testing script (smoke + detailed)
├── host.json                # Azure Functions config with CORS
├── local.settings.json      # Local development settings
├── Dockerfile               # Container image with virtual environment
├── .dockerignore            # Docker build exclusions
├── requirements.txt         # Python dependencies
├── pyproject.toml           # Project metadata and dev dependencies
└── README.md                # This file
```

## Deployment

### Container Deployment

#### Using Docker

```bash
# Build image
docker build --platform linux/amd64 -t subnet-calculator-python-api:v1 .

# Run locally
docker run --platform linux/amd64 --rm -it --init -p 8080:8080 subnet-calculator-python-api:v1
```

#### Using Podman

```bash
# Build image
podman build --platform linux/amd64 --tag subnet-calculator-python-api:v1 .

# Run locally
podman run --platform linux/amd64 --rm -it --init -p 8080:8080 subnet-calculator-python-api:v1
```

**Note on flags:**

- `--rm`: Automatically removes the container when it stops
- `-it`: Runs interactively with a pseudo-TTY for real-time logs
- `--init`: Adds an init process (PID 1) that properly handles signals like Ctrl+C
- `-p 8080:8080`: Maps container port 8080 to host port 8080

The `--init` flag is particularly important for Azure Functions, as the runtime intercepts but doesn't properly handle SIGINT without it.

Once running, access the API at `http://localhost:8080/api/`

## Blog Series

This project is part of a blog series on building microservices with Python and Azure:

- **Part 1**: Building the IPv4 Validation API _(link coming soon)_
- **Part 2**: Creating a Static Frontend _(coming soon)_
- **Part 3**: Deployment and CI/CD _(coming soon)_

## License

Copyright © 2025 Nick Romney. All rights reserved.

## Links

- [Azure Functions Documentation](https://docs.microsoft.com/azure/azure-functions/)
- [Python ipaddress Module](https://docs.python.org/3/library/ipaddress.html)
- [RFC 1918 - Private Address Spaces](https://datatracker.ietf.org/doc/html/rfc1918)
- [RFC 6598 - Shared Address Space](https://datatracker.ietf.org/doc/html/rfc6598)
- [RFC 3021 - Point-to-Point Links (/31)](https://datatracker.ietf.org/doc/html/rfc3021)

---

Built with Python and Azure Functions
