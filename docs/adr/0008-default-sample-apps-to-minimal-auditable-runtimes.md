# ADR 0008: Default sample apps to minimal auditable runtimes

## Status

Accepted

## Context

This repo is a learning workspace. A developer may clone it on a workstation
and inspect or run a sample app. The default app path should not require `npm
install`, a large transitive frontend dependency graph, or Python package
installation when the app behavior can be expressed with platform primitives.

`subnetcalc` had several useful teaching variants, but its default path had
drifted toward Vite/React/FastAPI dependency graphs. Those variants are useful
for comparison, but they are a poor default for a low-risk sample app.

## Decision

Default sample app implementations should use vanilla platform capabilities
unless a dependency is intentionally selected and documented.

For `subnetcalc` and `sentiment`, the default implementation is a Go codebase
that builds one small image and runs as two microservices:

- `RUNTIME_ROLE=frontend` serves vanilla static assets and proxies `/api/*`.
- `RUNTIME_ROLE=backend` serves the subnet API and validates OIDC bearer tokens.

The subnetcalc backend uses Go stdlib for HTTP, JSON, static serving, reverse
proxying, subnet calculation, and health checks. Its one intentional backend
dependency is `github.com/coreos/go-oidc/v3/oidc`, because JWT signature,
issuer, audience, expiry, discovery, and JWKS validation are security-sensitive
and should not be handwritten.

The sentiment backend uses only Go stdlib in the default path. It keeps the API
contract for comments and classification but uses deterministic lexicon
classification instead of loading a model dependency tree.

The default Docker Compose path runs separate frontend and backend services
from the same image. This keeps the microservice topology visible while
avoiding two dependency graphs and two build systems.

The APIM simulator keeps its Python backend, but its default operator console
is static HTML, CSS, and vanilla JavaScript served from nginx. It no longer
uses React, Vite, TypeScript, or npm in the shipped console path.

The APIM todo demo frontend is also static HTML, CSS, and vanilla JavaScript
served from nginx. The previous Astro package root was removed; the directory
name remains only to avoid unnecessary compose and documentation path churn.

The local IDP core keeps the same portal API contract, but its default shipped
runtime is now a Go stdlib server. The previous FastAPI implementation stays
in-tree as a compatibility reference while the platform image builds from
`apps/idp-core/app-go`.

Backstage is the explicit exception. Portal demonstrates Backstage as a product,
so its Yarn and plugin dependency graph is intentional and resource-gated
rather than converted into a no-dependency sample app.

The Platform MCP server is another narrow exception: the MCP protocol SDK is
kept because it owns Streamable HTTP and Inspector compatibility. App-owned
network calls should use the standard library unless a separate client
dependency becomes justified.

The smaller `apps/idp-mcp` adapter remains dependency-free and uses Python
stdlib JSON and `urllib.request` directly.

## Consequences

- `apps/subnetcalc/app-go` is the default subnetcalc runtime.
- `apps/sentiment/app-go` is the default sentiment runtime.
- `apps/apim-simulator/ui` is a static nginx-served operator console.
- `apps/idp-core/app-go` is the default portal API runtime.
- `apps/backstage` is a documented Portal exception, not a sample-app template.
- `apps/platform-mcp` keeps the MCP SDK as an intentional protocol dependency.
- `apps/idp-mcp` remains dependency-free.
- `make -C apps/subnetcalc test` verifies the default Go two-service compose
  path.
- `make -C apps/sentiment test` verifies the default Go two-service compose
  path through the existing edge proxy.
- Legacy FastAPI, Flask, Vite, React, SWA, Node/SST, and APIM variants are
  compatibility examples until they are removed or moved behind explicit legacy
  targets.
- The Kubernetes image catalog now builds the active subnetcalc and sentiment
  workload images from the Go app roots. Subnetcalc publishes technology-neutral
  image names, `subnetcalc-api` and `subnetcalc-frontend`, so the default Go
  runtime is not described as FastAPI or Vite in registry metadata.
- Subnetcalc auth remains server-side: `/api/whoami` accepts a bearer token and
  exposes only selected safe claims.
