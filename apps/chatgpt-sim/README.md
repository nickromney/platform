# ChatGPT Sim

Small Go local simulation of the key ChatGPT-to-MCP loop.

It has two roles in the same static binary:

- `ROLE=mcp`: serves a small MCP-compatible HTTP endpoint with protected-resource
  metadata, OAuth authorization-server discovery metadata, tool listing,
  resource listing, and deterministic tool results.
- `ROLE=shell`: serves a vanilla HTML/CSS/JS browser UI plus API endpoints that
  discover the MCP server, call `initialize`, `tools/list`, and `tools/call`,
  then either phrase the result with a deterministic local rule or forward the
  user message and MCP result to an OpenAI-compatible chat-completions endpoint.

The shell reuses the repo-local shared Go app libraries for HTTP, browser
assets, and provider-neutral OIDC/session helpers. There are no JavaScript
package dependencies.

## Local Run

```sh
make -C apps/chatgpt-sim up
```

Open `http://localhost:18084`.

The compose stack publishes the MCP role on the private compose network and
the shell role at `http://localhost:18084`.

The shell includes a small connector settings panel. Adding an MCP URL makes the
shell fetch protected-resource metadata and OAuth authorization-server metadata,
similar to the discovery step in ChatGPT's custom app dialog.

## AI Chat Layer

Without `LLM_URL`, the simulator uses deterministic Go code in
`internal/app/server.go`:

- `chooseTool` is the planner. It maps a user message to either `tools/list` or
  one of the advertised MCP tools.
- `callMCP` is the tool-use loop. It calls `initialize`, `tools/list`, and then
  either summarizes discovered tools or calls the selected tool.
- `deterministicReply` is the response generator. It phrases the MCP result for
  the user without inventing facts.

Try asking:

```text
what tools did you discover?
who am I to the MCP server?
show route evidence
show security posture
```

With `LLM_URL`, the shell keeps MCP discovery and tool calls in-process, then
posts the user message plus MCP result to an OpenAI-compatible
`/v1/chat/completions` endpoint. The compose file runs a tiny stdlib `ROLE=llm`
stub named `go-local-openai-compatible-stub`; it is not a bundled mini model.
Kubernetes points `LLM_URL` at the agentgateway-brokered endpoint.
`LLM_MODEL` should be set when the target model is known; otherwise the shell
discovers `/v1/models` before completion. `LLM_TIMEOUT_SECONDS`,
`LLM_MAX_TOKENS`, and `LANGFUSE_TIMEOUT_SECONDS` bound the request so the
interactive SSO route returns before the gateway times out.

If that configured endpoint is unavailable or returns unusable text, `/api/chat`
falls back to `deterministicReply` and includes model metadata such as
`"status":"unavailable"` or `"status":"fallback"` in the JSON inspector output.

To point the app-local compose shell at a running OpenAI-compatible oMLX
endpoint instead of the stub, override the shell endpoint:

```sh
CHATGPT_SIM_LLM_URL=http://host.docker.internal:8000/v1/chat/completions \
CHATGPT_SIM_LLM_MODEL=Qwen3.5-9B-MLX-4bit \
  make -C apps/chatgpt-sim up-direct
```

To also prove Langfuse ingestion from the shell, provide the local Langfuse
endpoint and keys:

```sh
CHATGPT_SIM_LLM_URL=http://host.docker.internal:8000/v1/chat/completions \
CHATGPT_SIM_LLM_MODEL=Qwen3.5-9B-MLX-4bit \
CHATGPT_SIM_LANGFUSE_HOST=http://host.docker.internal:3000 \
CHATGPT_SIM_LANGFUSE_PUBLIC_KEY=pk-lf-local-platform \
CHATGPT_SIM_LANGFUSE_SECRET_KEY=sk-lf-local-platform \
  make -C apps/chatgpt-sim up-direct
```

Then post a chat request and check the response inspector payload. A successful
oMLX call reports `"model":{"status":"ok",...}` and a successful Langfuse
ingestion reports `"trace":{"provider":"langfuse","status":"ok",...}`:

```sh
curl -fsS http://localhost:18084/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"who am I to the MCP server?"}'
```

## OAuth Scope

The first local slice supports the ChatGPT-style OAuth discovery surface:

- protected-resource metadata at `/.well-known/oauth-protected-resource/mcp`
- authorization-server metadata at `/.well-known/oauth-authorization-server`
- `WWW-Authenticate` challenges for unauthenticated `/mcp` calls
- tool descriptors carrying OAuth scope metadata

It does not yet run a full browser login or validate a real Keycloak-issued JWT.
The local MCP accepts any bearer token so the red/green loop stays fast while the
protocol shape is exercised.

## Tests

```sh
make -C apps/chatgpt-sim/app test
```
