# Subnet Calculator - TypeScript + Vite Frontend

Modern single-page application (SPA) frontend for the subnet calculator, built with TypeScript, Vite, and Pico CSS.

## Architecture

- **Framework**: Vanilla TypeScript with Vite build tooling
- **UI Library**: Pico CSS v2 for modern, semantic styling
- **Testing**: Playwright for end-to-end browser testing
- **Linting/Formatting**: Biome for fast, consistent code quality
- **Container**: Multi-stage Docker build with nginx

## Features

- Modern TypeScript with strict type checking
- Fast development with Vite HMR (Hot Module Replacement)
- Responsive design with Pico CSS theming
- Comprehensive E2E tests with Playwright
- Production-ready nginx serving
- Zero vulnerabilities in container image (Alpine Linux base)

## Quick Start

### Local Development

```bash
# Install dependencies
bun install

# Start development server with HMR
bun run dev
# Access at http://localhost:5173

# Run type checking
bun run type-check

# Run linting
bun run lint

# Run tests (headless)
bun run test

# Run tests (headed mode)
bun run test:headed

# Run tests (interactive UI)
bun run test:ui
```

### Docker/Podman Build

```bash
# Build the container image
podman build -t subnet-calculator-frontend-typescript-vite:latest .

# Run the container
podman run -d -p 3000:8080 subnet-calculator-frontend-typescript-vite:latest

# Access at http://localhost:3000
```

### With Docker Compose

From the `subnet-calculator/` directory:

```bash
# Stack 4: TypeScript frontend + Container App API (no auth)
podman-compose up api-fastapi-container-app frontend-typescript-vite
# Access frontend at http://localhost:3000
# Access API docs at http://localhost:8090/api/v1/docs

# Stack 5: TypeScript frontend + Azure Function API (JWT auth)
podman-compose up api-fastapi-azure-function frontend-typescript-vite-jwt
# Access frontend at http://localhost:3001
# Access API docs at http://localhost:8080/api/v1/docs
# JWT authentication handled automatically (demo/password123)
```

## JWT Authentication

The TypeScript frontend supports optional JWT authentication to connect to backends that require it (like the Azure Function API).

### Configuration

For local Vite development, authentication is controlled via `VITE_*` variables:

- `VITE_AUTH_ENABLED` - Set to `"true"` to enable JWT auth (default: `"false"`)
- `VITE_JWT_USERNAME` - JWT username (default: empty)
- `VITE_JWT_PASSWORD` - JWT password (default: empty)
- `VITE_API_URL` - API base URL (default: `http://localhost:8090`)
- `VITE_SHOW_NETWORK_PATH` - Set to `"true"` to show the network path and diagnostics panels
- `VITE_FRONTEND_STATUS_LABEL` - Optional label for the browser-facing frontend origin in the health banner
- `VITE_API_INGRESS_STATUS_LABEL` - Optional label for the ingress URL the frontend calls
- `VITE_BACKEND_PATH_STATUS_LABEL` - Optional label for a topology/explanation line in the health banner
- `VITE_BACKEND_PATH_STATUS_DETAIL` - Optional topology/explanation string shown under the ingress URL
- `VITE_NETWORK_HOPS` - Optional JSON array describing the user-facing request path
- `VITE_NETWORK_DIAGNOSTICS_LABEL` - Optional label for the primary diagnostics panel
- `VITE_SECONDARY_NETWORK_DIAGNOSTICS_LABEL` - Optional label for a second diagnostics panel
- `VITE_SECONDARY_NETWORK_DIAGNOSTICS_PATH` - Optional path for that second diagnostics API

For containers, the frontend now reads runtime config from `/runtime-config.js` generated at startup. Use runtime env vars such as `API_BASE_URL`, `AUTH_METHOD`, `JWT_USERNAME`, and `JWT_PASSWORD` instead of Docker build args.

### Local Development with JWT

```bash
# Development with JWT authentication
VITE_AUTH_ENABLED=true \
VITE_JWT_USERNAME=demo \
VITE_JWT_PASSWORD=password123 \
VITE_API_URL=http://localhost:8080 \
bun run dev

# Access at http://localhost:5173
# Connects to Azure Function API with automatic JWT authentication
```

### Container Runtime with JWT

```bash
# Build a generic image
podman build -t subnet-calculator-frontend-typescript-vite-jwt:latest .

# Supply auth and API details at runtime
podman run --rm -p 3001:8080 \
  -e AUTH_METHOD=jwt \
  -e JWT_USERNAME=demo \
  -e JWT_PASSWORD=password123 \
  -e API_BASE_URL=http://api-fastapi-azure-function:8080 \
  subnet-calculator-frontend-typescript-vite-jwt:latest
```

## Optional Network Diagnostics Panels

The Vite frontend can show one or two network diagnostics panels alongside the subnet lookup results.

The primary panel uses the normal backend API endpoint:

- `GET ${VITE_API_URL}/api/v1/network/diagnostics`
- if `VITE_API_URL` is empty, that becomes `/api/v1/network/diagnostics`

The optional secondary panel is intended for cases where you want a second viewpoint, for example:

- frontend edge vs backend API
- ingress site vs service site
- local proxy vs remote application

### Diagnostics Environment Variables

- `VITE_SHOW_NETWORK_PATH=true`
  Enables the network path card and diagnostics panels.
- `VITE_FRONTEND_STATUS_LABEL`
  Overrides the frontend-origin label in the API health banner.
- `VITE_API_INGRESS_STATUS_LABEL`
  Overrides the ingress label in the API health banner.
- `VITE_BACKEND_PATH_STATUS_LABEL`
  Title for the optional backend-path explanation line.
- `VITE_BACKEND_PATH_STATUS_DETAIL`
  Optional topology string that explains what sits behind the ingress URL.
- `VITE_NETWORK_HOPS`
  JSON array of `{ label, detail, role? }` objects shown as the request path legend.
- `VITE_NETWORK_DIAGNOSTICS_LABEL`
  Overrides the primary panel title. Default: `Live Diagnostics`.
- `VITE_SECONDARY_NETWORK_DIAGNOSTICS_LABEL`
  Title for the optional second panel. If empty, no second panel is shown.
- `VITE_SECONDARY_NETWORK_DIAGNOSTICS_PATH`
  Relative or absolute URL fetched for the second panel. If empty, no second panel is fetched.

### Expected Diagnostics Response

Both diagnostics panels expect the same JSON shape:

```json
{
  "viewpoint": "cloud1",
  "target": "api1.vanity.test:443",
  "generated_at": "2026-03-11T15:29:03.595020+00:00",
  "dns": {
    "resolver": "10.10.1.10",
    "answers": ["172.16.11.2"],
    "command": "dig +time=2 +tries=1 api1.vanity.test A @10.10.1.10",
    "exit_code": 0,
    "raw_output": "..."
  },
  "traceroute": {
    "command": "traceroute -n -T -p 443 -q 1 -w 1 api1.vanity.test",
    "exit_code": 0,
    "hops": ["172.16.11.2"],
    "hop_count": 1,
    "raw_output": "..."
  },
  "tunnel": {
    "interface": "wg0",
    "local_tunnel_ip": "192.168.1.1",
    "peer_tunnel_ips": ["192.168.1.2", "192.168.1.3"],
    "peer_endpoint_ips": ["192.168.104.5", "192.168.104.6"],
    "peers": [
      {
        "public_key": "base64...",
        "endpoint_ip": "192.168.104.5",
        "endpoint_port": 51820,
        "allowed_ips": ["192.168.1.2/32", "172.16.11.0/24"],
        "tunnel_peer_ip": "192.168.1.2",
        "latest_handshake_unix": 1741706941
      }
    ]
  }
}
```

### Example: dual-view diagnostics

```bash
VITE_SHOW_NETWORK_PATH=true \
VITE_FRONTEND_STATUS_LABEL='Frontend origin' \
VITE_API_INGRESS_STATUS_LABEL='Cloud1 ingress' \
VITE_BACKEND_PATH_STATUS_LABEL='Backend path' \
VITE_BACKEND_PATH_STATUS_DETAIL='cloud1 nginx -> WireGuard SD-WAN -> cloud2 nginx -> cloud2 FastAPI' \
VITE_NETWORK_DIAGNOSTICS_LABEL='Backend Diagnostics' \
VITE_SECONDARY_NETWORK_DIAGNOSTICS_LABEL='Frontend Diagnostics (cloud1 viewpoint)' \
VITE_SECONDARY_NETWORK_DIAGNOSTICS_PATH='/cloud1-diagnostics/network/diagnostics' \
VITE_NETWORK_HOPS='[
  {"label":"Browser","detail":"localhost:58081"},
  {"label":"cloud1 nginx","detail":"frontend ingress"},
  {"label":"cloud2 FastAPI","detail":"remote service"}
]' \
bun run build
```

This keeps the feature reusable in non-SD-WAN deployments: the frontend only needs a primary diagnostics endpoint, and optionally a second endpoint that returns the same response shape from a different network viewpoint.

The optional status-banner variables keep the host-facing ingress URL separate from the actual backend path. That is useful when the frontend talks to a local reverse proxy which then crosses some other transport layer before reaching the real API.

### How JWT Works

When `AUTH_METHOD=jwt` in runtime config, or `VITE_AUTH_ENABLED=true` during local Vite development:

1. **Automatic Login**: Frontend logs in on first API call using configured credentials
2. **Token Caching**: JWT token cached for 25 minutes (refreshes before 30-min expiration)
3. **Auth Headers**: All API requests include `Authorization: Bearer <token>` header
4. **Transparent**: No UI changes - authentication happens automatically

When `AUTH_METHOD=none` in runtime config, or `VITE_AUTH_ENABLED=false` (default) during local Vite development:

- No authentication
- Works with public APIs (like Container App backend)
- No login or auth headers sent

### Testing with JWT

```bash
# Run tests with JWT mocking enabled
AUTH_METHOD=jwt \
JWT_USERNAME=demo \
JWT_PASSWORD=password123 \
bun run test

# All 30 tests pass with or without JWT enabled
```

## Development Workflow

### 1. Code

Edit files in `src/`:

- `src/main.ts` - Application entry point and logic
- `src/style.css` - Custom styles (extends Pico CSS)
- `index.html` - HTML template

### 2. Type Check

```bash
bun run type-check
```

### 3. Lint and Format

```bash
# Check for issues
bun run lint

# Auto-fix issues
bun run lint:fix

# Format code
bun run format

# Run all checks
bun run check
```

### 4. Test

#### Unit Tests (Mocked API)

```bash
# Run all Playwright tests (mocked API responses)
bun run test

# Run tests in headed mode (see browser)
bun run test:headed

# Run tests in UI mode (interactive)
bun run test:ui
```

Tests are located in `tests/frontend.spec.ts` and cover:

- Page load and rendering
- IPv4 subnet calculations
- IPv6 subnet calculations
- Form validation
- Error handling

#### Integration Tests (Real Containers)

Test against real running containerized backends - NO MOCKING:

```bash
# Prerequisites: Start containers first
cd ..
podman-compose up api-fastapi-azure-function frontend-typescript-vite-jwt  # Stack 5 (JWT)
# OR
podman-compose up api-fastapi-container-app frontend-typescript-vite        # Stack 4 (no auth)

# Run integration tests against Stack 5 (JWT auth)
bun run test:integration

# Run integration tests against Stack 4 (no auth)
bun run test:integration:stack4

# Run integration tests with browser visible
bun run test:integration:headed
```

Integration tests are located in `tests/integration.spec.ts` and validate:

- Real API connectivity and health checks
- JWT authentication flow (Stack 5)
- JWT token caching and reuse
- Authorization headers in requests
- Real IPv4/IPv6 validation via API
- Real subnet calculations (Azure/AWS/OCI modes)
- Real RFC1918 private address detection
- Real Cloudflare IP range detection

### 5. Build

```bash
# Build for production
bun run build

# Preview production build
bun run preview
```

Built files are output to `dist/`.

## Project Structure

```text
frontend-typescript-vite/
├── src/
│   ├── main.ts           # Application logic
│   ├── style.css         # Custom styles
│   └── vite-env.d.ts     # Vite type definitions
├── tests/
│   └── frontend.spec.ts  # Playwright E2E tests
├── index.html            # HTML template
├── nginx.conf            # nginx configuration for container
├── Dockerfile            # Multi-stage production build
├── package.json          # Dependencies and scripts
├── bun.lock     # Locked dependencies
├── tsconfig.json         # TypeScript configuration
├── playwright.config.ts  # Playwright test configuration
├── biome.json           # Biome linter/formatter configuration
└── vite.config.ts       # Vite build configuration
```

## API Integration

The frontend communicates with the Container App API backend:

- **Development**: Configured in `vite.config.ts` to proxy `/api` to `http://localhost:8090`
- **Production**: nginx proxies `/api` requests to the backend service
- **Container**: Uses `api-fastapi-container-app` service via Docker network

API endpoints used:

- `GET /api/v1/health` - Health check
- `POST /api/v1/subnets/calculate` - Calculate subnet details

## Testing

### Playwright Tests

Located in `tests/frontend.spec.ts`:

```typescript
test('calculates IPv4 subnet correctly', async ({ page }) => {
  await page.goto('/');
  await page.fill('input[name="network"]', '192.168.1.0/24');
  await page.selectOption('select[name="provider"]', 'standard');
  await page.click('button[type="submit"]');
  await expect(page.locator('.result')).toContainText('Network: 192.168.1.0/24');
});
```

### Running Tests

```bash
# Headless (CI mode)
bun run test

# Headed (see browser)
bun run test:headed

# UI mode (interactive debugging)
bun run test:ui
```

### Test Configuration

Configured in `playwright.config.ts`:

- Base URL: `http://localhost:3000`
- Browsers: Chromium, Firefox, WebKit
- Screenshots on failure
- Trace on first retry

## Code Quality

### Biome

Fast, modern linter and formatter replacing ESLint + Prettier:

```bash
# Check for issues
bun run lint

# Auto-fix issues
bun run lint:fix

# Format code
bun run format
```

Configuration in `biome.json`:

- Strict linting rules
- Consistent formatting
- Import sorting
- No unused variables

### TypeScript

Strict type checking enabled in `tsconfig.json`:

```bash
bun run type-check
```

## Container Details

### Multi-stage Build

1. **Builder stage**: Node.js 22 Alpine, installs deps and builds app
2. **Production stage**: Docker Hardened nginx (`dhi.io/nginx`), serves static files

### Security

- Based on `dhi.io/nginx:1.29.5-debian13`
- **0 HIGH/CRITICAL vulnerabilities** (verified with Trivy)
- Runs nginx as non-root user (default nginx behavior)
- Minimal attack surface

### nginx Configuration

Located in `nginx.conf`:

- Serves static files from `/usr/share/nginx/html`
- SPA routing: Falls back to `index.html` for all routes
- Gzip compression enabled
- API proxy to backend (in compose stack)

## Environment Variables

None required - API endpoint is configured at build time in `vite.config.ts` for development and `nginx.conf` for production.

## Stack 4 - TypeScript Vite + Container App

This frontend is part of Stack 4, the most modern architecture:

**Stack 4 Components:**

- **Frontend**: TypeScript + Vite SPA (this project)
- **Backend**: Container App API (`api-fastapi-container-app`)
- **Authentication**: None (local development)

**Access Points:**

- Frontend: <http://localhost:3000>
- API Docs: <http://localhost:8090/api/v1/docs>

**Why Stack 4?**

- Modern SPA architecture with client-side routing
- TypeScript for type safety
- Fast Vite build tooling
- Comprehensive E2E testing with Playwright
- Production-ready nginx serving
- Clean separation of frontend/backend concerns

## Comparison with Other Frontends

| Feature | TypeScript Vite | Flask | Static HTML |
|---------|----------------|-------|-------------|
| Language | TypeScript | Python | JavaScript |
| Architecture | SPA | Server-rendered | Client-side |
| Build Tool | Vite | None | None |
| Type Safety | Strong | None | None |
| Testing | Playwright E2E | pytest unit | None |
| HMR | Yes | No | No |
| Bundle Size | ~50KB | N/A | ~5KB |
| Learning Curve | Medium | Low | Low |

## Contributing

1. Make changes to `src/` files
2. Run `bun run check` to verify types and linting
3. Run `bun run test` to verify tests pass
4. Build container: `podman build -t subnet-calculator-frontend-typescript-vite:latest .`
5. Run security scan: `make -C apps trivy-scan`

## Troubleshooting

### Port Already in Use

If port 3000 is in use:

```bash
# Find process using port 3000
lsof -i :3000

# Kill process
kill -9 <PID>
```

### Playwright Browsers Not Installed

```bash
bun x playwright install
```

### Type Errors

```bash
# Clean and reinstall
rm -rf node_modules bun.lock
bun install
```

### Container Build Fails

Ensure you have `bun.lock`:

```bash
bun install  # Generates bun.lock
```

## License

Part of the subnet-calculator repository.
