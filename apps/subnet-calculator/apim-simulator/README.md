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
- direct public, edge HTTP, edge TLS, private/internal, OIDC, MCP, hello starter, todo demo, and OTEL/LGTM runtime shapes

Local internal caching is supported for the `cache-*` policies. External cache backends and `quota-by-key` bandwidth enforcement remain out of scope.

## Prerequisites

Before running the simulator:

- make sure Docker Engine or Docker Desktop is running
- use `uv` if you want to run smoke scripts, import helpers, or tests from the host
- use `npm` only for the browser-facing demo checks such as Playwright, Bruno, or the UI toolchain

## Choose the Right Stack

| Scenario | Start command | Entry point | Use when |
| --- | --- | --- | --- |
| Direct public gateway | `make up` | `http://localhost:8000` | You want the smallest APIM-shaped gateway path |
| Direct public gateway with OTEL | `make up-otel` | `http://localhost:8000`, `http://localhost:3001` | You want logs, metrics, and traces immediately |
| Todo demo with OTEL | `make up-todo-otel` | `http://localhost:3000` | You want the richest browser-backed teaching flow |
| Hello starter | `make up-hello` | `http://localhost:8000/api/hello` | You want the smallest backend scaffold behind APIM |
| OIDC example | `make up-oidc` | `http://localhost:8000` | You want JWT plus subscription flows |
| MCP example | `make up-mcp` | `http://localhost:8000/mcp` | You want an MCP server behind APIM |
| Edge HTTP | `make up-edge` | `http://apim.localtest.me:8088` | You want forwarded-header and reverse-proxy behavior |
| Edge TLS | `make up-tls` | `https://apim.localtest.me:8443` | You want local TLS termination behavior |
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

- `examples/basic.json`
- `examples/mcp/http.json`
- `examples/oidc/keycloak.json`
- `examples/migrating-from-aws-api-gateway/apim.http-api.json`

These shipped configs keep it off by default:

- `examples/hello-api/apim.*.json`
- `examples/todo-app/apim.json`

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

- `examples/todo-app/api-clients/bruno/`
- `examples/todo-app/api-clients/postman/`
- `examples/todo-app/api-clients/proxyman/`

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
