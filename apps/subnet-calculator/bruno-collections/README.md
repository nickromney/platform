# Bruno API Test Collections

This directory contains Bruno API test collections for the Subnet Calculator, organized by three testing contexts: **direct**, **compose**, and **swa**.

## Three Testing Contexts

### Direct (7000s)

Individual services launched with native tools (`func start`, `uvicorn`, `npm run dev`). Each service runs independently.

### Compose (8000s)

Complete application stacks via `podman-compose`. Each stack includes frontend + backend combination.

### SWA (4000s)

Azure Static Web Apps CLI emulation for production-like testing with different authentication scenarios.

## Collection Structure

```text
bruno-collections/
├── bruno.json                           # Collection configuration
├── environments/
│   ├── local.bru                        # Local development URLs (7000s, 8000s, 4000s)
│   └── production.bru                   # Production URLs (Azure deployments)
│
├── DIRECT LAUNCHES (Port 7000s)
├── direct-azure-function/               # Azure Function API (port 7071, JWT auth)
│   ├── Health Check.bru
│   ├── Login.bru
│   └── Subnet Info.bru
├── direct-container-app/                # Container App API (port 7080, no auth)
│   ├── Health Check.bru
│   ├── Validate IP.bru
│   └── Subnet Info.bru
├── direct-flask/                        # Flask frontend (port 7000)
│   └── Page Load.bru
├── direct-vite/                         # TypeScript Vite frontend (port 7010)
│   └── Page Load.bru
│
├── PODMAN-COMPOSE STACKS (Ports 8000-8003)
├── compose-01/                          # Flask + Azure Function (ports 8000, 8080)
│   ├── Frontend Health.bru
│   ├── API Health.bru
│   └── Subnet Info.bru
├── compose-02/                          # Static HTML + Container App (ports 8001, 8090)
│   ├── Frontend Health.bru
│   ├── API Health.bru
│   └── Subnet Info.bru
├── compose-03/                          # Flask + Container App (ports 8002, 8090)
│   ├── Frontend Health.bru
│   ├── API Health.bru
│   └── Subnet Info.bru
├── compose-04/                          # TypeScript Vite + Container App (ports 8003, 8090)
│   ├── Frontend Health.bru
│   ├── API Health.bru
│   └── Subnet Info.bru
│
└── SWA CLI STACKS (Ports 4000s)
    ├── swa-04/                          # No Auth (port 4280)
    │   ├── Health Check.bru
    │   ├── Validate IP.bru
    │   └── Subnet Info.bru
    ├── swa-05/                          # JWT Auth (port 4281)
    │   ├── Login.bru
    │   ├── Health Check.bru
    │   └── Subnet Info.bru
    └── swa-06/                          # Entra ID Auth (port 4282)
        ├── Check Auth Status.bru
        ├── Health Check.bru
        └── Subnet Info.bru
```

## Prerequisites

```bash
# No installation needed - Makefile uses npx
# Or install globally:
npm install -g @usebruno/cli
```

## Environments

Two environments available:

- **local** - Development testing (7000s, 8000s, 4000s)
- **production** - Production deployments (Azure URLs)

To use production environment:

1. Edit `environments/production.bru`
2. Update URLs to your deployed services
3. Select "production" in Bruno GUI

## Running Tests

### Via Makefile (Recommended)

```bash
# Terminal 1: Start the stack
make start-direct-azure-function        # Or any other start command

# Terminal 2: Run corresponding tests
make test-bruno-direct                  # Test all direct services
make test-bruno-compose                 # Test all compose stacks
make test-bruno-swa                     # Test all SWA stacks
```

### Via Bruno CLI

```bash
cd bruno-collections

# Run all tests
npx @usebruno/cli@latest run --env local -r

# Run specific collection
npx @usebruno/cli@latest run direct-azure-function --env local
npx @usebruno/cli@latest run compose-01 --env local
npx @usebruno/cli@latest run swa-04 --env local

# Output to JSON
npx @usebruno/cli@latest run --env local --output results.json --format json -r
```

### Via Bruno GUI

```bash
# Install Bruno
brew install --cask bruno

# Open collection
# File > Open Collection > Select bruno-collections directory
```

## Environment Variables

The `environments/local.bru` file defines:

**Direct Launches (7000s):**

- `directAzureFunctionUrl`: <http://localhost:7071>
- `directContainerAppUrl`: <http://localhost:7080>
- `directFlaskUrl`: <http://localhost:7000>
- `directViteUrl`: <http://localhost:7010>

**Podman-Compose Stacks (8000s):**

- `compose01FrontendUrl`, `compose01ApiUrl`: Ports 8000, 8080
- `compose02FrontendUrl`, `compose02ApiUrl`: Ports 8001, 8090
- `compose03FrontendUrl`, `compose03ApiUrl`: Ports 8002, 8090
- `compose04FrontendUrl`, `compose04ApiUrl`: Ports 8003, 8090

**SWA CLI Stacks (4000s):**

- `swa04BaseUrl`: <http://localhost:4280> (No Auth)
- `swa05BaseUrl`: <http://localhost:4281> (JWT Auth)
- `swa06BaseUrl`: <http://localhost:4282> (Entra ID Auth)
- `token`: Auto-populated by Login requests

## Quick Start Examples

### Test Direct Services

```bash
# Terminal 1
make start-direct-azure-function

# Terminal 2
make test-bruno-direct
```

### Test Compose Stack 01

```bash
# Terminal 1
make start-compose-01

# Terminal 2
cd bruno-collections
npx @usebruno/cli@latest run compose-01 --env local
```

### Test SWA 04

```bash
# Terminal 1
make start-swa-04

# Terminal 2
cd bruno-collections
npx @usebruno/cli@latest run swa-04 --env local
```

## Port Allocation

All three contexts use **zero-conflict** port ranges:

| Context | Ports | Services |
|---------|-------|----------|
| Direct | 7000-7010 | Individual services |
| Compose | 8000-8090 | Complete stacks |
| SWA | 4280-4282 | SWA CLI emulation |

You can run services from all contexts simultaneously!

## How It Works

### Direct Collections

Test individual services in isolation:

- **direct-azure-function**: JWT auth required
- **direct-container-app**: No auth, validates IP addresses
- **direct-flask**, **direct-vite**: Frontend page loads

### Compose Collections

Test complete application stacks:

- **compose-01**: Flask frontend + Azure Function backend
- **compose-02**: Static HTML + Container App backend
- **compose-03**: Flask + Container App (no auth)
- **compose-04**: TypeScript Vite + Container App (no auth)

### SWA Collections

Test Azure Static Web Apps scenarios:

- **swa-04**: No authentication
- **swa-05**: JWT application-managed auth
- **swa-06**: Entra ID platform-managed auth (cookie-based)

## Troubleshooting

### Error: "ECONNREFUSED"

**Solution**: Ensure the corresponding service/stack is running:

```bash
make start-direct-azure-function    # For direct-azure-function tests
make start-compose-01               # For compose-01 tests
make start-swa-04                   # For swa-04 tests
```

### Error: "401 Unauthorized" on direct-azure-function

**Solution**: Login first to get JWT token:

1. Bruno will run "Login.bru" first
2. Token is automatically saved to environment
3. Subsequent requests use the token

### Error: "Invalid X-Forwarded-Host" on compose stacks

**Solution**: This is expected when testing via curl. Bruno tests are properly configured.

## Testing All Stacks

To comprehensively test everything:

```bash
# Terminal 1: Start all direct services
make start-direct-azure-function &
make start-direct-container-app &
make start-direct-flask &
make start-direct-vite &

# Terminal 2: Start compose stack
make start-compose-01

# Terminal 3: Start SWA 04
make start-swa-04

# Terminal 4: Run all tests
make test-bruno-direct
make test-bruno-compose
make test-bruno-swa
```

All services run simultaneously on different ports!

## See Also

- `../Makefile` - Development commands
- `../docs/SWA-CLI.md` - SWA CLI documentation
- `../swa-cli.config.json` - SWA CLI configuration
