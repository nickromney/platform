# Local AI Gateway Example

The AI gateway example simulates the APIM gateway responsibilities in front of
model endpoints. It does not run models inside APIM and does not emulate the
Azure AI Foundry control plane.

## What It Covers

- OpenAI-compatible request routing for `/v1/chat/completions`,
  `/v1/embeddings`, `/v1/responses`, and Azure-style
  `/openai/deployments/{deployment}/...` paths.
- Deployment-to-backend mapping through `ai_gateway.deployments`.
- Priority backend selection with in-memory circuit state for configured
  `429` and `5xx` responses.
- Same-request fallback to the next configured backend when a backend trips the
  local breaker.
- Lightweight `llm-token-limit` and `azure-openai-token-limit` policy support
  using an approximate prompt estimate and response `usage.total_tokens`.
- Gateway-derived consumer variables for policies:
  `consumer_id`, `consumer_name`, and `consumer_type`. Subscription-authenticated
  callers use the subscription identity; JWT-authenticated callers fall back to
  client/application claims.

## Governed Cluster Agent Pattern

For a Kubernetes agent calling a local or external LLM endpoint, put APIM
simulator on the path and attach the route to a subscription-required product.
The model stays behind the gateway; the gateway enforces access and local
policy counters.

Use subscription keys for simple in-cluster agent identities, or JWT plus
subscription when the caller already has workload identity. Policy counters can
then key on the gateway-derived consumer:

```xml
<rate-limit-by-key
  calls="60"
  renewal-period="60"
  counter-key="@(context.Variables.GetValueOrDefault(&quot;consumer_id&quot;,&quot;anonymous&quot;))" />
```

For OpenAI-compatible model calls, use the same counter key with
`llm-token-limit` when you want token-rate limiting instead of call-rate
limiting. This is local token governance, not cost accounting.

## Run It

```bash
make up-ai-gateway
make smoke-ai-gateway
```

The default stack starts two tiny mock OpenAI-compatible backends:

- `local-primary` in `local-eu`
- `local-secondary` in `local-us`

The gateway entry point is `http://localhost:8000/ai`.

```bash
curl -sS \
  -H 'content-type: application/json' \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hello"}]}' \
  http://localhost:8000/ai/v1/chat/completions
```

## Real Local Model With llama.cpp

For a mock-free path, the simulator can front a host `llama-server` process
from llama.cpp. The helper downloads the prebuilt llama.cpp server and the
default Qwen2.5 0.5B Instruct Q4_K_M GGUF model into
`.run/llamacpp/`, starts the server on `127.0.0.1:8087`, then points APIM at
`host.docker.internal:8087`.

```bash
make setup-llamacpp
make up-ai-gateway-llamacpp
make llamacpp-memory
make down-ai-gateway-llamacpp
```

The end-to-end smoke starts llama.cpp, starts APIM, sends a direct chat
completion through APIM, then runs the sentiment compose smoke against that
same APIM endpoint:

```bash
make smoke-ai-gateway-llamacpp
```

The default footprint is intentionally small:

- runtime archive: selected from the latest llama.cpp release for the host OS
  and CPU architecture
- model artifact: `qwen2.5-0.5b-instruct-q4_k_m.gguf`, roughly 500 MiB
- serving mode: CPU-only by default with `-ngl 0` and context size `1024`
- memory samples: appended to `.run/llamacpp/llama-server-memory.jsonl`

Useful overrides:

```bash
LLAMACPP_MODEL_PATH=/path/to/model.gguf make up-ai-gateway-llamacpp
LLAMACPP_RELEASE_TAG=<tag> make setup-llamacpp
LLAMACPP_THREADS=6 LLAMACPP_CTX_SIZE=2048 make smoke-ai-gateway-llamacpp
LLAMACPP_KEEP_RUNNING_AFTER_SMOKE=1 make smoke-ai-gateway-llamacpp
```

The APIM config for this path is
`examples/ai-gateway/apim.llamacpp.json`. It uses the deployment name
`qwen2.5-0.5b-instruct-q4_k_m`; sentiment sets that model name when the
llama.cpp smoke runs.

To exercise fallback, force only the primary backend to return `429`:

```bash
curl -sS \
  -H 'content-type: application/json' \
  -H 'x-ai-mock-fail-backend: local-primary' \
  -H 'x-ai-mock-status: 429' \
  -H 'x-ai-mock-retry-after: 1' \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"fallback"}]}' \
  http://localhost:8000/ai/v1/chat/completions
```

## Configuration Shape

The gateway reads `examples/ai-gateway/apim.json`.

```json
{
  "backends": {
    "openai-primary-local": {"url": "http://ai-openai-primary:8080"},
    "openai-secondary-local": {"url": "http://ai-openai-secondary:8080"}
  },
  "ai_gateway": {
    "strategy": "priority",
    "circuit_breaker": {
      "trip_status_codes": [429],
      "trip_status_code_ranges": ["5xx"],
      "honor_retry_after": true
    },
    "deployments": {
      "gpt-4o-mini": {
        "backend_ids": ["openai-primary-local", "openai-secondary-local"]
      }
    }
  }
}
```

For real local inference, point those backend URLs at local model servers on the
compose network. For external forwarding, point them at OpenAI-compatible
provider URLs and configure backend credentials with the existing backend auth,
header credential, or query credential fields.

## Deliberate Limits

- No model runtime is started by the simulator itself.
- No Redis, Event Hubs, tokenizer package, semantic cache, or external quota
  store is required.
- Circuit and token counters are process-local and reset on restart.
- Backend selection is priority-only; weighted balancing and regional latency
  routing are out of scope for the first pass.
- No semantic MCP tool routing is included. APIM gates the MCP HTTP endpoint;
  the MCP server still owns tool discovery and selection semantics.
