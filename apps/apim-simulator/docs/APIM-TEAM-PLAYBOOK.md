# APIM Team Playbook

Playbook for common delivery tasks in this repository.

Use it when the question is not "what is APIM?" but rather:

- "What files do I change for this kind of work?"
- "How do I validate it before I ask for review?"
- "What proof should I include in the PR?"

If you need the repo-specific APIM model first, start with:

- [`APIM-TRAINING-GUIDE.md`](./APIM-TRAINING-GUIDE.md)
- [`FIRST-DAY-APIM-CHECKLIST.md`](./FIRST-DAY-APIM-CHECKLIST.md)

If you want a copy-paste project template, use:

- [`APIM-STARTER-RECIPE.md`](./APIM-STARTER-RECIPE.md)

## Golden Rules

- Keep the backend private when the gateway is the intended entrypoint.
- Get the route working before you add multiple auth layers.
- Add one positive case and one negative case for any auth or policy change.
- Use the shared OTEL contract where possible so gateway and backend telemetry
  line up without custom per-service wiring.
- Do not claim a route works until you have both request proof and observability
  proof.

## Delivery Pattern

For almost every APIM change, work in this order:

1. Make the backend route work
2. Put APIM in front of it
3. Add auth
4. Add policy behaviour
5. Add observability
6. Add repeatable checks
7. Update docs

If you reverse that order, you usually make debugging harder.

## Common Tasks

### Add A New Backend Behind APIM

Use this when:

- a new service is being introduced
- an existing internal service needs a public APIM API

Touch:

- backend app code under [`examples/`](../examples/) or the appropriate service folder
- backend Dockerfile
- APIM config JSON
- a compose overlay or compose service entry

Usually start from:

- [`examples/hello-api/main.py`](../examples/hello-api/main.py)
- [`examples/hello-api/Dockerfile`](../examples/hello-api/Dockerfile)
- [`examples/hello-api/apim.anonymous.json`](../examples/hello-api/apim.anonymous.json)
- [`examples/todo-app/api-fastapi-container-app/main.py`](../examples/todo-app/api-fastapi-container-app/main.py)
- [`examples/todo-app/api-fastapi-container-app/Dockerfile`](../examples/todo-app/api-fastapi-container-app/Dockerfile)
- [`examples/todo-app/apim.json`](../examples/todo-app/apim.json)

Validation:

- one `curl` request through APIM returns `200`
- the backend is not called directly from the browser
- the backend service is internal-only unless there is a strong reason not to be

PR proof:

- the APIM config snippet
- one successful request example
- one sentence explaining why the backend should be behind APIM

### Add Subscription Protection

Use this when:

- access is controlled per consuming app or client
- you want APIM products/subscriptions without identity yet

Touch:

- `products`
- `subscription`
- API or operation `products`

Required checks:

- valid key returns `200`
- missing key returns `401`
- invalid key returns `401`
- unauthorized product access returns `403` when applicable

Good proof:

- `curl` examples for all three cases
- Bruno coverage if this is a user-facing API
- APIM trace or response header showing the route actually passed through the
  gateway

### Add JWT Or OIDC Protection

Use this when:

- user or workload identity matters
- the route needs scopes, roles, or claims

Touch:

- `allow_anonymous`
- `oidc`
- route `authz`
- possibly product subscription requirements depending on whether the pattern is
  JWT-only or subscription plus JWT

Decide which pattern you want before you code:

- JWT-only: `subscription.required: false` and no subscription-required product
- Subscription plus JWT: `subscription.required: true` and route attached to a
  subscription-required product

Required checks:

- valid token returns `200`
- missing token returns `401`
- wrong role or scope returns `403`
- if subscriptions are also required, missing or invalid subscription still
  fails correctly

Good proof:

- one successful bearer-token request
- one failed request due to authz, not routing
- note whether the route is JWT-only or subscription plus JWT

### Add Route-Level Authorization

Use this when:

- the token is valid, but not every authenticated caller should be allowed

Touch:

- route `authz.required_scopes`
- route `authz.required_roles`
- route `authz.required_claims`

Required checks:

- one token that satisfies the rule returns `200`
- one token that fails the rule returns `403`

Good proof:

- the exact rule you configured
- the token shape you expected
- the negative case you tested

### Add Or Change Policy Behaviour

Use this when:

- the gateway should mutate, reject, throttle, rewrite, or enrich traffic

Touch:

- `policies_xml`
- policy fragments when shared behaviour is intended

Examples:

- add a header with `set-header`
- rewrite a path with `rewrite-uri`
- rate-limit with `rate-limit`
- validate a JWT in policy

Required checks:

- the changed behaviour is visible in a response, trace, or both
- a negative case exists when the policy is supposed to reject requests

Good proof:

- response headers showing the policy took effect
- `/apim/trace/{id}` output for one representative request
- clear statement of whether the policy runs inbound, backend, outbound, or
  on-error

### Add OTEL Observability

Use this when:

- the backend is new
- the route is strategically important
- the service is expected to move between repos

Touch:

- [`app/telemetry.py`](../app/telemetry.py) integration in the backend
- compose OTEL overlay if needed
- dashboard or verification docs when the signal is user-facing

For Python services, prefer the shared helper and copy the shape of:

- [`examples/todo-app/api-fastapi-container-app/main.py`](../examples/todo-app/api-fastapi-container-app/main.py)

Required checks:

- logs visible in Loki
- traces visible in Tempo
- metrics visible in Prometheus
- dashboard or verify script shows the service and route

Good proof:

- `make verify-otel` or `make verify-todo-otel`
- a clear Grafana dashboard or Explore walkthrough when there is no dedicated verifier yet

### Add A Browser-Facing Demo

Use this when:

- humans need to understand the API flow, not just engineers using request tools

Touch:

- frontend runtime config
- frontend text that explains the path
- Playwright e2e coverage
- optional Bruno / HAR artifacts

Required checks:

- a human can complete the flow in the browser
- the browser is visibly calling APIM, not the backend directly
- the flow is covered by Playwright

Good proof:

- `make test-todo-e2e` or equivalent passing
- a direct link from the UI into observability if the example is a teaching tool

## Recommended Validation Stack

Use at least one tool from each column.

| Purpose | Good tools |
| --- | --- |
| Request correctness | `curl`, Bruno, smoke scripts |
| Human flow | browser UI, Playwright |
| APIM-specific explanation | response headers, `/apim/trace/{id}` |
| System-level observability | Grafana, verify scripts |

Do not rely on only one of these.

## PR Checklist

For APIM-related changes, try to include all of these in the PR description:

- what public path changed
- what backend it maps to
- whether auth is anonymous, subscription-only, JWT-only, or both
- one positive test or smoke command
- one negative test command
- one observability proof point
- one doc link if humans are expected to use the flow

## Failure Map

Use this table before you start random changes.

| Status | Most likely meaning | Check first |
| --- | --- | --- |
| `401` | Missing or invalid auth | subscription header, bearer token, product requirements |
| `403` | Authenticated but not allowed | route `authz`, subscription product access |
| `404` | No matching route | `path_prefix`, method, host match |
| `429` | Rate limit or quota | policy XML, trace output |
| `500` | Gateway bug or policy/runtime issue | gateway logs, trace, recent change |
| `502`/upstream failure | Backend unreachable or unhealthy | compose service health, upstream URL |

## Definition Of Done

A normal APIM task is not done until:

- the route works through APIM
- the intended auth mode is proven
- at least one failure mode is proven
- observability is available for the request path
- the docs are good enough for the next teammate

## Read Next

- Training path: [`APIM-TRAINING-GUIDE.md`](./APIM-TRAINING-GUIDE.md)
- Copy-paste service template: [`APIM-STARTER-RECIPE.md`](./APIM-STARTER-RECIPE.md)
