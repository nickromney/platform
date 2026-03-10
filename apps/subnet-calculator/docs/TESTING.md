# Testing Guide

This document describes how to run all tests for the Subnet Calculator project.

## Prerequisites

- Python 3.11+ with `uv` installed
- `curl` installed (for API endpoint tests)
- Running services (start with `podman-compose up`)

## Quick Test All Services

### Integrated Bruno CLI Tests (Recommended)

**Complete test chains that start services, run tests, and clean up:**

```bash
# Test direct launches (7000s ports)
make test-bruno-direct-full

# Test compose stacks (8000s ports)
make test-bruno-compose-full

# Test SWA stacks (4000s ports)
make test-bruno-swa-full
```

### Manual Service Testing

```bash
# Start all services
podman-compose up -d

# Test Azure Function API (port 8080)
cd api-fastapi-azure-function
USE_CURL=1 ./test_endpoints.sh --detailed http://localhost:8080/api

# Test Container App API (port 8090)
cd api-fastapi-container-app
./test_endpoints.sh --detailed

# Test Flask Frontend (port 8000)
cd frontend-python-flask
uv run pytest test_frontend.py --base-url=http://localhost:8000 -v

# Test Static Frontend (port 8001)
cd frontend-html-static
uv run pytest test_frontend.py --base-url=http://localhost:8001 -v
```

## Backend API Tests

### Azure Function API

**Location:** `api-fastapi-azure-function/`

**Unit Tests (30 tests):**

```bash
cd api-fastapi-azure-function
uv run pytest -v
```

**Endpoint Tests (17 endpoints):**

```bash
# Smoke test (5 key endpoints)
USE_CURL=1 ./test_endpoints.sh http://localhost:8080/api

# Detailed test (all 17 endpoints)
USE_CURL=1 ./test_endpoints.sh --detailed http://localhost:8080/api
```

**What it tests:**

- Health check
- IPv4/IPv6 address validation
- RFC1918 private address detection
- RFC6598 shared address space detection
- Cloudflare IP range detection
- Subnet calculations (Azure, AWS, OCI, Standard modes)
- Special cases (/31, /32 networks)

### Container App API

**Location:** `api-fastapi-container-app/`

**Unit Tests (60 tests):**

```bash
cd api-fastapi-container-app
uv run pytest -v
```

**Endpoint Tests (18 endpoints with JWT auth):**

```bash
# Smoke test (6 key endpoints)
./test_endpoints.sh

# Detailed test (all 18 endpoints)
./test_endpoints.sh --detailed

# Test remote deployment
./test_endpoints.sh --detailed https://your-api.example.com/api
```

**Authentication:**

- Automatically obtains JWT token using `demo:password123`
- Tests all endpoints with proper authentication
- No manual token management required

**What it tests:**

- Same as Azure Function API plus:
- IPv6 subnet calculations
- JWT authentication flow
- All endpoints under `/api/v1/` prefix

## Frontend Tests

### Flask Frontend (Python)

**Location:** `frontend-python-flask/`

**Playwright E2E Tests (20 tests):**

```bash
cd frontend-python-flask

# First-time setup: install browsers
uv run playwright install chromium

# Run all tests
uv run pytest test_frontend.py --base-url=http://localhost:8000 -v

# Run specific test
uv run pytest test_frontend.py::TestFrontend::test_theme_switcher -v

# Run with headed browser (see what's happening)
uv run pytest test_frontend.py --headed --base-url=http://localhost:8000
```

**What it tests:**

- Page loads correctly
- Input validation (client-side)
- Example buttons populate input
- Cloud mode selector
- Clear button functionality
- Responsive layouts (mobile, tablet, desktop)
- Copy button
- Loading states
- Error display
- Results table structure
- JavaScript fallback behavior
- Noscript warning
- Semantic HTML structure
- Accessibility

### Static HTML Frontend

**Location:** `frontend-html-static/`

**Playwright E2E Tests (23 tests):**

```bash
cd frontend-html-static

# First-time setup: install dependencies and browsers
uv sync
uv run playwright install chromium

# Run all tests
uv run pytest test_frontend.py --base-url=http://localhost:8001 -v

# Run specific test
uv run pytest test_frontend.py::TestStaticFrontend::test_theme_switcher -v

# Run with headed browser
uv run pytest test_frontend.py --headed --base-url=http://localhost:8001
```

**What it tests:**

- Page loads correctly
- Theme switcher (light/dark mode)
- Theme persistence across reloads
- Input validation
- Example buttons
- Cloud mode selector
- Clear button
- Responsive layouts (mobile, tablet, desktop)
- Copy button visibility
- Loading states
- Error display
- Results table structure
- Semantic HTML
- Accessibility (button labels)

## Running Tests in CI/CD

### GitHub Actions Example

```yaml
name: Test

on: [push, pull_request]

jobs:
 test-backend:
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4
 - uses: astral-sh/setup-uv@v5

 # Test Azure Function API
 - name: Test Azure Function
 run: |
 cd api-fastapi-azure-function
 uv run pytest -v

 # Test Container App API
 - name: Test Container App
 run: |
 cd api-fastapi-container-app
 uv run pytest -v

 test-frontend:
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4
 - uses: astral-sh/setup-uv@v5

 # Test Flask Frontend
 - name: Install Playwright
 run: |
 cd frontend-python-flask
 uv run playwright install --with-deps chromium

 - name: Start services
 run: podman-compose up -d

 - name: Test Flask Frontend
 run: |
 cd frontend-python-flask
 uv run pytest test_frontend.py --base-url=http://localhost:8000 -v

 - name: Test Static Frontend
 run: |
 cd frontend-html-static
 uv run pytest test_frontend.py --base-url=http://localhost:8001 -v
```

## Test Coverage Summary

| Component | Test Type | Count | Authentication |
| ------------------ | --------- | ------- | --------------- |
| Azure Function API | Unit | 30 | N/A |
| Azure Function API | Endpoint | 17 | None (default) |
| Container App API | Unit | 60 | N/A |
| Container App API | Endpoint | 18 | JWT (automated) |
| Flask Frontend | E2E | 20 | N/A |
| Static Frontend | E2E | 23 | N/A |
| **Total** | | **168** | |

## Troubleshooting

### Playwright browser not found

```bash
uv run playwright install chromium
```

### API endpoint tests fail with "Cannot connect"

Make sure services are running:

```bash
podman-compose up -d
podman ps # Check all containers are running
```

### JWT token errors

The test script automatically handles JWT authentication. If it fails:

1. Check API is running: `curl http://localhost:8090/api/v1/health`
1. Verify credentials in compose.yml match `demo:password123`

### Tests timeout

Some tests may timeout if the API is slow to respond. Increase timeout:

```bash
uv run pytest test_frontend.py --base-url=http://localhost:8001 -v --timeout=60
```

## Bruno CLI Integration Tests

Bruno CLI provides comprehensive API testing across all deployment stacks. Tests are organized by stack type and automatically validate authentication, health checks, and core functionality.

### Test Categories

**Direct Launches (7000s ports):**

- Azure Function API (port 7071) with JWT authentication
- Container App API (port 7080) without authentication
- Status: All tests passing (6 requests)

**Compose Stacks (8000s ports):**

- compose-01: Flask + Azure Function (JWT) - port 8000
- compose-02: Static HTML + Container App (no auth) - port 8001
- compose-03: Flask + Container App (no auth) - port 8002
- compose-04: TypeScript Vite + Container App (no auth) - port 8003
- Status: All tests passing (13 requests)

**SWA Stacks (4000s ports):**

- swa-04: TypeScript Vite + Container App (no auth) - port 4280
- swa-05: TypeScript Vite + Azure Function (JWT auth) - port 4281
- swa-06: TypeScript Vite + Container App (Entra ID at SWA layer) - port 4282
- Status: All tests passing (9 requests)

### Running Bruno Tests

```bash
# Run all direct launch tests
make test-bruno-direct

# Run all compose stack tests
make test-bruno-compose

# Run all SWA stack tests
make test-bruno-swa

# Full test chains (start services + test + cleanup)
make test-bruno-direct-full
make test-bruno-compose-full
make test-bruno-swa-full
```

### Current Test Status Summary

| Stack Type | Tests | Requests | Status |
| --- | --- | --- | --- |
| Direct Launches | 2 | 6 | PASS |
| Compose Stacks | 4 | 13 | PASS |
| SWA Stacks | 3 | 9 | PASS |
| **Total Bruno Tests** | **9** | **28** | **ALL PASS** |

## Best Practices

1. **Always run unit tests before endpoint tests** - Unit tests are faster and catch issues early
1. **Use smoke tests for quick verification** - Run `./test_endpoints.sh` without `--detailed`
1. **Run Playwright tests in headless mode for CI** - Default behavior, faster
1. **Use headed mode for debugging** - Add `--headed` flag to see browser
1. **Test one stack at a time during development** - Use `podman-compose up api-fastapi-azure-function frontend-python-flask`
1. **Use Bruno CLI for integration testing** - Full stack testing with proper authentication flows
1. **Run `make test-bruno-*-full` for complete validation** - Includes setup, testing, and cleanup
