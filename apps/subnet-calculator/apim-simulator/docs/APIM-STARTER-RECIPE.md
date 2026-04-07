# APIM Starter Recipe

This guide shows the fastest way to create a brand-new API behind APIM in this
repository.

The repo ships a working scaffold under `examples/hello-api/` plus compose
overlays and a smoke script, so the docs and the example stay aligned.

Use this guide in two ways:

- run the checked-in `hello-api` example to see the pattern in a working stack
- copy and rename that scaffold when you need a new service

If you need the APIM model first, read
[`APIM-TRAINING-GUIDE.md`](./APIM-TRAINING-GUIDE.md) first.

## What Ships In The Scaffold

These files already exist:

- `examples/hello-api/main.py`
- `examples/hello-api/Dockerfile`
- `examples/hello-api/apim.anonymous.json`
- `examples/hello-api/apim.subscription.json`
- `examples/hello-api/apim.oidc.jwt-only.json`
- `examples/hello-api/apim.oidc.subscription.json`
- `examples/hello-api/README.md`
- `compose.hello.yml`
- `compose.hello.otel.yml`
- `scripts/smoke_hello.py`

That gives you four auth variants out of the box:

1. anonymous
2. subscription-only
3. JWT-only
4. subscription plus JWT

The checked-in starter configs keep `tenant_access` disabled. That keeps the
example small, but it also means `/apim/management/*` and the operator console
stay unavailable until you add tenant access to the APIM config.

## Fastest Path

Run the anonymous version first:

```bash
make up-hello
make smoke-hello
```

That verifies routing before you add auth.

Switch to subscription-only:

```bash
make up-hello-subscription
SMOKE_HELLO_MODE=subscription make smoke-hello
```

Switch to JWT-only:

```bash
make up-hello-oidc
SMOKE_HELLO_MODE=oidc-jwt make smoke-hello
```

Switch to subscription plus JWT:

```bash
make up-hello-oidc-subscription
SMOKE_HELLO_MODE=oidc-subscription make smoke-hello
```

Add OTEL and LGTM:

```bash
make up-hello-otel
make smoke-hello
make verify-hello-otel
```

Then open:

- `http://localhost:8000/apim/health`
- `http://localhost:8000/api/hello?name=team`
- `http://localhost:3001`

## What Each File Does

### `examples/hello-api/main.py`

This is the smallest useful backend:

- normal FastAPI routes
- shared OTEL wiring from `app/telemetry.py`
- one health route
- one business route

If you are creating a new service, this is the first file you copy and rename.

### `examples/hello-api/Dockerfile`

This matches the repo's standard Python service container pattern:

- builds the virtualenv once with `uv`
- copies the shared `app/` package so OTEL helpers are available
- runs the backend internally on port `8000`

If your new backend is also Python, start here before inventing a new container
shape.

### `examples/hello-api/apim.*.json`

These are the gateway-side variants:

- `apim.anonymous.json`: API works without auth
- `apim.subscription.json`: API requires a subscription key
- `apim.oidc.jwt-only.json`: API requires a bearer token but not a subscription
- `apim.oidc.subscription.json`: API requires both a bearer token and a subscription key

This isolates the auth differences because only the config changes.

### `compose.hello.yml`

This overlay does two jobs:

- adds the `hello-api` container
- points `apim-simulator` at the chosen hello APIM config

The key line is:

```yaml
APIM_CONFIG_PATH: ${HELLO_APIM_CONFIG_PATH:-/app/examples/hello-api/apim.anonymous.json}
```

That is what lets the `make` targets switch auth modes without editing files.

### `compose.hello.otel.yml`

This adds OTLP exporter settings for the backend so `hello-api` emits logs,
traces, and metrics into the same LGTM stack as the gateway.

### `scripts/smoke_hello.py`

This is the repeatable proof layer. It supports:

- `anonymous`
- `subscription`
- `oidc-jwt`
- `oidc-subscription`

It should be the first thing you update when you change the hello example or
copy it into a new service.

## How To Adapt The Scaffold Into A New API

### Step 1: Copy The Example

Copy `examples/hello-api/` to your new service folder under `examples/`.

Typical rename targets:

- `hello-api` service name
- route names
- product names
- subscription names
- response payloads

Do not start by writing brand-new files from scratch. Copy the working example
first, then change one thing at a time.

### Step 2: Change The Backend Behavior

Edit the backend file:

- rename `SERVICE_NAME`
- rename the route handlers
- replace `/api/hello` with your real business route
- keep `/api/health`
- keep the OTEL helper usage unless you have a strong reason not to

Keep the shape simple until routing works through APIM.

### Step 3: Update The Compose Overlay

Copy `compose.hello.yml` to a new overlay and update:

- backend service name
- Dockerfile path
- image name
- default `APIM_CONFIG_PATH`
- any healthcheck path if your backend health route changes

Keep the backend on `expose`, not `ports`, unless the backend is intentionally
meant to be called directly.

### Step 4: Choose The Auth Pattern

Pick exactly one first:

- anonymous for API bring-up
- subscription-only for product access control
- JWT-only for identity-driven APIs without APIM subscriptions
- subscription plus JWT when you need both product access and identity

The hello example shows all four. Use those JSON files as templates rather than
inventing a new config shape.

### Step 5: Keep The Verification With The Service

Copy `scripts/smoke_hello.py` to a new smoke script when the service becomes
real enough to keep.

At minimum, keep:

- one success case
- one missing-auth case
- one wrong-auth case when applicable

If humans will use the API, also add Bruno, HAR, or a browser demo as the
service grows.

## Manual Checks By Auth Mode

### Anonymous

```bash
curl http://localhost:8000/apim/health
curl http://localhost:8000/api/health
curl 'http://localhost:8000/api/hello?name=team'
```

Good result:

- all three return `200`

### Subscription-only

Success:

```bash
curl \
  -H "Ocp-Apim-Subscription-Key: hello-demo-key" \
  http://localhost:8000/api/hello?name=subscription
```

Missing key:

```bash
curl http://localhost:8000/api/health
```

Invalid key:

```bash
curl \
  -H "Ocp-Apim-Subscription-Key: hello-demo-key-invalid" \
  http://localhost:8000/api/health
```

Good result:

- success returns `200`
- missing key returns `401`
- invalid key returns `401`
- success includes `x-hello-policy: applied`

### JWT-only

```bash
TOKEN=$(uv run python scripts/get_keycloak_token.py)

curl \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/api/hello?name=oidc
```

Good result:

- valid token returns `200`
- missing token returns `401`

### Subscription Plus JWT

```bash
TOKEN=$(uv run python scripts/get_keycloak_token.py)

curl \
  -H "Authorization: Bearer $TOKEN" \
  -H "Ocp-Apim-Subscription-Key: hello-demo-key" \
  http://localhost:8000/api/hello?name=oidc
```

Good result:

- valid token plus valid subscription returns `200`
- missing bearer returns `401`
- missing subscription still fails

## OTEL Standard

The hello scaffold already follows the repo's OTEL standard:

- backend instrumentation uses `app/telemetry.py`
- the backend emits OTLP to LGTM with env vars
- the gateway and backend share the same local OTEL contract

That matters because the gateway and backend can share one local OTEL contract
without extra per-service wiring.

When teaching or reviewing, make these checks:

- logs appear in Loki
- traces appear in Tempo
- metrics appear in Prometheus
- both `apim-simulator` and your backend service appear in Grafana

For a richer backend observability shape, study:

- `examples/todo-app/api-fastapi-container-app/main.py`

## Definition Of Done

Do not stop at "the route exists."

For a new API, aim for all of these:

- `GET /api/health` works through APIM
- one business route works through APIM
- the intended auth mode is proven
- at least one failure mode is proven
- a smoke script exists
- OTEL signals are visible when the service is run with LGTM

## Read Next

- Checked-in example: `examples/hello-api/README.md`
- Guided onboarding: [`APIM-TRAINING-GUIDE.md`](./APIM-TRAINING-GUIDE.md)
- Team delivery guide: [`APIM-TEAM-PLAYBOOK.md`](./APIM-TEAM-PLAYBOOK.md)
- OTEL signals appear if the service is important enough to instrument now
- the route has a short usage note in docs

## Step 10: Borrow The Repo’s Existing Proof Tools

Use these depending on the audience:

- `curl` for quick route proof
- smoke scripts for repeatable checks
- Bruno for saved request flows
- Proxyman or HAR when browser behavior matters
- `/apim/trace/{id}` for APIM-specific explanation
- Grafana for logs, traces, and metrics

## Read Next

- Team delivery patterns: [`APIM-TEAM-PLAYBOOK.md`](./APIM-TEAM-PLAYBOOK.md)
- Conceptual onboarding: [`APIM-TRAINING-GUIDE.md`](./APIM-TRAINING-GUIDE.md)
