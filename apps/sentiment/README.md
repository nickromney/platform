# Sentiment

Local sentiment-analysis demo with a compose-first runtime that mirrors the
same broad concerns as the Kubernetes demo: authenticated browser entry,
frontend and API separation, and a switchable sentiment backend path.

## Start Here

- Compose runtime architecture: [docs/COMPOSE-ARCHITECTURE.md](docs/COMPOSE-ARCHITECTURE.md)
- Test runbook: [docs/TEST-RUNBOOK.md](docs/TEST-RUNBOOK.md)
- Main local stack: [compose.yml](compose.yml)
- TLS overlay: [compose.tls.yml](compose.tls.yml)

## Main Runtime Slices

- `keycloak` provides the local OIDC provider.
- `oauth2-proxy` forces browser login before forwarding traffic upstream.
- `edge` splits browser traffic between the static UI and the API.
- `sentiment-api` defaults to an in-process SST sentiment classifier.
- `litellm` and `llama-cpp` remain available as an opt-in legacy LLM path.

## Quick Start

```bash
docker compose up
```

From this directory you can also use:

```bash
make up
```

That starts the authenticated local stack and prints the URL to open.

Optional TLS front door:

```bash
docker compose -f compose.yml -f compose.tls.yml up
```
