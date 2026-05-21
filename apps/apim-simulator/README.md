# APIM Simulator

Small APIM-shaped gateway for local platform demos. It brokers HTTP APIs and
MCP APIs; AI gateway duties belong to `agentgateway` in the cluster.

The runtime is a single Go binary with embedded HTML/CSS/JS. It intentionally
avoids npm and Python in the simulator path. Local compose can run it directly
or behind oauth2-proxy and Keycloak, matching the app shape used by
`subnetcalc` and `sentiment`.

## Run

Direct simulator:

```bash
make up-direct
open http://localhost:8000
```

SSO-gated simulator:

```bash
make up
open http://localhost:8307
```

Stop everything:

```bash
make down
```

## Test

```bash
make test
```

Focused checks:

```bash
make app-test
make app-js-check
make compose-smoke
make compose-smoke-sso
```

## Local Endpoints

- `GET /` embedded operator console
- `GET /apim/health` runtime health
- `GET /apim/startup` readiness
- `GET /api/health` config-routed demo operation
- `GET /api/echo` config-routed demo operation
- `GET|POST /apim/management/apis` tenant-key-protected API inventory and upsert
- `GET|POST /apim/management/products` tenant-key-protected product inventory and upsert
- `GET|POST /apim/management/subscriptions` tenant-key-protected subscription inventory and upsert
- `GET|POST /apim/management/named-values` tenant-key-protected named value inventory and upsert
- `GET /apim/management/summary` tenant-key-protected inventory
- `POST /apim/management/replay` tenant-key-protected replay

The local tenant key is `local-dev-tenant-key`.

## Shape

- [app/](/Users/nickromney/Developer/personal/platform/apps/apim-simulator/app) contains the Go module.
- [compose.yml](/Users/nickromney/Developer/personal/platform/apps/apim-simulator/compose.yml) contains both direct and SSO local stacks.
- [examples/basic.json](/Users/nickromney/Developer/personal/platform/apps/apim-simulator/examples/basic.json) is the direct local APIM config.
- [examples/sso.json](/Users/nickromney/Developer/personal/platform/apps/apim-simulator/examples/sso.json) is the local SSO APIM config.
- [examples/mcp.json](/Users/nickromney/Developer/personal/platform/apps/apim-simulator/examples/mcp.json) shows an MCP broker config without carrying a local MCP server implementation.

Kubernetes still consumes this app as the `subnetcalc-apim-simulator` image for
the shared APIM namespace.
