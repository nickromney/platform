# Sentiment Test Runbook

This app has a small default verification path and a few heavier opt-in checks.

```mermaid
flowchart TD
  A["Change in sentiment"] --> B["Run default checks"]
  B --> C["api-sentiment: bun run test"]
  B --> D["sentiment-auth-ui: bun run test && bun run build"]
  B --> E["make -C apps compose-smoke-sentiment"]
  A --> F["Need TLS or ingress-specific coverage?"]
  F --> G["Run opt-in checks"]
  G --> H["tests/test-tls.sh --execute"]
  G --> I["Manual compose overlays and browser flows"]
```

## Default Checks

- `cd apps/sentiment/api-sentiment && bun run test`
- `cd apps/sentiment/frontend-react-vite/sentiment-auth-ui && bun run test && bun run build`
- `make -C apps compose-smoke-sentiment`

Use this path for normal application changes. It covers the API, the authenticated UI build, and the minimal compose wiring.

## Opt-In Checks

- `cd apps/sentiment && ./tests/test-tls.sh --execute`
- `cd apps/sentiment && docker compose -f compose.yml -f compose.tls.yml up`

Use the opt-in path when you change TLS, reverse-proxy behavior, or browser entry routing.
