# Platform MCP

Platform MCP server for the platform learning environment.

The deployed kind image is built from [`app-go/`](app-go/) using the same
single-binary, no runtime dependency pattern as the other `app-go` workloads.
The legacy Python package remains here for local comparison while the
Kubernetes path uses the Go implementation.

It serves Streamable HTTP on `/mcp` and exposes seven tools:

- `platform_status`
- `platform_catalog_list`
- `subnetcalc_calculate`
- `sentiment_classify` (calls the sentiment classify-only endpoint and does not persist comments)
- `d2_validate`
- `d2_format`
- `d2_render`

Run deployed app tests:

```bash
make -C apps/platform-mcp/app-go test
```

Build the deployed image binary:

```bash
make -C apps/platform-mcp/app-go build-linux
```

Run legacy Python tests:

```bash
uv run --extra dev pytest
```

Run locally:

```bash
uv run platform-mcp
```

Run the container-only MCP stack without kind:

```bash
docker compose -f apps/platform-mcp/compose.yml up -d --build
```

Local endpoints:

- MCP Streamable HTTP: `http://localhost:8089/mcp`
- MCP health: `http://localhost:8089/health`
- MCP metrics: `http://localhost:9099/metrics`
- MCP Inspector: `http://localhost:6274`

Run the compose deployability smoke:

```bash
apps/platform-mcp/tests/compose-smoke.sh --execute
```

List tools from the routed endpoint:

```bash
PLATFORM_MCP_BEARER_TOKEN=... uv run platform-mcp-smoke
```
