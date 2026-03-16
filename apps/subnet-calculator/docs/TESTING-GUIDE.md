# Comprehensive Testing Guide for Subnet Calculator

This document provides a complete overview of all testing methods available for the subnet calculator project across all environments: local development, podman-compose stacks, SWA CLI emulation, and Azure deployments.

## Table of Contents

1. [Testing Overview](#testing-overview)
1. [Podman Compose Stack Testing](#podman-compose-stack-testing)
1. [SWA CLI Local Emulator Testing](#swa-cli-local-emulator-testing)
1. [Azure Deployment Testing](#azure-deployment-testing)
1. [Test Coverage Summary](#test-coverage-summary)

---

## Testing Overview

The subnet calculator has **~320 tests** across multiple layers:

| Layer | Test Type | Count | Tools |
| ------------------- | ---------------- | ------- | -------------------- |
| **Backend APIs** | Unit + Endpoint | 185 | pytest, curl |
| **Frontend** | E2E + Unit | 43 | Playwright |
| **SWA Proxy** | Integration | 8 | Playwright + SWA CLI |
| **API Collections** | Manual/Automated | 12 | Bruno CLI |
| **Integration** | Stack Testing | 10 | Makefile + shell |
| **Deployment** | Production | Various | Azure CLI + curl |

---

## Podman Compose Stack Testing

### Overview

Local stacks run in containers using `podman-compose up`. This is the fastest way to test the entire application locally.

**Local Stacks (from `compose.yml`):**

- **local-stack-01**: Static HTML + Container App (No Auth)
- **local-stack-02**: Flask + Container App (No Auth)
- **local-stack-03**: Flask + Azure Function (JWT)
- **local-stack-04**: TypeScript Vite + Container App (No Auth)
- **local-stack-05**: TypeScript Vite + Azure Function (JWT)

### Quick Start - Test All Stacks

```bash
# Start all services in background
cd apps/subnet-calculator
podman-compose up -d

# Wait for services to be healthy
sleep 10

# Test everything
make test-all # (or individual stack tests below)
```

### Backend API Testing

#### Azure Function API Tests

**Location:** `api-fastapi-azure-function/`

**Unit Tests (108 tests):**

```bash
cd api-fastapi-azure-function
uv run pytest -v
```

**Endpoint Tests (17 endpoints):**

```bash
# Start Azure Function in foreground or use compose
# Smoke test (5 key endpoints, runs in ~5 sec)
USE_CURL=1 ./test_endpoints.sh http://localhost:8080/api

# Detailed test (all 17 endpoints, runs in ~10 sec)
USE_CURL=1 ./test_endpoints.sh --detailed http://localhost:8080/api
```

**What is tested:**

- Health check endpoint
- IPv4/IPv6 address validation
- RFC1918 private address detection (10.x, 172.16.x, 192.168.x)
- RFC6598 shared address space (100.64.x)
- Cloudflare IP range detection
- Subnet calculations (Azure, AWS, OCI, Standard modes)
- Special cases (/31 point-to-point, /32 single host)

#### Container App API Tests

**Location:** `api-fastapi-container-app/`

**Unit Tests (60 tests):**

```bash
cd api-fastapi-container-app
uv run pytest -v
```

**Endpoint Tests (18 endpoints with JWT):**

```bash
# Smoke test (6 key endpoints)
./test_endpoints.sh

# Detailed test (all 18 endpoints)
./test_endpoints.sh --detailed

# Test remote deployment
./test_endpoints.sh --detailed https://your-api.example.com/api
```

**Authentication:** Automatically obtains JWT token using `demo:password123`

### Frontend Testing

#### Flask Frontend E2E Tests

**Location:** `frontend-python-flask/`

**Playwright Tests (20 tests):**

```bash
cd frontend-python-flask

# First-time: install browsers
uv run playwright install chromium

# Run all tests (headless, fastest)
uv run pytest test_frontend.py --base-url=http://localhost:8000 -v

# Run specific test
uv run pytest test_frontend.py::TestFrontend::test_page_load -v

# Run with headed browser (debug mode)
uv run pytest test_frontend.py --headed --base-url=http://localhost:8000
```

**Tests covered:**

- Page loads correctly
- Input validation (client-side)
- Example buttons populate input
- Cloud mode selector
- Clear button functionality
- Responsive layouts (mobile 375px, tablet 768px, desktop 1280px)
- Copy button
- Loading states
- Error display
- Results table structure

#### Static HTML Frontend E2E Tests

**Location:** `frontend-html-static/`

**Playwright Tests (23 tests):**

```bash
cd frontend-html-static
uv sync
uv run playwright install chromium

# Run all tests
uv run pytest test_frontend.py --base-url=http://localhost:8001 -v

# Debug mode
uv run pytest test_frontend.py --headed --base-url=http://localhost:8001
```

**Tests covered:**

- Theme switcher (light/dark mode)
- Theme persistence
- Input validation
- Example buttons
- Cloud mode selector
- Responsive layouts
- Copy button visibility
- Error handling

#### TypeScript Vite Unit Tests

**Location:** `frontend-typescript-vite/`

**Unit Tests (30 tests - mocked API):**

```bash
cd frontend-typescript-vite
bun install

# Run all tests
bun run test

# Run with browser visible
bun run test:headed

# Interactive UI mode
bun run test:ui
```

### Makefile Test Targets

Run tests using built-in Makefile shortcuts:

```bash
# Test individual stacks
make test-stack4 # Tests local-stack-04 (Vite + Container App, no auth)
make test-stack5 # Tests local-stack-05 (Vite + Azure Function, JWT)

# Test with Bruno collections
make test-bruno-stack4 # Bruno tests for local-stack-04
make test-bruno-stack5 # Bruno tests for local-stack-05
make test-bruno-stack6 # Bruno tests for local-stack-06 (Entra ID)

# Start services
make start-swa-04 # Start local-stack-04
make start-swa-05 # Start local-stack-05
make start-swa-06 # Start local-stack-06
```

### Bruno API Testing

**Location:** `bruno-collections/`

**Collections:**

- Local Stack 01 (3 tests)
- Local Stack 04 (3 tests)
- Local Stack 05 (3 tests) + JWT login
- Azure Stack 06 (3 tests) + Entra ID auth (requires browser)

**Via Makefile:**

```bash
make test-bruno-stack4 # Run Bruno tests for stack 4
make test-bruno-stack5 # Run Bruno tests for stack 5
```

**Via Bruno CLI:**

```bash
cd bruno-collections
bun x @usebruno/cli@latest run "Local Stack 04" --env local
bun x @usebruno/cli@latest run "Local Stack 05" --env local
bun x @usebruno/cli@latest run --env local -r # Run all collections
```

**Via Bruno GUI (Interactive):**

```bash
brew install --cask bruno
# Then: File → Open Collection → Select bruno-collections/
```

---

## SWA CLI Local Emulator Testing

### Overview

SWA CLI emulates Azure Static Web Apps locally, allowing you to test the same routing, authentication, and backend linking that will happen in production.

**Configuration:** `swa-cli.config.json` defines three SWA emulation stacks:

- **stack4-no-auth** (port 4280): Vite + Container App, no authentication
- **stack5-jwt** (port 4281): Vite + Azure Function, JWT authentication
- **stack6-entra** (port 4282): Vite + Azure Function, Entra ID emulation

### Quick Start - SWA CLI

```bash
# Start SWA CLI for local-stack-04 (no auth)
bun run swa -- start stack4-no-auth

# In another terminal, run SWA tests
cd frontend-typescript-vite
bun run test:swa:stack4
```

### What SWA CLI Does

- **Proxies frontend**: Vite dev server at `http://localhost:5173`
- **Proxies API**: Container App (port 8000) or Azure Function (port 7071)
- **Emulates routing**: Applies `staticwebapp.config.json` rules
- **Emulates auth**: Mocks SWA authentication (limited enforcement)
- **Serves all on one port**: 4280, 4281, or 4282

### SWA CLI Testing

#### SWA Playwright Tests

**Location:** `frontend-typescript-vite/tests/swa.spec.ts`

**8 Integration Tests:**

```bash
cd frontend-typescript-vite

# Test local-stack-04 (port 4280)
bun run test:swa:stack4

# Test local-stack-05 (port 4281)
bun run test:swa:stack5

# Run with browser visible (debugging)
bun run test:swa:headed
```

**Tests covered:**

- Page loads through SWA proxy
- API health check through SWA proxy
- Frontend HMR (hot module reload)
- API calls through SWA proxy
- Multiple endpoints
- SWA routes work correctly
- Content-type validation
- Frontend and API serving

#### Manual SWA Testing

**Test local-stack-04 (No Auth):**

```bash
# Terminal 1: Start Container App API
cd api-fastapi-container-app
uv run uvicorn app.main:app --reload --port 8000

# Terminal 2: Start SWA CLI
bun run swa -- start stack4-no-auth

# Terminal 3: Test in browser or with curl
open http://localhost:4280
curl http://localhost:4280/api/v1/health
```

**Test local-stack-05 (JWT Auth):**

```bash
# SWA CLI auto-starts Azure Function
bun run swa -- start stack5-jwt

# Browser tests automatic JWT login
open http://localhost:4281

# curl test (must extract JWT first)
TOKEN=$(curl -s -X POST http://localhost:4281/api/v1/auth/login \
 -H "Content-Type: application/x-www-form-urlencoded" \
 -d "username=demo&password=password123" | jq -r '.access_token')
curl -H "Authorization: Bearer $TOKEN" http://localhost:4281/api/v1/health
```

### Important SWA CLI Limitations

**Local Emulation vs Production:**

1. **Route Protection NOT Enforced Locally**

- `staticwebapp.config.json` routes with `allowedRoles` are NOT checked
- You can access protected routes without authentication
- This is a known SWA CLI limitation

1. **Authentication is Mocked**

- Entra ID login is emulated, not real
- You can log in with any username locally
- Production uses real Entra ID

1. **Testing Best Practices**

- Test frontend logic locally with SWA CLI
- Test authentication in Azure after deployment
- Use Bruno collections for API-level testing

---

## Azure Deployment Testing

### Static Web App Deployment Testing

**Location:** `~/Developer/personal/azure-tui/infrastructure/azure/test-static-deployment.sh`

```bash
# Test a deployed Static Web App
./test-static-deployment.sh https://your-swa.azurestaticapps.net

# What it checks:
# - Main page loads
# - Extracts API_BASE_URL from deployed app
# - Tests API endpoints
# - Validates static assets
```

### Production Testing Checklist

After deploying to Azure:

1. **Frontend Access**

```bash
# Should load without errors
open https://your-swa.azurestaticapps.net
```

1. **API Health**

```bash
# Check health endpoint
curl https://your-swa.azurestaticapps.net/api/v1/health

# Or if function is separate
curl https://your-func-app.azurewebsites.net/api/v1/health
```

1. **Authentication** (if applicable)

```bash
# For Entra ID stacks
# Should redirect to login.microsoftonline.com
curl -L https://your-swa.azurestaticapps.net/api/v1/health

# Check auth status
curl https://your-swa.azurestaticapps.net/.auth/me
```

1. **End-to-End Workflow**

- Open app in browser
- If auth required: login
- Enter CIDR: `10.0.0.0/24`
- Click Calculate
- Verify results

### Bruno Collections for Deployed Stacks

Test production deployments with Bruno:

```bash
# Set environment to production
cd bruno-collections
bun x @usebruno/cli@latest run "Azure Stack 06" --env production
```

---

## Test Coverage Summary

### Complete Test Inventory

| Component | Test Type | Count | File/Location | Auth |
| ------------------------ | ----------- | -------- | ---------------------------------------------------- | ------------ |
| **Backend APIs** | | | | |
| Azure Function | Unit | 108 | `api-fastapi-azure-function/tests/` | N/A |
| Azure Function | Endpoint | 17 | `api-fastapi-azure-function/test_endpoints.sh` | None |
| Azure Function | Auth | 3 | `api-fastapi-azure-function/test_auth.sh` | Various |
| Container App | Unit | 60 | `api-fastapi-container-app/tests/` | N/A |
| Container App | Endpoint | 18 | `api-fastapi-container-app/test_endpoints.sh` | JWT |
| **Frontend** | | | | |
| Flask | E2E | 20 | `frontend-python-flask/test_frontend.py` | None |
| Static HTML | E2E | 23 | `frontend-html-static/test_frontend.py` | None |
| TypeScript Vite | Unit | 30 | `frontend-typescript-vite/tests/frontend.spec.ts` | Mocked |
| TypeScript Vite | Integration | 8 | `frontend-typescript-vite/tests/integration.spec.ts` | Real API |
| TypeScript Vite | SWA | 8 | `frontend-typescript-vite/tests/swa.spec.ts` | SWA emulated |
| **API Collections** | | | | |
| Bruno - Local Stack 01 | Manual/CLI | 3 | `bruno-collections/Local Stack 01/` | None |
| Bruno - Local Stack 04 | Manual/CLI | 3 | `bruno-collections/Local Stack 04/` | None |
| Bruno - Local Stack 05 | Manual/CLI | 3 | `bruno-collections/Local Stack 05/` | JWT |
| Bruno - Azure Stack 06 | Manual/CLI | 3 | `bruno-collections/Azure Stack 06/` | Entra ID |
| **Makefile Integration** | | | | |
| Stack 4 | Integration | 5 | `Makefile:test-stack4` | None |
| Stack 5 | Integration | 5 | `Makefile:test-stack5` | JWT |
| | | | | |
| **TOTAL TESTS** | | **~320** | | |

### Test Execution Time

| Test Suite | Time | Notes |
| ------------------------- | ------- | -------------------- |
| Azure Function Unit Tests | ~5 sec | 108 tests |
| Container App Unit Tests | ~3 sec | 60 tests |
| Flask E2E Tests | ~15 sec | 20 tests, headless |
| Static HTML E2E Tests | ~18 sec | 23 tests, headless |
| Vite Unit Tests | ~8 sec | 30 tests |
| Vite Integration Tests | ~10 sec | 8 tests, real API |
| Vite SWA Tests | ~12 sec | 8 tests, via SWA CLI |
| All Tests (Serial) | ~90 sec | Full test suite |

---

## Troubleshooting

### Tests Won't Run

**Playwright browser not found:**

```bash
uv run playwright install chromium
# or
bun run test:install
```

**API endpoint tests fail with "Cannot connect":**

```bash
# Make sure services are running
podman-compose up -d
podman ps # Check all containers are running

# Check specific port
curl http://localhost:8090/api/v1/health
```

**SWA CLI not starting:**

```bash
# Make sure port 4280-4282 are free
lsof -i :4280
lsof -i :4281
lsof -i :4282

# Kill process if needed
kill -9 <PID>
```

### Performance Issues

**Tests timeout:**

```bash
# Increase timeout in pytest
uv run pytest test_frontend.py --timeout=120

# Or reduce test scope
uv run pytest test_frontend.py -k test_page_load
```

**Slow API responses:**

```bash
# Check if containers are healthy
podman-compose logs api-fastapi-azure-function
podman-compose logs api-fastapi-container-app

# Restart services
podman-compose restart
```

---

## Best Practices

1. **Layer your testing**

- Unit tests (fast, frequent)
- Endpoint tests (verify API contract)
- E2E tests (verify user workflows)
- Integration tests (verify stacks work together)

1. **Use headless mode for CI**

- `bun run test` runs headless by default
- Use `bun run test:headed` for debugging

1. **Test one stack at a time**

- During development, use specific stack: `podman-compose up api-fastapi-azure-function frontend-python-flask`
- Faster than starting all services

1. **Run smoke tests frequently**

- `./test_endpoints.sh` (5 endpoints, ~5 sec)
- Quick verification before detailed tests

1. **Use make targets for consistency**

- `make test-stack4`
- `make test-bruno-stack5`
- Ensures correct configuration

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Test All Stacks

on: [push, pull_request]

jobs:
 test-backend:
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4
 - uses: astral-sh/setup-uv@v5

 - name: Test Azure Function API
 run: |
 cd api-fastapi-azure-function
 uv run pytest -v

 - name: Test Container App API
 run: |
 cd api-fastapi-container-app
 uv run pytest -v

 test-frontend:
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4
 - uses: astral-sh/setup-uv@v5

 - name: Install Playwright
 run: |
 cd frontend-python-flask
 uv run playwright install --with-deps chromium

 - name: Start services
 run: podman-compose up -d

 - name: Test all frontends
 run: |
 cd frontend-python-flask && uv run pytest test_frontend.py -v
 cd ../frontend-html-static && uv run pytest test_frontend.py -v

 test-integration:
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4
 - uses: astral-sh/setup-uv@v5

 - name: Start all services
 run: podman-compose up -d && sleep 10

 - name: Run integration tests
 run: make test-stack4 && make test-stack5
```

---

## References

- [TESTING.md](TESTING.md) - Original testing guide
- [SWA-CLI.md](SWA-CLI.md) - SWA CLI local emulator guide
- [SWA-FUNCTIONS-GUIDE.md](SWA-FUNCTIONS-GUIDE.md) - Functions architecture guide
- [pytest docs](https://docs.pytest.org/)
- [Playwright docs](https://playwright.dev/)
- [Bruno API Client](https://www.usebruno.com/)
