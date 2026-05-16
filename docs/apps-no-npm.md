# Sample Apps Without npm Dependency Sprawl

## Decision

Sample apps should default to source that a developer can inspect and run
without installing npm dependency trees. A sample app may use zero, one, or two
carefully chosen dependencies when the dependency buys a real security or
platform capability that should not be handwritten.

For `subnetcalc`, the default runtime is now:

```text
Codebase: apps/subnetcalc/app-go
Local compose image: subnetcalc-go
Platform images: subnetcalc-api, subnetcalc-frontend
Frontend microservice: RUNTIME_ROLE=frontend
Backend microservice: RUNTIME_ROLE=backend
Frontend implementation: embedded vanilla HTML, CSS, and JavaScript
Backend implementation: Go stdlib net/http
Intentional dependency: github.com/coreos/go-oidc/v3/oidc
Runtime image: Alpine, non-root, read-only compose root filesystem
```

The frontend and backend remain separate microservices in compose. They can be
built from the same codebase and image; the role is selected at runtime. The
frontend role serves static assets and proxies `/api/*` to `BACKEND_URL`. The
backend role exposes the subnet API and `/api/whoami`.

The frontend source remains plain static files. The Go frontend role is a
container delivery adapter for compose and kind, not a requirement for hosting.
`make -C apps/subnetcalc/app-go static-dist` copies the same HTML, CSS, and
JavaScript into `.run/frontend-static/` for S3, Azure Storage static website, or
CDN-style deployments behind a gateway that provides `/api/*`.

The legacy FastAPI, Flask, Vite, React, SWA, and APIM demo variants remain in
the tree for now as compatibility examples, but they are no longer the default
subnetcalc path. They should be retired or moved behind clearly named legacy
targets once Kubernetes and documentation wiring have caught up.

The Gitea image workflow follows the same default: it builds `app-go` once and
pushes `subnetcalc-api` and `subnetcalc-frontend` from that shared runtime. It
no longer builds the deprecated FastAPI, APIM simulator, React, or Vite
examples as part of the app's default image pipeline, and the active image names
do not carry deprecated implementation names.

For `sentiment`, the default runtime now follows the same pattern:

```text
Codebase: apps/sentiment/app-go
Frontend microservice: RUNTIME_ROLE=frontend
Backend microservice: RUNTIME_ROLE=backend
Frontend implementation: embedded vanilla HTML, CSS, and JavaScript
Backend implementation: Go stdlib net/http with deterministic lexicon sentiment classification
Intentional dependency: none
Runtime image: Alpine, non-root, read-only compose root filesystem
```

The historical Node/Hugging Face SST API and Vite auth UI remain in-tree for
comparison and for any future model-backed experiment, but the default compose
and Kubernetes image catalog build from `apps/sentiment/app-go`.

`make -C apps/sentiment/app-go static-dist` provides the same static artifact
option for the sentiment UI. The Go frontend role remains useful for the local
two-microservice container demo because it supplies the `/api/*` proxy without
nginx.

The Gitea image workflow now builds `app-go` once and pushes both
`sentiment-api` and `sentiment-auth-ui` from that shared runtime. The nested
legacy workflows under the old Node API and Vite UI directories are retained as
deprecated examples, not as the default app build.

## Current Subnetcalc Verification

```bash
make -C apps/subnetcalc/app-go test
make -C apps/subnetcalc test
make -C apps/sentiment/app-go test
make -C apps/sentiment test
```

The app-local compose tests build the tiny runtime image, start the two compose
microservices, check backend health, check the frontend page, check the
frontend-to-backend API proxy, then tear the stack down.

## APIM simulator operator console

`apps/apim-simulator/ui` is now a static operator console: `index.html`,
`styles.css`, and `app.js` are copied directly into the nginx runtime image.
There is no React, Vite, TypeScript, npm install, or frontend build step for
the default console.

The APIM todo demo frontend follows the same shape in
`apps/apim-simulator/examples/todo-app/frontend-astro`: `index.html`,
`styles.css`, and `app.js` are copied directly into nginx, while the tiny Go
runtime-config entrypoint keeps environment-driven `runtime-config.js`
generation. The directory name is retained for compatibility, but Astro,
TypeScript, Playwright, and npm package files have been removed from that
frontend path.

The APIM simulator backend remains the Python/FastAPI simulator. That service
has a larger contract surface and keeps its dependency graph explicit. The
frontend cleanup is still useful because the operator console is just a
management client over the existing `/apim/management/*` API, and the todo
frontend is just a browser client over the APIM-protected todo API.

## IDP core

`apps/idp-core` now ships a Go stdlib implementation from `app-go`. It preserves
the portal API routes for catalog reads, runtime status, and dry-run workflow
planning, while the Docker image copies a single prebuilt binary into an Alpine
runtime. The previous FastAPI implementation remains in-tree as a deprecated
compatibility reference.

## Portal exception

`apps/backstage` is intentionally dependency-heavy because it demonstrates
Backstage itself. It stays in-tree, but it is not the template for lightweight
sample apps and remains gated out of constrained local profiles. The companion
`apps/idp-sdk` package is dependency-free and wraps browser-native `fetch`.

## Platform MCP

`apps/platform-mcp` keeps the MCP protocol SDK as an intentional dependency.
The server must remain compatible with Streamable HTTP MCP clients and the MCP
Inspector, so replacing that protocol layer with handwritten JSON-RPC is out of
scope for the no-dependency pass. App-owned HTTP calls and the smoke client use
the Python standard library instead of a separate HTTP client dependency.

`apps/idp-mcp` is the smaller Portal API MCP adapter and already has zero
runtime dependencies. It uses Python stdlib JSON and `urllib.request` directly.

## Original Conversion Brief

The following brief is preserved as the starting design input.

## Goal

Convert the existing subnet calculator proof of concept from:

```text
Frontend: Vite + TypeScript
Backend: Python + FastAPI

to:

Frontend: plain HTML + CSS + vanilla JavaScript
Backend: Go stdlib HTTP server
Auth: Keycloak or Dex via OIDC
JWT validation: github.com/coreos/go-oidc/v3/oidc

The result should keep the same user-facing behaviour while removing npm, Vite, TypeScript, Python package dependencies, and FastAPI.

Conversion Requirements
Frontend

Convert the current Vite/TypeScript frontend into static files:

frontend/
  index.html
  style.css
  app.js

Requirements:

no npm
no Vite
no TypeScript
no build step
no frontend framework
use browser-native fetch
preserve existing UI behaviour
call backend APIs using relative paths where possible

Expected API calls:

await fetch("/api/subnet?cidr=10.0.0.0/24")
await fetch("/api/whoami", {
  headers: {
    Authorization: `Bearer ${token}`
  }
})

The frontend may decode/display non-sensitive claims for UX, but must not be treated as authoritative.

Backend

Convert the FastAPI backend into a Go HTTP API using stdlib net/http.

Suggested structure:

backend/
  go.mod
  main.go

Use one considered dependency only:

github.com/coreos/go-oidc/v3/oidc

Everything else should use Go stdlib.

Endpoints to implement:

GET /healthz
GET /readyz
GET /api/subnet?cidr=<cidr>
GET /api/whoami

/api/subnet should preserve the existing subnet calculator behaviour.

/api/whoami should require a valid bearer token and return selected safe claims:

{
  "sub": "...",
  "preferred_username": "...",
  "email": "...",
  "groups": []
}
Authentication

Use OIDC with either Keycloak or Dex.

Backend configuration should come from environment variables:

OIDC_ISSUER_URL
OIDC_CLIENT_ID

The Go backend must:

extract Authorization: Bearer <token>
validate the JWT using OIDC discovery/JWKS
verify issuer
verify audience/client ID
verify expiry
reject invalid tokens
expose only selected claims via /api/whoami

Do not hand-roll JWT verification unless absolutely necessary.

Containerisation

Replace Python/FastAPI and Node/Vite images with minimal containers.

Backend target:

single Go binary
non-root runtime
small final image

Frontend target:

static file container
no npm install
no build

It is acceptable to serve the static frontend from the same Go binary if simpler.

Kubernetes

Preserve or recreate the Kubernetes deployment for kind.

Expected resources:

Deployment
Service
Ingress
ConfigMap for OIDC settings

The demo should continue to show:

frontend to backend API calls
authenticated vs unauthenticated experience
claims shown after login
platform routing through Kubernetes ingress
Non-Goals

Do not introduce:

React
Vite
npm
TypeScript compilation
FastAPI
Flask
Composer
frontend auth frameworks
large dependency graphs

The purpose of the conversion is to make the demo small, auditable, portable, and low-risk to run on someone else’s machine.

Acceptance Criteria

The converted app should:

run locally in kind
build without npm
build without Python dependencies
expose the same subnet calculator functionality
support OIDC login via Keycloak or Dex
validate JWTs server-side
show different logged-in/logged-out frontend states
be easy to inspect source-to-container
