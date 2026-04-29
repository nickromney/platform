# Local APIM Simulator

Docker-first Azure API Management lab for local gateway work, policy testing, auth flows, management-surface experiments, and OTEL-backed debugging.

Development and testing only. This project is for local iteration, not production APIM replacement.

## Security Note

- Keep this stack local-only. Do not expose it to the internet or use it as a production gateway.
- Demo passwords, tenant keys, and subscription keys in this repository are intentional and exist only for local examples, tutorials, and smoke tests.
- Do not expose or port-forward the demo Keycloak service on `localhost:8180`, especially when running management-enabled stacks.

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

- run `make prereqs` to verify Docker, `mkcert`, and the common local host ports are ready
- make sure Docker Engine or Docker Desktop is running
- use `uv` if you want to run smoke scripts, import helpers, or tests from the host
- use `npm` only for the browser-facing demo checks such as Playwright, Bruno, or the UI toolchain

## Dependency Cooldown

This repository carries repo-local dependency age gates so local installs and
container builds do not rely on host dotfiles.

- Python resolution via `uv` uses a seven-day cutoff in [`pyproject.toml`](pyproject.toml)
- npm package roots ship local `.npmrc` with `min-release-age=7`, and individual example roots can temporarily override it when we intentionally roll a fresh release forward
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

## Release Artifacts

Tagged releases publish two downstream-friendly artifacts:

- `apim-simulator-runtime-vX.Y.Z.zip`, a narrow source context containing only
  `.dockerignore`, `Dockerfile`, `LICENSE.md`, `app/`, `contracts/`,
  `pyproject.toml`, and `uv.lock`
- `ghcr.io/<owner>/apim-simulator`, built from that same runtime context with
  the Dockerfile's Docker Hardened Image defaults, BuildKit provenance, SBOM,
  and GitHub artifact attestations

The runtime zip deliberately excludes examples, docs, tests, compose overlays,
and the UI. Its Dockerfile is patched during packaging so Gitea can build the
zip as a standalone container context.

Build the same artifact locally with:

```bash
make runtime-artifact
```

Manual release workflow runs can also build the image without publishing it,
choose `dhi` or `public` base images for that manual build, and optionally push
the resulting image to GHCR. Tag releases always use the Docker Hardened Image
profile and push the image.

The current Docker Hardened `node` image is also not a drop-in npm builder for
this repo. It ships `node`, but not `npm`, so the Node build stages still stay
on the upstream Node builder images for now while the final shipped nginx image
stays on a hardened runtime base.

## Choose the Right Stack

| Scenario | Start command | Entry point | Use when |
| --- | --- | --- | --- |
| Direct public gateway | `make up` | [http://localhost:8000](http://localhost:8000) | You want the smallest APIM-shaped gateway path |
| Direct public gateway with OTEL | `make up-otel` | [http://localhost:8000](http://localhost:8000), [https://lgtm.apim.127.0.0.1.sslip.io:8443](https://lgtm.apim.127.0.0.1.sslip.io:8443) | You want logs, metrics, and traces immediately |
| Todo demo with OTEL | `make up-todo-otel` | [http://localhost:3000](http://localhost:3000) | You want the richest browser-backed teaching flow |
| Hello starter | `make up-hello` | [http://localhost:8000/api/hello](http://localhost:8000/api/hello) | You want the smallest backend scaffold behind APIM |
| OIDC example | `make up-oidc` | [http://localhost:8000](http://localhost:8000) | You want JWT plus subscription flows |
| MCP example | `make up-mcp` | [http://localhost:8000/mcp](http://localhost:8000/mcp) | You want an MCP server behind APIM |
| Edge HTTP | `make up-edge` | [http://edge.apim.127.0.0.1.sslip.io:8088](http://edge.apim.127.0.0.1.sslip.io:8088) | You want forwarded-header and reverse-proxy behaviour |
| Edge TLS | `make up-tls` | [https://edge.apim.127.0.0.1.sslip.io:9443](https://edge.apim.127.0.0.1.sslip.io:9443) | You want local TLS termination behaviour |
| Private internal stack | `make up-private` | no host gateway port | You want the MCP stack reachable only from the internal compose network |
| Operator console | `make up-ui` | `http://localhost:3007` | You want the fastest control-room view of a running management-enabled stack |
| Backstage API catalog | `make up-backstage` | `http://localhost:7007` | You want an optional API-aware developer portal over the simulator catalog |
| Every compose stack at once | `make up-all` | slot-based; printed during startup | You want the whole repo up simultaneously without port collisions |

## Quick Start

### New To APIM?

If you do not already have an APIM mental model, start with the control room:

```bash
make up-ui
```

Then open [http://localhost:3007](http://localhost:3007), click `Load Local Demo`, and connect.

Use that first pass to answer four basic questions:

- what APIs, routes, products, and backends are loaded
- which policy scopes exist
- what a traced request looks like
- what a replay through the gateway returns

After that, move to the browser-backed todo flow if you want to see a client calling APIM end to end.

### Browser-Backed Teaching Flow

For the most complete end-to-end flow:

```bash
make up-todo-otel
make smoke-todo
make verify-todo-otel
```

Then open:

- [http://localhost:3000](http://localhost:3000)
- [https://lgtm.apim.127.0.0.1.sslip.io:8443/d/apim-simulator-overview/apim-simulator-overview](https://lgtm.apim.127.0.0.1.sslip.io:8443/d/apim-simulator-overview/apim-simulator-overview)

### Smallest path

For the smallest possible gateway bring-up:

```bash
make up
curl http://localhost:8000/apim/health
curl http://localhost:8000/api/echo
```

## Run Many Stacks At Once

The default `make up-*` targets keep the repo’s current ports and compose
project names. Nothing changes unless you opt in.

Use `STACK_SLOT` when you want an isolated copy of a stack with a predictable
port shift and a unique compose project name:

```bash
STACK_SLOT=1 make up-otel
STACK_SLOT=1 make smoke-oidc
```

Each slot shifts the published host ports by `100`, so slot `1` moves the
default gateway from `8000` to `8100`, Grafana from `8443` to `8543`, Keycloak
from `8180` to `8280`, and the todo frontend from `3000` to `3100`.

If you prefer a raw offset, use `PORT_OFFSET` directly:

```bash
PORT_OFFSET=200 make up-ui
```

To start every compose stack in one pass with non-conflicting ports:

```bash
make up-all
make down-all
```

`up-all` assigns a distinct slot to each stack automatically, including the
todo, OIDC, edge, UI, hello, and private variants.

## Tutorial Mirror

For a simulator-native version of the Microsoft Learn getting-started sequence, see:

- [apim-get-started](docs/tutorials/apim-get-started/README.md)
- [tutorial01.sh](docs/tutorials/apim-get-started/tutorial01.sh) through [tutorial11.sh](docs/tutorials/apim-get-started/tutorial11.sh) for self-contained mirrored tutorial shortcuts kept alongside the matching markdown guides; use `--dry-run` to preview, `--setup`/`--execute` to apply a step, and `--verify` to validate it
- [tutorial-cleanup.sh](docs/tutorials/apim-get-started/tutorial-cleanup.sh) to preview with `--dry-run` or stop the tutorial compose stacks with `--execute`

## Interacting with the Simulator

### Choosing the right base URL

Use the gateway URL that matches where your application is running:

- from the local machine, use [http://localhost:8000](http://localhost:8000)
- from another container on the same compose network, use [http://apim-simulator:8000](http://apim-simulator:8000)
- for the edge HTTP stack, use [http://edge.apim.127.0.0.1.sslip.io:8088](http://edge.apim.127.0.0.1.sslip.io:8088)
- for the edge TLS stack, use [https://edge.apim.127.0.0.1.sslip.io:9443](https://edge.apim.127.0.0.1.sslip.io:9443)

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

Then open `http://localhost:3007`, use `Load Local Demo`, and connect to `http://localhost:8000`.

### Optional Backstage Portal

The simulator publishes [Backstage catalog metadata](catalog-info.yaml) for the
gateway and management APIs. The repository also carries a minimal catalog/API
docs Backstage app under [backstage/app](backstage/app), so a fresh clone can
start the portal without cloning a platform repo.

This starts Backstage beside the direct public APIM stack:

```bash
make up-backstage
make smoke-backstage
```

You can also opt the portal into the smallest stack:

```bash
BACKSTAGE_ENABLED=true make up
```

The Backstage app itself is not part of the narrow runtime artifact intended for
downstream vendoring. Consumers such as `platform` should vendor
`catalog-info.yaml`, not a second Backstage application.

The app follows Backstage's current Yarn 4 workspace layout. The committed
`yarn.lock` and vendored Yarn release are marked as generated review artifacts
with `.gitattributes`.

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
uv run --project . python scripts/import_openapi.py
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
