# Platform MCP

Python MCP server for the platform learning environment.

It serves Streamable HTTP on `/mcp` and exposes seven tools:

- `platform_status`
- `platform_catalog_list`
- `subnetcalc_calculate`
- `sentiment_classify`
- `d2_validate`
- `d2_format`
- `d2_render`

Run tests:

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
