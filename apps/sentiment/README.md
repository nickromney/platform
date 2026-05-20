# Sentiment

Local sentiment-analysis demo with a compose-first runtime that mirrors the
same broad concerns as the Kubernetes demo: authenticated browser entry plus
frontend and API separation.

The default runtime is now [`app/`](app/). It builds one small DHI static
image for the compiled Go binary and runs as two microservices:

- `sentiment-api` with `RUNTIME_ROLE=backend`
- `sentiment-auth-frontend` with `RUNTIME_ROLE=frontend`

The frontend is vanilla HTML/CSS/JavaScript. The backend uses Go stdlib and a
deterministic lexicon classifier so the default path does not require npm,
Vite, React, Node, or a model dependency tree.

## Start Here

- Compose runtime architecture: [docs/COMPOSE-ARCHITECTURE.md](docs/COMPOSE-ARCHITECTURE.md)
- Test runbook: [docs/TEST-RUNBOOK.md](docs/TEST-RUNBOOK.md)
- Main local stack: [compose.yml](compose.yml)
- TLS overlay: [compose.tls.yml](compose.tls.yml)

## Main Runtime Slices

- `keycloak` provides the local OIDC provider.
- `oauth2-proxy` forces browser login before forwarding traffic upstream.
- `edge` splits browser traffic between the static UI and the API.
- `sentiment-api` runs the Go backend role and owns classification.
- `compose.apim-ai-gateway.yml` is retained as a legacy/model-backed experiment
  path, but the default runtime no longer loads SST in-process.

## Quick Start

Before the authenticated compose flows, copy the repo root template and set the
secrets it needs:

```bash
cp ../../.env.example ../../.env
```

`make` targets in this directory load `../../.env` automatically. Raw
`docker compose` commands should pass it explicitly with `--env-file ../../.env`.

```bash
docker compose --env-file ../../.env up
```

From this directory you can also use:

```bash
make up
```

That starts the authenticated local stack and prints the URL to open.

Optional TLS front door:

```bash
docker compose --env-file ../../.env -f compose.yml -f compose.tls.yml up
```

Optional APIM AI gateway inference path:

```bash
make -C ../apim-simulator up-ai-gateway
make up-apim-ai-gateway
make smoke-apim-ai-gateway
```

This keeps the sentiment API contract unchanged while routing inference through
`http://localhost:8000/ai/v1/chat/completions`. The APIM simulator still does
gateway work only; the model endpoint is whatever the APIM AI gateway config
fronts.

For the same sentiment path backed by a real local llama.cpp model instead of
the APIM mock model endpoints, run:

```bash
make -C ../apim-simulator smoke-ai-gateway-llamacpp
```

That command starts llama.cpp, starts the APIM llama.cpp overlay, runs a direct
APIM chat completion, then runs this app's `smoke-apim-ai-gateway` target
against the real model path.
