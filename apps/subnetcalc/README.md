# Subnet Calculator

A full-stack IPv4/IPv6 subnet calculator with multiple backend and frontend implementations demonstrating different deployment patterns.

> Looking for an overview of every hosting option (local compose, SWA, App Service Easy Auth, etc.) and how authentication works in each one? See [docs/HOSTING-MATRIX.md](docs/HOSTING-MATRIX.md) for the compatibility matrix that maps stacks to auth modes.
>
> Looking for the non-Kubernetes runtime topology itself, including Mermaid diagrams of the compose stacks and overlays? See [docs/COMPOSE-ARCHITECTURE.md](docs/COMPOSE-ARCHITECTURE.md).
>
> Looking for the default versus opt-in verification path for the local app and compose workflows? See [docs/TEST-RUNBOOK.md](docs/TEST-RUNBOOK.md).

## Quick Start

Compose workflows in this directory now read `OAUTH2_PROXY_COOKIE_SECRET` from
the repo root `.env`. On Apple Silicon, the repo-local `make` targets also set
`SUBNETCALC_LOCAL_PLATFORM=linux/arm64` so the local compose stack runs natively
instead of forcing `linux/amd64` emulation. Copy the template before using the
`make` or raw Compose commands below:

```bash
cp ../../.env.example ../../.env
```

### Run Baseline Compose

The default [`compose.yml`](compose.yml) path now starts the fast baseline
container-app family only. This is the recommended local loop when you want one
backend kept warm and to swap frontends quickly.

```bash
# Start the default happy path from this directory
make start-compose-happy

# Or bring up only the shared backend, then swap frontends
make start-compose-backend-container
make start-compose-frontend-vite
make start-compose-frontend-react
make start-compose-frontend-static
```

### Run Full Demo Topology

The main [`compose.yml`](compose.yml) defines many local stack variants. The
four baseline compose slices below are still the quickest way to understand the
core frontend/backend pairings before moving on to the OIDC, APIM, and mock
Easy Auth variants documented in
[docs/COMPOSE-ARCHITECTURE.md](docs/COMPOSE-ARCHITECTURE.md).

```bash
# Start the full local compose topology explicitly
make start-compose-full

# Or with Docker
docker compose --env-file ../../.env --profile function-family --profile oidc --profile mock-easyauth up -d

# Or from this directory, start the default stack-04
make up
```

**Stack 1 - Flask + Azure Function** (Traditional):

- Flask Frontend: <http://localhost:8000>
- Azure Function API: <http://localhost:8080/api/v1/docs>

**Stack 2 - Static HTML + Container App** (Client-Side):

- Static HTML Frontend: <http://localhost:8001>
- Container App API: <http://localhost:8090/api/v1/docs>

**Stack 3 - Flask + Container App** (Server-Side):

- Flask Frontend: <http://localhost:8002>
- Container App API: <http://localhost:8090/api/v1/docs>

**Stack 4 - TypeScript Vite + Container App** (Modern SPA):

- Vite SPA: <http://localhost:8003>
- Container App API: <http://localhost:8090/api/v1/docs>

### Run Individual Stacks

**Stack 1 - Flask + Azure Function:**

```bash
podman-compose up api-fastapi-azure-function frontend-python-flask
```

**Stack 2 - Static HTML + Container App:**

```bash
podman-compose up api-fastapi-container-app frontend-html-static
```

**Stack 3 - Flask + Container App:**

```bash
podman-compose up api-fastapi-container-app frontend-python-flask-container-app
```

**Stack 4 - TypeScript Vite + Container App:**

```bash
podman-compose up api-fastapi-container-app frontend-typescript-vite
```

### Run Individual Services

Each component can run standalone from its directory:

```bash
# Azure Function API only (port 8080)
cd api-fastapi-azure-function && podman-compose up

# Container App API only (port 8090)
cd api-fastapi-container-app && podman-compose up

# Flask Frontend only (port 8000)
cd frontend-python-flask && podman-compose up

# Static Frontend only (port 8001)
cd frontend-html-static && podman-compose up
```

### Stopping Services

```bash
podman-compose down
# or
docker compose down
```

## Vendored APIM Simulator

`apps/subnetcalc/apim-simulator/` is a vendored runtime subset of the
standalone `apim-simulator` repository. Treat the standalone repo as
authoritative.

Refresh the vendored copy from an explicit tag or commit SHA:

```bash
make vendor-apim-simulator \
  APIM_SIMULATOR_SOURCE_REPO=$HOME/Developer/personal/apim-simulator \
  APIM_SIMULATOR_SOURCE_REF=v0.4.0
```

The vendoring script records the resolved source commit and subset profile in
`apps/subnetcalc/apim-simulator.vendor.json`. The default `runtime`
profile keeps only the simulator package, contracts, lockfile/package metadata,
license, and runtime Dockerfile. It intentionally excludes upstream docs,
examples, tutorials, tests, UI assets, and local development scripts.

Do not hand-edit the vendored subtree and assume those changes will be
preserved; land source changes in the standalone repo first, then re-vendor
here.

## Azure Infrastructure Scripts

Azure deployment scripts and infrastructure docs live in the separate `azure-tui` repo:

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure
```

## Azure Static Web Apps (SWA CLI) Development

The project includes three additional stacks using the [Azure Static Web Apps CLI](https://azure.github.io/static-web-apps-cli/) for local development. These stacks demonstrate different authentication patterns suitable for Azure deployment.

**Prerequisites:**

```bash
bun add -g @azure/static-web-apps-cli
```

### SWA Stack Overview

All SWA stacks use:

- **Frontend**: TypeScript + Vite (same as podman-compose Stack 4)
- **Backend**: Azure Function API (Python + FastAPI)
- **Management**: SWA CLI handles both Vite dev server and Azure Function runtime

**Key Differences:**

| Stack | Port | Authentication | Backend Auth | Use Case |
|-------|------|----------------|--------------|----------|
| Stack 4 | 4280 | None | `AUTH_METHOD=none` | Public APIs, development |
| Stack 5 | 4281 | JWT (Application) | `AUTH_METHOD=jwt` | Custom user management |
| Stack 6 | 4282 | Entra ID (Platform) | `AUTH_METHOD=none` | Enterprise SSO |

### Run SWA Stacks

**Important**: Only run ONE stack at a time (port conflicts on 3000/7071).

**Stack 4 - No Authentication:**

```bash
cd ~/Developer/personal/subnetcalc
make start-swa-04
# Access at: http://localhost:4280
```

**Stack 5 - JWT Authentication:**

```bash
make start-swa-05
# Access at: http://localhost:4281
# Login with: username=demo@dev.test, password=demo-password
```

**Stack 6 - Entra ID Authentication:**

```bash
make start-swa-06
# Access at: http://localhost:4282
# Uses SWA platform auth (emulated locally)
```

### Stack Authentication Details

**Stack 4 (No Auth)**:

- Open access to all endpoints
- Suitable for public APIs
- Same as podman-compose Stack 4

**Stack 5 (JWT Auth)**:

- Application-level authentication
- Login endpoint: `POST /api/v1/auth/login`
- JWT token in `Authorization: Bearer <token>` header
- Backend validates JWT and checks Argon2 password hashes
- Test user: `demo@dev.test` / `demo-password`

**Stack 6 (Entra ID Auth)**:

- Platform-level authentication via Azure Static Web Apps
- Login endpoint: `/.auth/login/aad` (SWA managed)
- Backend receives authenticated user via SWA headers (`x-ms-client-principal`)
- Locally: SWA CLI emulates authentication (no real Azure AD)
- Production: Real Azure AD/Entra ID integration
- See [SWA-ENTRA-AUTH.md](SWA-ENTRA-AUTH.md) for detailed setup

### SWA Configuration Files

- `swa-cli.config.json` - SWA CLI configuration (ports, paths)
- `staticwebapp.config.json` - SWA authentication and routing rules (Stack 6)
- `Makefile` - Commands to start each stack with correct environment variables

### Clean Up Stuck Processes

If you close terminals without stopping the stack, processes may remain running:

```bash
make clean-ports
# Kills processes on ports: 3000, 7071, 4280-4282
```

### Local vs Production Differences

**Local Development (SWA CLI)**:

- Stack 6 authentication is **emulated** (no real Azure AD)
- Environment variables in `Makefile` and `local.settings.json`
- All stacks accessible on localhost

**Production (Azure Static Web Apps)**:

- Stack 6 requires Azure AD App Registration
- Environment variables in Azure App Settings
- `staticwebapp.config.json` enforces authentication
- JWT secrets and test users from Key Vault or App Settings

See [SWA-ENTRA-AUTH.md](SWA-ENTRA-AUTH.md) for production deployment guide.

## Project Structure

```text
subnetcalc/
├── api-fastapi-azure-function/  # Azure Function API (port 8080)
│   ├── compose.yml              # Standalone compose file
│   ├── test_endpoints.sh        # API endpoint tests
│   └── README.md
├── api-fastapi-container-app/   # Container App API (port 8090)
│   ├── compose.yml              # Standalone compose file
│   ├── test_endpoints.sh        # API endpoint tests with JWT
│   └── README.md
├── frontend-python-flask/       # Flask Frontend (port 8000)
│   ├── compose.yml              # Standalone compose file
│   ├── test_frontend.py         # Playwright e2e tests
│   └── README.md
├── frontend-html-static/        # Static HTML Frontend (port 8001)
│   ├── compose.yml              # Standalone compose file
│   ├── test_frontend.py         # Playwright e2e tests
│   ├── Dockerfile               # nginx-based image
│   ├── nginx.conf               # API proxy configuration
│   └── README.md
├── frontend-typescript-vite/    # TypeScript Vite Frontend (port 3000)
│   ├── compose.yml              # Standalone compose file
│   ├── tests/frontend.spec.ts   # Playwright e2e tests (15 tests)
│   ├── Dockerfile               # Multi-stage build (Node.js -> nginx)
│   ├── nginx.conf               # API proxy configuration
│   └── README.md
├── compose.yml                  # Main compose file (all 4 stacks)
├── TESTING.md                   # Complete testing guide
└── README.md                    # This file
```

## Service Details

| Service | Type | Port | Connects To | Description |
|---------|------|------|-------------|-------------|
| `api-fastapi-azure-function` | Backend | 8080 | - | FastAPI via Azure Functions AsgiMiddleware |
| `api-fastapi-container-app` | Backend | 8090 | - | FastAPI on Uvicorn (includes IPv6, no auth in compose) |
| `frontend-python-flask` | Frontend | 8000 | Azure Function API | Server-side Flask (Stack 1) |
| `frontend-html-static` | Frontend | 8001 | Container App API | Static HTML with nginx proxy (Stack 2) |
| `frontend-python-flask-container-app` | Frontend | 8002 | Container App API | Server-side Flask (Stack 3) |
| `frontend-typescript-vite` | Frontend | 3000 | Container App API | TypeScript + Vite SPA (Stack 4) |

## Individual Projects

See individual project READMEs for local development and detailed information:

- [Azure Function API](api-fastapi-azure-function/README.md) - Traditional Azure Functions deployment
- [Container App API](api-fastapi-container-app/README.md) - Modern container-native deployment
- [Flask Frontend](frontend-python-flask/README.md) - Server-side rendering (no CORS needed)
- [Static Frontend](frontend-html-static/README.md) - Pure client-side HTML/JS with nginx proxy
- [TypeScript Vite Frontend](frontend-typescript-vite/README.md) - Modern SPA with TypeScript, Vite, and nginx proxy

## Architecture

- **Backend API**: FastAPI-based Azure Function App

  - IPv4/IPv6 address validation and CIDR notation support
  - RFC1918 private address detection
  - RFC6598 shared address space detection
  - Cloudflare IP range detection
  - Cloud provider-specific subnet calculations (Azure, AWS, OCI, Standard)
  - Interactive Swagger UI documentation at `/api/v1/docs`
  - Python 3.11

- **Frontends**:

  **Flask (Server-Side Rendering)** - Stacks 1 & 3:
  - Server calls API, renders HTML
  - Progressive enhancement (works without JavaScript)
  - CORS not required (server-to-server)
  - Python 3.11, Pico CSS

  **Static HTML (Client-Side)** - Stack 2:
  - Pure HTML/JS/CSS (no server runtime)
  - nginx reverse proxy forwards `/api/*` to backend
  - Browser makes relative API calls
  - Architecture: `Browser → nginx (port 8001) → Backend API (container network)`

  **TypeScript + Vite (Modern SPA)** - Stack 4:
  - TypeScript (ES2022/ES2023), Vite 6.0
  - Multi-stage Docker build (Node.js build → nginx serve)
  - nginx reverse proxy forwards `/api/*` to backend
  - Type-safe API client with full interfaces
  - Architecture: `Browser → nginx (port 3000) → Backend API (container network)`
  - Comprehensive Playwright tests (15 tests)

## Container Details

The main `compose.yml` runs all six services (2 backends + 4 frontends):

- **Platform**: defaults to `linux/amd64` for deployment compatibility, but the local `make` workflow switches to native `linux/arm64` on Apple Silicon
- **Health checks**: Configured for both API services
- **Networking**: Services communicate via Docker/Podman network
- **Port Mappings**:
  - Azure Function API: 8080 → 80 (internal)
  - Container App API: 8090 → 8000 (internal)
  - Flask Frontend (Stack 1): 8000
  - Static Frontend (Stack 2): 8001
  - Flask Frontend (Stack 3): 8002
  - TypeScript Vite Frontend (Stack 4): 3000

**Four Complete Stacks**:

1. **Flask + Azure Function** (8000/8080) - Traditional server-side rendering
2. **Static HTML + Container App** (8001/8090) - Client-side with nginx API proxy
3. **Flask + Container App** (8002/8090) - Server-side rendering with modern API
4. **TypeScript Vite + Container App** (3000/8090) - Modern SPA with nginx API proxy

### nginx Reverse Proxy Pattern (Stacks 2 & 4)

Both client-side frontends (Static HTML and TypeScript Vite) use nginx as a reverse proxy to avoid CORS issues:

**Configuration** (`nginx.conf`):

```nginx
location /api/ {
    proxy_pass http://api-fastapi-container-app:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

**How it works**:

1. Browser requests `/api/v1/health` from frontend container
2. nginx intercepts and proxies to backend container via Docker network
3. Backend responds to nginx, nginx returns to browser
4. **Benefits**: No CORS configuration needed, same-origin from browser perspective

Each subdirectory contains a standalone `compose.yml` for individual service development.

## API Testing and Debugging

This section shows how to inspect HTTP traffic to understand what's actually happening in each stack's authentication flow.

### Tools

**curl** - Universal HTTP client (installed on most systems):

```bash
curl --version
```

**xh** - Modern curl alternative with simpler syntax:

```bash
brew install xh
# or
cargo install xh
```

**Bruno** - Open-source API client (GUI alternative to Postman):

```bash
brew install --cask bruno
# or download from https://www.usebruno.com
```

### Stack 4 (SWA - No Auth) Testing

**Check health endpoint:**

```bash
# curl (verbose to see headers)
curl -v http://localhost:4280/api/v1/health

# xh (cleaner output)
xh GET localhost:4280/api/v1/health

# Expected response
{
  "status": "healthy",
  "service": "FastAPI Subnet Calculator",
  "version": "1.0.0"
}
```

**Calculate subnet:**

```bash
# curl
curl -X POST http://localhost:4280/api/v1/calculate \
  -H "Content-Type: application/json" \
  -d '{"cidr": "10.0.0.0/24", "provider": "azure"}'

# xh (simpler syntax)
xh POST localhost:4280/api/v1/calculate \
  cidr=10.0.0.0/24 \
  provider=azure
```

**What to observe:**

- No `Authorization` header needed
- No authentication cookies
- Direct access to all endpoints

### Stack 5 (SWA - JWT Auth) Testing

**Step 1: Login to get JWT token:**

```bash
# curl
curl -X POST http://localhost:4281/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"demo@dev.test","password":"demo-password"}' \
  | jq -r '.access_token'

# xh
xh POST localhost:4281/api/v1/auth/login \
  username=demo@dev.test \
  password=demo-password

# Save token to variable
TOKEN=$(curl -s -X POST http://localhost:4281/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"demo@dev.test","password":"demo-password"}' \
  | jq -r '.access_token')

echo $TOKEN
```

**Step 2: Use token for API calls:**

```bash
# curl - check health (protected endpoint)
curl -v http://localhost:4281/api/v1/health \
  -H "Authorization: Bearer $TOKEN"

# curl - calculate subnet
curl -X POST http://localhost:4281/api/v1/calculate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"cidr":"10.0.0.0/24"}'

# xh - cleaner syntax
xh POST localhost:4281/api/v1/calculate \
  "Authorization:Bearer $TOKEN" \
  cidr=10.0.0.0/24
```

**Test without token (should fail):**

```bash
# Should return 401 Unauthorized
curl -v http://localhost:4281/api/v1/health

# Response: {"detail": "Not authenticated"}
```

**What to observe:**

- Login returns JWT token in response body
- Token must be sent in `Authorization: Bearer <token>` header
- Backend validates JWT signature and expiration
- Tokens expire after 1 hour (configurable)

**Inspect JWT token:**

```bash
# Decode JWT (header.payload.signature)
echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq

# Or use jwt.io website to decode and inspect claims
```

### Stack 6 (SWA - Entra ID Auth) Testing

**Check authentication status:**

```bash
# Try to access protected endpoint (will fail)
curl -v http://localhost:4282/api/v1/health

# Check user info (SWA endpoint)
curl -v http://localhost:4282/.auth/me

# Response when not authenticated
{
  "clientPrincipal": null
}
```

**Login via browser (SWA CLI emulation):**

```bash
# Open browser to login URL
open http://localhost:4282/.auth/login/aad

# Or on Linux
xdg-open http://localhost:4282/.auth/login/aad
```

**After login, SWA sets authentication cookies:**

```bash
# Save cookies to file
curl -c cookies.txt -L http://localhost:4282/.auth/login/aad

# Use cookies for API calls
curl -b cookies.txt http://localhost:4282/api/v1/health

# Check authenticated user info
curl -b cookies.txt http://localhost:4282/.auth/me

# Response when authenticated
{
  "clientPrincipal": {
    "userId": "demo@dev.test",
    "userRoles": ["authenticated"],
    "claims": [...]
  }
}
```

**What to observe:**

- No `Authorization` header needed (SWA uses cookies)
- SWA sets `StaticWebAppsAuthCookie` cookie after login
- SWA injects `x-ms-client-principal*` headers to backend
- Backend has `AUTH_METHOD=none` (SWA handles authentication)
- In production: Real Entra ID, locally: SWA CLI emulation

**Inspect SWA headers sent to backend:**

```bash
# Backend receives these headers (visible in Azure Function logs)
x-ms-client-principal: <base64-encoded user info>
x-ms-client-principal-id: <user-id>
x-ms-client-principal-name: <user-name>
```

### Bruno Collections

For GUI-based testing, create Bruno collections:

**Collection structure:**

```text
subnetcalc/
├── Stack 4 - No Auth/
│   ├── Health Check.bru
│   ├── Calculate Subnet.bru
│   └── List Providers.bru
├── Stack 5 - JWT Auth/
│   ├── Login.bru              # Saves token to environment
│   ├── Health Check.bru       # Uses {{token}} variable
│   └── Calculate Subnet.bru
└── Stack 6 - Entra ID/
    ├── Login (Browser).bru    # Open /.auth/login/aad
    ├── User Info.bru          # Check /.auth/me
    └── Calculate Subnet.bru   # Uses cookies
```

**Stack 5 JWT - Login request (Login.bru):**

```bruno
meta {
  name: Login
  type: http
  seq: 1
}

post {
  url: {{baseUrl}}/api/v1/auth/login
  body: json
}

body:json {
  {
    "username": "demo@dev.test",
    "password": "demo-password"
  }
}

script:post-response {
  const data = res.getBody();
  bru.setEnvVar("token", data.access_token);
}
```

**Stack 5 JWT - Protected request (Health Check.bru):**

```bruno
meta {
  name: Health Check
  type: http
  seq: 2
}

get {
  url: {{baseUrl}}/api/v1/health
  headers: {
    Authorization: Bearer {{token}}
  }
}
```

**Bruno environments:**

```json
{
  "Stack 4 (No Auth)": {
    "baseUrl": "http://localhost:4280"
  },
  "Stack 5 (JWT)": {
    "baseUrl": "http://localhost:4281",
    "token": ""
  },
  "Stack 6 (Entra ID)": {
    "baseUrl": "http://localhost:4282"
  }
}
```

### Debugging Tips

**View all HTTP headers (curl):**

```bash
curl -v http://localhost:4280/api/v1/health 2>&1 | grep -E '^(<|>)'
```

**Follow redirects and show cookies:**

```bash
curl -L -c cookies.txt -b cookies.txt -v http://localhost:4282/.auth/login/aad
```

**Test JWT expiration:**

```bash
# Wait 1 hour or modify JWT_EXPIRATION_MINUTES in local.settings.json
# Then try using old token (should fail with 401)
curl -v http://localhost:4281/api/v1/health \
  -H "Authorization: Bearer $OLD_TOKEN"
```

**Compare SWA proxy behavior:**

```bash
# Direct Azure Function call (bypasses SWA)
curl http://localhost:7071/api/v1/health

# Via SWA proxy
curl http://localhost:4280/api/v1/health

# Notice: SWA adds headers, handles CORS, manages authentication
```

**Check Azure Function logs:**

```bash
# While Stack 5 is running, look for authentication logs
# Terminal shows: [Authentication] Validating JWT token...
```

## Troubleshooting

### Check container logs

```bash
# All services
podman-compose logs -f
# or
docker compose logs -f

# Individual services
podman-compose logs api-fastapi-azure-function -f
podman-compose logs api-fastapi-container-app -f
podman-compose logs frontend-python-flask -f
podman-compose logs frontend-html-static -f
podman-compose logs frontend-python-flask-container-app -f
```

### Rebuild containers

```bash
podman-compose up --build
# or
docker compose --env-file ../../.env up --build
```

### Check service health

```bash
# Azure Function API
curl http://localhost:8080/api/v1/health

# Container App API (no auth in compose)
curl http://localhost:8090/api/v1/health

# Flask Frontend (Stack 1 - connects to Azure Function)
curl http://localhost:8000

# Static Frontend (Stack 2 - connects to Container App)
curl http://localhost:8001

# Flask Frontend (Stack 3 - connects to Container App)
curl http://localhost:8002

# TypeScript Vite SPA (Stack 4 - connects to Container App)
curl http://localhost:3000
```
