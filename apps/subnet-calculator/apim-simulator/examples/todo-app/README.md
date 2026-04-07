# Todo App Example

This example is the smallest full-stack app in the repository that proves the
browser-facing APIM path:

`Browser -> Astro frontend -> apim-simulator -> FastAPI todo API`

It is intentionally container-first and environment-configured so the frontend,
gateway, backend, and OTEL stack can be exercised together with one set of
local commands.

If you want the APIM model first, read
[`docs/APIM-TRAINING-GUIDE.md`](../../docs/APIM-TRAINING-GUIDE.md) before
diving into the example details here.

## Local stack

```bash
make up-todo
make up-todo-otel
make smoke-todo
make test-todo-e2e
make test-todo-bruno
make test-todo-postman
make export-todo-har
make down
```

The browser entrypoint is `http://localhost:3000`. The APIM gateway is
`http://localhost:8000`.

`make up-todo-otel` adds LGTM on `http://localhost:3001` and exports OTEL
telemetry from both the gateway and the toy FastAPI backend over OTLP HTTP.
The todo UI exposes direct Grafana links so a browser user can move from a
real task interaction into the OTEL dashboard without leaving the app.

Run `make verify-todo-otel` after the stack is up if you want a quick check
that Prometheus, Loki, and Tempo all see the expected APIM and todo signals.

## External client artifacts

- Bruno collection: `examples/todo-app/api-clients/bruno/`
- Postman collection: `examples/todo-app/api-clients/postman/`
- Proxyman HAR capture: `examples/todo-app/api-clients/proxyman/todo-through-apim.har`

The Bruno and Postman local environment files default to localhost, but the
base URL and subscription key are just variables, so the same collections can
be pointed at a Kubernetes ingress later without changing the request
definitions.

`make export-todo-har` regenerates the HAR from the currently running stack so
the Proxyman import reflects real requests and responses, including APIM proof
headers and the 401 auth cases.
