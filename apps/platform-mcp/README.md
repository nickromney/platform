# Platform MCP

Platform MCP server for the platform learning environment.

The deployed kind image is built from [`app-go/`](app-go/) using the same
single-binary, no runtime dependency pattern as the other `app-go` workloads.

It serves Streamable HTTP on `/mcp` and exposes these tools:

- `d2_validate`
- `d2_render`
- `model_ping` (calls the OpenAI-compatible endpoint through agentgateway)

Run tests:

```bash
make -C apps/platform-mcp/app-go test
```

Build the deployed image binary:

```bash
make -C apps/platform-mcp/app-go build-linux
```

Run locally:

```bash
make -C apps/platform-mcp/app-go run
```

Local endpoints:

- MCP Streamable HTTP: `http://localhost:8080/mcp`
- MCP health: `http://localhost:8080/health`
- MCP metrics: `http://localhost:9090/metrics`

List tools from the routed endpoint:

```bash
curl -fsS https://mcp.127.0.0.1.sslip.io/mcp \
  -H "Authorization: Bearer ${PLATFORM_MCP_BEARER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```
