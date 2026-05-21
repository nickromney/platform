# APIM Simulator Go Rewrite Notes

<!-- markdownlint-disable MD013 -->

- Status: Draft
- Date: 2026-05-20
- Scope: `apps/apim-simulator`
- Source process: `improve-codebase-architecture`

## Purpose

This note captures the intended shape of a Go rewrite of the local APIM
Simulator. It is a handoff artifact for a later implementation session, not an
implementation record.

The rewrite should preserve the value of the current simulator while reducing
the runtime surface area: one Go binary owns the gateway, management plane,
policy engine, tracing, static operator UI, and CLI/headless surfaces.

## Current Baseline

The current APIM simulator is a standalone project under `apps/apim-simulator`.
It has its own `Makefile`, many compose overlays, Python runtime code under
`app/`, static operator UI under `ui/`, and examples for hello, todo, MCP,
OIDC, edge TLS, AI gateway, Backstage, Key Vault, and OTEL.

The important behaviours to preserve are:

- APIM-shaped gateway routing from configured APIs, operations, routes,
  products, subscriptions, backends, named values, policy fragments, tags,
  users, groups, loggers, and diagnostics.
- Policy execution for the practical local XML subset.
- Auth flows for anonymous, subscription key, JWT/OIDC, scope, role, claim, and
  client-certificate checks.
- Management APIs protected by the tenant key.
- Per-request traces, replay, compatibility reporting, and import tooling.
- Compose-first local workflows for public, private, edge, TLS, OIDC, MCP, AI
  gateway, UI, todo, hello, and OTEL scenarios.
- Static browser surfaces that reveal gateway target, backend target, policy
  decisions, user/auth state where applicable, timings, traces, and network
  hops.

## Architecture Direction

Keep APIM Simulator as its own project, but align it with the lightweight app
direction where that helps:

- Go only for the simulator runtime and first-party examples.
- No Python, TypeScript, Rust, or JavaScript package-manager dependency in the
  shipped runtime.
- Static HTML/CSS/JavaScript for browser surfaces.
- `// @ts-check` plus generated or maintained `.d.ts` declarations for typed
  browser code.
- Biome for standalone lint/format checks and Deno for standalone semantic
  `// @ts-check` JavaScript checks; neither tool is installed through npm in
  the default workflow.
- One Go binary can serve both gateway APIs and the operator UI.
- One Docker image should cover the default gateway and management surface.
- Compose overlays remain scenario-focused, but avoid duplicating app-local
  compose files outside the APIM project.

Target high-level layout:

```text
apps/apim-simulator/
  .gitea/
  app/
    cmd/apim-simulator/
    internal/
      aigateway/
      auth/
      cli/
      config/
      gateway/
      importers/
      management/
      policy/
      telemetry/
      trace/
      web/
    web/
      ui/
        index.html
        app.js
        api-types.d.ts
        styles.css
    Dockerfile
    Makefile
    go.mod
  examples/
  tests/
  compose.yml
  compose.edge.yml
  compose.tls.yml
  compose.oidc.yml
  compose.otel.yml
```

Backstage stays optional and external to the lightweight APIM runtime. If the
Backstage demo remains, it should be treated as a separate product surface with
its own dependency model, not as part of the Go simulator.

## Deep Modules And Seams

### Config Module

Interface:

- Load APIM config from JSON files, environment-rendered paths, and embedded
  examples.
- Validate resource identifiers, routes, backend references, product
  bindings, subscriptions, named values, and policy scopes.
- Return structured diagnostics instead of process-fatal errors where the
  gateway can still expose health/status.

Implementation:

- Standard-library JSON decoding.
- Explicit Go structs with `json` tags.
- No general dynamic map traversal except at the import seam.

### Gateway Runtime Module

Interface:

- Accept an `http.Request`.
- Resolve configured API/route/operation/product/subscription/backend.
- Execute inbound, backend, outbound, and on-error policy phases.
- Return a response plus trace facts.

Implementation:

- Standard-library `net/http`.
- Per-request context carrying correlation ID, matched route, consumer,
  named-value resolver, backend target, policy decisions, timings, and trace
  sinks.

This is the central depth target. Callers should not need to know policy XML,
subscription matching, backend failover, or trace mechanics.

### Policy Module

Interface:

- Parse the supported APIM XML policy subset into executable policy steps.
- Execute steps against the gateway request context.
- Produce typed diagnostics for unsupported or partially supported policy
  features.

Implementation:

- Standard-library `encoding/xml`.
- Golden tests for every currently supported policy example.
- No XPath or expression dependency. Implement only the APIM expression subset
  that the simulator supports.

High-risk area:

- APIM expression compatibility can sprawl. Keep the expression evaluator a
  deliberately small module with its own golden tests and compatibility matrix.

### Auth Module

Interface:

- Validate anonymous, subscription-key, JWT/OIDC, scope, role, claim, and
  client-certificate requirements.
- Return a consumer identity plus failure details suitable for traces and UI.

Implementation:

- Subscription-key auth is local config lookup.
- JWT/OIDC can be implemented with standard-library JSON, base64url, `crypto`,
  and JWK fetch/caching.
- Client certificate checks use standard-library TLS request state.

High-risk area:

- JWT correctness is security-sensitive even for a local simulator. Keep the
  supported algorithms narrow, reject `none`, enforce issuer/audience/time
  checks, and add fixture-based tests for valid, expired, wrong-audience,
  wrong-issuer, and wrong-key tokens.

### Management Module

Interface:

- Expose tenant-key-protected read and mutation endpoints for service state,
  APIs, products, subscriptions, named values, policies, traces, replay, import,
  and compatibility reporting.
- Return schema-shaped JSON responses suitable for typed browser clients.

Implementation:

- Standard-library `net/http`.
- In-memory state with optional config persistence only where the current
  simulator already supports it.
- Reuse the Config, Gateway Runtime, Policy, Trace, and Import modules rather
  than duplicating traversal logic.

### Trace Module

Interface:

- Capture per-request trace records with route, backend, policy, auth, timing,
  response, and error facts.
- Expose recent traces to management APIs and the operator UI.
- Support replay through the same Gateway Runtime module.

Implementation:

- Bounded in-memory ring buffer by default.
- Structured JSON export for CLI/headless inspection.

### Importers Module

Interface:

- Import local APIM-shaped JSON and OpenAPI inputs into the Config module.
- Emit compatibility diagnostics rather than hiding unsupported features.

Implementation:

- JSON OpenAPI support first.
- YAML OpenAPI is the main no-dependency tradeoff. Either defer YAML support,
  require users to pre-convert YAML to JSON, or implement a deliberately small
  YAML adapter with explicit tests. Do not smuggle a dependency in just for
  YAML.

### Browser UI Module

Interface:

- Serve embedded static operator UI.
- Provide typed runtime config and management API contracts.
- Reveal gateway URL, backend target, auth/user facts, policy scope, timings,
  trace IDs, and network hops.

Implementation:

- `// @ts-check` JavaScript.
- `.d.ts` declarations generated from or aligned with Go response types.
- `make frontend-check` runs Biome and Deno against the static operator UI.
- No npm, Yarn, pnpm, Bun, Vite, React, or bundler in the default path.

## CLI And Headless Mode

The Go binary should support browser and headless usage:

- `apim-simulator serve` starts the gateway and management surface.
- `apim-simulator health` probes a configured base URL.
- `apim-simulator config validate --file examples/.../apim.json` validates
  config and prints diagnostics.
- `apim-simulator compatibility --file examples/.../apim.json` prints the
  compatibility report.
- `apim-simulator replay --base-url ... --path ...` runs a replay through the
  management surface.
- `apim-simulator traces --base-url ...` prints recent traces as JSON.

The CLI is an adapter over the same modules as the HTTP server. It should not
contain a second implementation of routing, policy, or import behaviour.

## Container Direction

Use the same lightweight Go image pattern as the canonical apps:

- DHI Go builder image when available.
- Static Go binary.
- Static runtime image such as `dhi.io/static`.
- Non-root user.
- Read-only root filesystem in compose and Kubernetes manifests.
- Explicit writable `tmpfs` or volumes only where required.

A shared Go build container can help if it is treated as a stable build base,
not a runtime dependency. For no-dependency Go apps, most speed comes from:

- BuildKit cache mounts for Go build cache.
- Copying `go.mod` before source when dependencies exist.
- Keeping the DHI Go builder image preloaded.
- Avoiding per-app Node/Python builder images.

## Red/Green TDD Rewrite Plan

### 0. Characterization Contracts

Red tests:

- Add Go rewrite contract tests that describe the current observable APIM
  behaviours before replacing Python.
- Start with HTTP-level golden tests for `/apim/health`,
  `/apim/management/status`, `/apim/management/summary`, gateway proxying,
  subscription-key failures, trace capture, and replay.

Green implementation:

- The current implementation should satisfy these tests or document explicit
  gaps before the Go rewrite starts.

Verification:

```bash
make -C apps/apim-simulator test
make -C apps/apim-simulator compose-smoke
```

### 1. Go Skeleton And Default Gateway

Red tests:

- Go unit tests for config load, `/apim/health`, `/apim/startup`, and direct
  route matching.
- Compose contract test proving the new image starts and exposes health.

Green implementation:

- Add `apps/apim-simulator/app`.
- Implement `serve`, config loading, health, startup, and one anonymous
  gateway route.
- Serve embedded UI assets, even if the UI initially only shows connection
  state.

### 2. Products, Subscriptions, And Auth

Red tests:

- Missing subscription key returns the current APIM-shaped failure.
- Invalid key returns the current APIM-shaped failure.
- Valid key reaches the backend and records consumer facts.
- JWT/OIDC fixture tests cover valid and invalid tokens.

Green implementation:

- Implement product/subscription matching and Auth module.
- Add trace fields for consumer, auth scheme, and failure reason.

### 3. Policy Engine

Red tests:

- Port current policy golden tests to Go.
- Cover inbound, backend, outbound, on-error, transforms, throttling, caching,
  JWT validation, backend selection, and `send-request` where currently
  supported.

Green implementation:

- Implement the Policy module behind a small executable policy interface.
- Keep unsupported features visible in compatibility diagnostics.

### 4. Management Plane

Red tests:

- Tenant-key-required management tests.
- Summary, resources, policy read/write, subscription key rotation, trace list,
  trace detail, and replay tests.

Green implementation:

- Implement management handlers as adapters over Config, Gateway Runtime,
  Policy, and Trace modules.

### 5. Imports And Compatibility

Red tests:

- OpenAPI JSON import fixtures.
- Terraform/OpenTofu show JSON import fixtures.
- Compatibility report golden outputs.

Green implementation:

- Implement Importers module.
- Keep YAML support explicitly deferred unless a no-dependency path is chosen.

### 6. AI Gateway And Examples

Red tests:

- Existing AI gateway smoke behaviours become Go tests or compose smokes.
- Token limit, backend selection, retry/fallback, and trace headers are
  covered.

Green implementation:

- Implement AI Gateway as an adapter behind the same Gateway Runtime module.
- Rewrite first-party mock backends to Go where feasible.

### 7. Static UI With Checked JavaScript

Red tests:

- Add a JS type-check target for the operator UI.
- Add browser or DOM-smoke coverage for connection, summary render, replay,
  traces, and theme switching.

Green implementation:

- Port the operator UI to the typed vanilla JS pattern.
- Expose runtime config and management response types through `.d.ts`.
- Show gateway, backend, timing, trace, hop, and auth/user facts in the UI.

### 8. Compose And Platform Integration

Red tests:

- Compose smoke for default public gateway.
- Compose smokes for UI, edge, TLS, OIDC, MCP, AI gateway, and OTEL as each
  path is ported.
- Image catalog/preload tests showing Python runtime images are no longer
  required by APIM.

Green implementation:

- Update Dockerfile, compose files, app image catalog, preload lists, and
  Kubernetes APIM manifests.
- Keep scenario overlays, but remove duplicate or dead compose surfaces.

Final verification after Docker login and local-runtime cleanup:

```bash
make -C apps/apim-simulator test
make -C apps/apim-simulator compose-smoke
make -C apps/apim-simulator compose-smoke-sso
make -C apps compose-smoke-apim-simulator
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind check-health
```

## Non-Goals

- Do not turn APIM Simulator into Backstage or Portal.
- Do not make the browser UI own gateway or policy behaviour.
- Do not introduce a frontend framework for the operator UI.
- Do not add package-manager installs to the default runtime path.
- Do not silently drop APIM behaviours. Unsupported or deferred behaviours must
  appear in compatibility diagnostics.
- Do not force APIM into the exact lightweight app layout if that harms its
  standalone project workflow. Align where useful; keep the project coherent.
