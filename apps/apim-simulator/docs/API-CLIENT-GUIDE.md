# API Client Guide

Use this guide when you want saved request flows against the simulator instead
of ad hoc `curl` commands.

This repo ships Bruno and Postman collections for the todo example. The Bruno
collection remains the git-first baseline; the Postman collection mirrors the
same request flow for teams that already standardize on Postman.

## When To Use Which Tool

- Use `curl` for one-off checks and docs snippets.
- Use Bruno when you want request files in git and CLI-friendly execution.
- Use Postman when your team already standardizes on Postman workspaces and collections.
- Use Proxyman or the HAR capture when browser behaviour is the question.

## Fastest Stack For Saved Request Flows

Bring up the todo stack first:

```bash
make up-todo
```

Or use the OTEL-backed variant if you also want Grafana:

```bash
make up-todo-otel
```

The request flow below assumes:

- APIM base URL: `http://127.0.0.1:8000`
- frontend origin: `http://127.0.0.1:3000`
- valid subscription key: `todo-demo-key`
- invalid subscription key: `todo-demo-key-invalid`

## Bruno

### What The Repo Already Ships

The Bruno collection lives under:

- [`examples/todo-app/api-clients/bruno/`](../examples/todo-app/api-clients/bruno/)

The local environment file is:

- [`examples/todo-app/api-clients/bruno/environments/local.bru`](../examples/todo-app/api-clients/bruno/environments/local.bru)

It defines:

- `apimBaseUrl`
- `frontendOrigin`
- `subscriptionKey`
- `invalidSubscriptionKey`

Install Bruno with one of the official options before opening the collection:
[Bruno installation options](https://docs.usebruno.com/get-started/bruno-basics/download#installation-options).

### Open The Collection In Bruno

1. Open Bruno.
2. Load [`examples/todo-app/api-clients/bruno/`](../examples/todo-app/api-clients/bruno/) as a collection.
3. Select the `local.bru` environment.
4. Run the requests in order.

The request order matters because request `06-create-todo.bru` stores
`createdTodoId`, and later requests use it.

### Run It From The CLI

From the repo root:

```bash
make test-todo-bruno
```

That runs the checked-in collection with a generated environment file. If the
todo stack is running on a slotted ingress, pass the same slot:

```bash
make test-todo-bruno STACK_SLOT=2
```

### What The Collection Verifies

| Request | Purpose |
| --- | --- |
| `01-health-through-apim.bru` | Valid subscription through APIM, plus APIM proof headers |
| `02-cors-preflight.bru` | Browser-style CORS preflight against APIM |
| `03-missing-subscription-key.bru` | Missing key returns `401` |
| `04-invalid-subscription-key.bru` | Invalid key returns `401` |
| `05-list-todos.bru` | Authenticated list request through APIM |
| `06-create-todo.bru` | Create request plus captured `createdTodoId` |
| `07-toggle-created-todo.bru` | Update request using stored todo id |
| `08-list-after-toggle.bru` | Final state check for the created todo |

### Point Bruno At A Different Ingress

Edit only the environment variables. Do not rewrite the request files unless
the API contract changes.

Typical changes:

- `apimBaseUrl`
- `frontendOrigin`
- `subscriptionKey`

## Postman

### What The Repo Already Ships

The Postman collection lives under:

- [`examples/todo-app/api-clients/postman/todo-through-apim.postman_collection.json`](../examples/todo-app/api-clients/postman/todo-through-apim.postman_collection.json)

The local environment file is:

- [`examples/todo-app/api-clients/postman/local.postman_environment.json`](../examples/todo-app/api-clients/postman/local.postman_environment.json)

It defines:

- `apimBaseUrl`
- `frontendOrigin`
- `subscriptionKey`
- `invalidSubscriptionKey`
- `createdTodoId`
- `createdTodoTitle`

### Open The Collection In Postman

1. Import `todo-through-apim.postman_collection.json`.
2. Import `local.postman_environment.json`.
3. Select the local environment.
4. Run the requests in order or run the whole collection.

The request order matters because `06 Create Todo` stores `createdTodoId`, and
later requests use it.

### Run It From The CLI

From the repo root:

```bash
make test-todo-postman
```

For a slotted stack, use the same slot override:

```bash
make test-todo-postman STACK_SLOT=2
```

### What The Collection Verifies

If you are not using the checked-in local environment file, create an
environment with these variables:

| Variable | Value |
| --- | --- |
| `apimBaseUrl` | `http://127.0.0.1:8000` |
| `frontendOrigin` | `http://127.0.0.1:3000` |
| `subscriptionKey` | `todo-demo-key` |
| `invalidSubscriptionKey` | `todo-demo-key-invalid` |
| `createdTodoId` | leave blank initially |
| `createdTodoTitle` | leave blank initially |

For the same coverage as Bruno, the Postman collection verifies:

- valid subscription requests return `200` or `201`
- missing and invalid subscription key requests return `401`
- response headers include `x-todo-demo-policy: applied`
- response headers include `x-apim-simulator`
- the final list shows the created todo in the expected state

### Point Postman At A Different Ingress

Edit only the environment variables. Do not rewrite the request definitions
unless the API contract changes.

Typical changes:

- `apimBaseUrl`
- `frontendOrigin`
- `subscriptionKey`

## When Bruno Or Postman Are Not Enough

Use Proxyman or the HAR file when the issue is browser-specific:

- [`examples/todo-app/api-clients/proxyman/todo-through-apim.har`](../examples/todo-app/api-clients/proxyman/todo-through-apim.har)

Regenerate the HAR with:

```bash
make export-todo-har
```

Use the APIM trace endpoint when you need per-request gateway detail:

```bash
curl -i \
  -H "x-apim-trace: true" \
  -H "Ocp-Apim-Subscription-Key: todo-demo-key" \
  http://localhost:8000/api/health
```

Then fetch the trace with the returned `x-apim-trace-id`.
