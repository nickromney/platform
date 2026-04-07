# Hello API Example

This is the smallest checked-in backend scaffold for creating a brand-new API
behind APIM in this repository.

It mirrors the copy-paste recipe in
[`docs/APIM-STARTER-RECIPE.md`](../../docs/APIM-STARTER-RECIPE.md), but with
real files you can run immediately.

## Files

- `main.py`: minimal FastAPI backend with shared OTEL wiring
- `Dockerfile`: container build matching the repo's Python service pattern
- `apim.anonymous.json`: anonymous APIM config
- `apim.subscription.json`: subscription-protected APIM config
- `apim.oidc.jwt-only.json`: JWT-only APIM config
- `apim.oidc.subscription.json`: subscription plus JWT APIM config

## Fastest Path

Anonymous:

```bash
make up-hello
make smoke-hello
```

Subscription-protected:

```bash
make up-hello-subscription
SMOKE_HELLO_MODE=subscription make smoke-hello
```

JWT-only:

```bash
make up-hello-oidc
SMOKE_HELLO_MODE=oidc-jwt make smoke-hello
```

Subscription plus JWT:

```bash
make up-hello-oidc-subscription
SMOKE_HELLO_MODE=oidc-subscription make smoke-hello
```

OTEL:

```bash
make up-hello-otel
make smoke-hello
make verify-hello-otel
```

## URLs

- Gateway: `http://localhost:8000`
- Grafana, when OTEL is enabled: `http://localhost:3001`

These starter configs keep tenant access off by default. If you want
`/apim/management/*` or the operator console, add `tenant_access` to the APIM
config first.

## Read Next

- Starter recipe: [`docs/APIM-STARTER-RECIPE.md`](../../docs/APIM-STARTER-RECIPE.md)
- Training guide: [`docs/APIM-TRAINING-GUIDE.md`](../../docs/APIM-TRAINING-GUIDE.md)
