# ChatGPT Sim

Go stdlib-only local simulation of the key ChatGPT-to-MCP loop.

It has two roles in the same static binary:

- `ROLE=mcp`: serves a small MCP-compatible HTTP endpoint with protected-resource
  metadata, OAuth authorization-server discovery metadata, tool listing,
  resource listing, and deterministic tool results.
- `ROLE=shell`: serves a vanilla HTML/CSS/JS browser UI plus API endpoints that
  discover the MCP server, call `initialize`, `tools/list`, and `tools/call`,
  then either phrase the result with a deterministic local rule or forward the
  user message and MCP result to an OpenAI-compatible chat-completions endpoint.

There are no third-party Go modules and no JavaScript package dependencies.

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
stub; Kubernetes points `LLM_URL` at the agentgateway-brokered endpoint.

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
