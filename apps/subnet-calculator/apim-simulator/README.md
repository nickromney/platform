# Local APIM Simulator

Docker-first Azure API Management lab for local gateway work, policy testing, auth flows, management-surface experiments, and OTEL-backed debugging.

Development and testing only. This project is for local iteration, not production APIM replacement.

## About the Simulator

The simulator gives you a local APIM-shaped gateway with:

- config-driven APIs, operations, products, subscriptions, version sets, backends, named values, policy fragments, tags, users, groups, loggers, and diagnostics
- APIM-style auth flows, including anonymous, subscription-key, JWT/OIDC, scope, role, claim, and client-certificate checks
- a practical XML policy subset, including routing, transforms, throttling, caching, JWT validation, backend selection, and `send-request`
- tenant-key-protected management APIs, per-request traces, replay, and a local operator console
- Terraform/OpenTofu import and static compatibility reporting
- direct public, edge HTTP, edge TLS, private/internal, OIDC, MCP, hello starter, todo demo, and OTEL/[LGTM](https://github.com/grafana/docker-otel-lgtm) runtime shapes

Local internal caching is supported for the `cache-*` policies. External cache backends and `quota-by-key` bandwidth enforcement remain out of scope.

## Prerequisites

Before running the simulator:

- make sure Docker Engine or Docker Desktop is running
- use `uv` if you want to run smoke scripts, import helpers, or tests from the host
- use `npm` only for the browser-facing demo checks such as Playwright, Bruno, or the UI toolchain

## Dependency Cooldown

This repository carries repo-local dependency age gates so local installs and
container builds do not rely on host dotfiles.

- Python resolution via `uv` uses a seven-day cutoff in [`pyproject.toml`](pyproject.toml)
- npm package roots ship local `.npmrc` with `min-release-age=7`
- frontend Dockerfiles copy `.npmrc` before `npm ci` so image builds keep the
  same cooldown policy

## Container Hardening

The stateless services now default to a tighter local runtime posture:

- non-root users in the Python and nginx containers
- read-only root filesystems for the gateway, mock backend, MCP example, hello
  example, todo API, todo frontend, and edge proxy
- read-only roots for the [LGTM](https://github.com/grafana/docker-otel-lgtm) container and the private smoke runner, with
  writable state moved onto named volumes or `tmpfs`
- `cap_drop: [ALL]`, `security_opt: ["no-new-privileges:true"]`, `tmpfs` for
  writable scratch paths, and `init: true` where it helps process handling
- a prebuilt static operator console image instead of `npm install && vite dev`
  inside the running container
- Docker Hardened runtime bases by default for the shipped Python and nginx
  images

By default, the shipped runtime images use Docker Hardened Images for the
Python and nginx stages. If you need the non-DHI path instead, create a local
override file and set the upstream image refs explicitly:

```bash
cp .env.example .env
```

Then uncomment the upstream overrides:

- `PYTHON_BUILD_IMAGE=python:3.13-slim`
- `PYTHON_RUNTIME_IMAGE=python:3.13-slim`
- `NGINX_RUNTIME_IMAGE=nginx:1.27-alpine`
- `EDGE_PROXY_IMAGE=nginx:1.27-alpine`
- `SMOKE_RUNNER_IMAGE=python:3.13-slim`

If you stay on the default path, authenticate once with:

```bash
docker login dhi.io
```

The Docker-backed CI jobs use the same idea as the platform repo: they check
whether the runner already has `dhi.io` credentials and use the hardened image
defaults when available, otherwise they fall back to the upstream image
overrides automatically. There is no separate nightly DHI workflow.

Keycloak is still the main exception. The shipped `start-dev` path rebuilds
Quarkus artifacts on startup, so it cannot use a read-only root without moving
to a custom optimized image.

The current Docker Hardened `node` image is also not a drop-in npm builder for
this repo. It ships `node`, but not `npm`, so the Node build stages still stay
on the upstream Node builder images for now while the final shipped nginx image
stays on a hardened runtime base.

## Choose the Right Stack

| Scenario | Start command | Entry point | Use when |
| --- | --- | --- | --- |
| Direct public gateway | `make up` | `http://localhost:8000` | You want the smallest APIM-shaped gateway path |
| Direct public gateway with OTEL | `make up-otel` | `http://localhost:8000`, `http://localhost:3001` | You want logs, metrics, and traces immediately |
| Todo demo with OTEL | `make up-todo-otel` | `http://localhost:3000` | You want the richest browser-backed teaching flow |
| Hello starter | `make up-hello` | `http://localhost:8000/api/hello` | You want the smallest backend scaffold behind APIM |
| OIDC example | `make up-oidc` | `http://localhost:8000` | You want JWT plus subscription flows |
| MCP example | `make up-mcp` | `http://localhost:8000/mcp` | You want an MCP server behind APIM |
| Edge HTTP | `make up-edge` | `http://apim.localtest.me:8088` | You want forwarded-header and reverse-proxy behaviour |
| Edge TLS | `make up-tls` | `https://apim.localtest.me:8443` | You want local TLS termination behaviour |
| Operator console | `make up-ui` | `http://localhost:3007` | You want to inspect and edit a running management-enabled stack |

## Quick Start

### Recommended path

For the most complete end-to-end flow:

```bash
make up-todo-otel
make smoke-todo
make verify-todo-otel
```

Then open:

- `http://localhost:3000`
- `http://localhost:3001/d/apim-simulator-overview/apim-simulator-overview`

### Smallest path

For the smallest possible gateway bring-up:

```bash
make up
curl http://localhost:8000/apim/health
curl http://localhost:8000/api/echo
```

## Tutorial Mirror

For a simulator-native version of the Microsoft Learn getting-started sequence, see:

- [apim-get-started](docs/tutorials/apim-get-started/README.md)
- [tutorial01.sh](docs/tutorials/apim-get-started/tutorial01.sh) through [tutorial11.sh](docs/tutorials/apim-get-started/tutorial11.sh) for self-contained mirrored tutorial shortcuts kept alongside the matching markdown guides; use `--setup` to apply a step and `--verify` to validate it
- [tutorial-cleanup.sh](docs/tutorials/apim-get-started/tutorial-cleanup.sh) to stop the tutorial compose stacks

## Interacting with the Simulator

### Choosing the right base URL

Use the gateway URL that matches where your application is running:

- from the local machine, use `http://localhost:8000`
- from another container on the same compose network, use `http://apim-simulator:8000`
- for the edge HTTP stack, use `http://apim.localtest.me:8088`
- for the edge TLS stack, use `https://apim.localtest.me:8443`

### Gateway health and startup

Use these first when checking reachability:

```bash
curl http://localhost:8000/apim/health
curl http://localhost:8000/apim/startup
```

### Management API access

The management API exists only when the loaded config enables `tenant_access`.

These shipped configs enable it:

- [examples/basic.json](examples/basic.json)
- [examples/mcp/http.json](examples/mcp/http.json)
- [examples/oidc/keycloak.json](examples/oidc/keycloak.json)
- [examples/migrating-from-aws-api-gateway/apim.http-api.json](examples/migrating-from-aws-api-gateway/apim.http-api.json)

These shipped configs keep it off by default:

- the `apim.*.json` files under [examples/hello-api/](examples/hello-api/)
- [examples/todo-app/apim.json](examples/todo-app/apim.json)

When the management API is enabled, use the tenant key header:

```bash
curl \
  -H "X-Apim-Tenant-Key: local-dev-tenant-key" \
  http://localhost:8000/apim/management/status
```

The operator console uses the same management surface. Start it with:

```bash
make up-ui
```

Then connect to `http://localhost:8000` from `http://localhost:3007`.

### Request tracing

To capture APIM-style per-request detail:

```bash
curl -i \
  -H "x-apim-trace: true" \
  http://localhost:8000/api/echo
```

Read the `x-apim-trace-id` response header, then inspect:

```bash
curl http://localhost:8000/apim/trace/<trace-id>
```

## Examples and Client Artifacts

### Hello starter

Smallest checked-in backend scaffold behind APIM:

```bash
make up-hello
make smoke-hello
```

Additional starter modes:

```bash
make up-hello-subscription
SMOKE_HELLO_MODE=subscription make smoke-hello

make up-hello-oidc
SMOKE_HELLO_MODE=oidc-jwt make smoke-hello

make up-hello-oidc-subscription
SMOKE_HELLO_MODE=oidc-subscription make smoke-hello

make up-hello-otel
make smoke-hello
make verify-hello-otel
```

### Todo demo

Browser-backed APIM demo with Astro frontend and FastAPI backend:

```bash
make up-todo
make smoke-todo
make test-todo-e2e
make test-todo-bruno
make test-todo-postman
make export-todo-har
```

Client artifacts live under:

- [examples/todo-app/api-clients/bruno/](examples/todo-app/api-clients/bruno/)
- [examples/todo-app/api-clients/postman/](examples/todo-app/api-clients/postman/)
- [examples/todo-app/api-clients/proxyman/](examples/todo-app/api-clients/proxyman/)

### AWS API Gateway migration starter

Stage-style local APIM shape for migration-oriented work:

```bash
HELLO_APIM_CONFIG_PATH=/app/examples/migrating-from-aws-api-gateway/apim.http-api.json make up-hello
curl -H "Ocp-Apim-Subscription-Key: aws-migration-demo-key" http://localhost:8000/prod/hello
```

### MCP example

Minimal streamable HTTP MCP server behind APIM:

```bash
make up-mcp
make smoke-mcp
```

## Import and Compatibility

Import a local or remote OpenAPI document directly into a running simulator:

```bash
OPENAPI_SOURCE=examples/mock-backend/openapi.json \
APIM_API_ID=tutorial-api \
APIM_API_NAME="Tutorial API" \
APIM_API_PATH=tutorial-api \
uv run python scripts/import_openapi.py
```

Import a running simulator from a `tofu show -json` payload:

```bash
make up
TOFU_SHOW=/path/to/tofu-show.json make import-tofu
```

Run the static compatibility report without starting the gateway:

```bash
TOFU_SHOW=/path/to/tofu-show.json make compat-report
```

Run the curated APIM sample compatibility harness:

```bash
make compat
```

Key Vault-backed named values are local-first. Provide local overrides with env vars in the form `APIM_NAMED_VALUE_<NAME>`.

## Development

Common commands:

```bash
make help
make lint-check
make test
make compat
make down
```

Before opening a PR:

```bash
make lint-check
make test
```

## Further Reading

- Basics and onboarding: [docs/APIM-TRAINING-GUIDE.md](docs/APIM-TRAINING-GUIDE.md)
- First-day checklist: [docs/FIRST-DAY-APIM-CHECKLIST.md](docs/FIRST-DAY-APIM-CHECKLIST.md)
- APIM vocabulary in repo terms: [docs/AZURE-APIM-TERM-MAP.md](docs/AZURE-APIM-TERM-MAP.md)
- Bruno and Postman workflows: [docs/API-CLIENT-GUIDE.md](docs/API-CLIENT-GUIDE.md)
- Build a new API behind the simulator: [docs/APIM-STARTER-RECIPE.md](docs/APIM-STARTER-RECIPE.md)
- Delivery workflow for contributors: [docs/APIM-TEAM-PLAYBOOK.md](docs/APIM-TEAM-PLAYBOOK.md)
- AWS API Gateway mapping: [docs/MIGRATING-FROM-AWS-API-GATEWAY.md](docs/MIGRATING-FROM-AWS-API-GATEWAY.md)
- Scope and limits: [docs/SCOPE.md](docs/SCOPE.md)
- Capability matrix: [docs/CAPABILITY-MATRIX.md](docs/CAPABILITY-MATRIX.md)
- Management-surface guide: [docs/APIM-SDK-SURFACE-GUIDE.md](docs/APIM-SDK-SURFACE-GUIDE.md)
- Roadmap: [docs/NEXT-FEATURES.md](docs/NEXT-FEATURES.md)
