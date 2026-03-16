# Sentiment LLM

Local sentiment-analysis demo with a compose-first runtime that mirrors the
same broad concerns as the Kubernetes demo: authenticated browser entry,
frontend and API separation, and a switchable LLM backend path.

## Start Here

- Compose runtime architecture: [docs/COMPOSE-ARCHITECTURE.md](docs/COMPOSE-ARCHITECTURE.md)
- Test runbook: [docs/TEST-RUNBOOK.md](docs/TEST-RUNBOOK.md)
- Main local stack: [compose.yml](compose.yml)
- TLS overlay: [compose.tls.yml](compose.tls.yml)

## Main Runtime Slices

- `keycloak` provides the local OIDC provider.
- `oauth2-proxy` forces browser login before forwarding traffic upstream.
- `edge` splits browser traffic between the static UI and the API.
- `sentiment-api` calls either the in-container LLM path or a host-backed
  OpenAI-compatible endpoint.
- `litellm` and `llama-cpp` are the default in-compose inference path.

## Quick Start

```bash
docker compose up
```

Optional TLS front door:

```bash
docker compose -f compose.yml -f compose.tls.yml up
```
