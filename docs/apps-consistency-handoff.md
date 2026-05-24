# Apps consistency handoff

Date: 2026-05-23

## Goal

The active work was to tighten the `apps/` directory around the Go-first,
minimal-dependency direction:

- Keep lightweight apps as Go services with embedded HTML, CSS, and vanilla
  JavaScript.
- Move repeated app behaviour into small shared modules where it creates real
  locality and leverage.
- Keep shared modules copied into app containers when used.
- Avoid new default-path npm, Python, React, Vite, or TypeScript dependency
  graphs for lightweight apps.
- After backend/app consistency improves, make light frontend improvements
  while retaining HTML, CSS, and JavaScript only.

The goal is not complete. Continue only after deciding to resume it.

## Current shared modules

- `apps/shared/apphttp`
  - JSON response helpers.
  - canonical error payload helpers.
  - bounded JSON decoding with trailing-data rejection.
  - CORS helpers.
  - request logging.
  - env parsing helpers.
  - URL normalization.
  - query integer parsing.
  - API proxy helper.
  - standard HTTP client timeout helper.
  - browser health and role-status payload helpers.
- `apps/shared/appshell`
  - shared CSS and JavaScript app shell.
  - static asset registration.
  - favicon and signed-out page helpers.
  - runtime config writer and runtime payload helpers.
  - vanilla browser utilities for runtime config, status rendering, list
    rendering, timing, network path display, selectors, busy buttons, theme
    switching, and signed-out redirect.
- `apps/shared/idpauth`
  - provider-neutral OIDC and gateway-session helpers.
  - browser `idpauth.js` helpers.
  - runtime auth config env mapping.

These are intentionally small, dependency-light seams. Do not add another shared
module unless the deletion test says the complexity would otherwise reappear in
multiple apps.

## Important user concerns already addressed

- `/idpauth.js` should remain provider-neutral OIDC/OAuth2, not Keycloak-only.
  The current direction is compatible with standard OIDC discovery patterns and
  should work with Entra ID if issuer metadata and client config are supplied.
- ChatGPT Sim fallback behaviour was investigated. It can return deterministic
  stub/fallback text when no external LLM is configured. The user wants proof
  that, when oMLX is running, ChatGPT Sim can reach it and traces land in
  Langfuse.
- User wanted local LLM waits to stay under roughly `1000ms` and avoid reaching
  long proxy timeouts. ChatGPT Sim tests currently include bounded timeout
  expectations.
- User noticed `https://llm.127.0.0.1.sslip.io`; that is a helper hostname for
  routing local LLM traffic through the platform gateway shape.
- User questioned BATS running Python. There are Python-backed test helpers in
  the BATS suite; avoid expanding that unless needed.
- User noticed Langfuse-related apps without matching Grafana launchpad tiles.
  There are changes in the platform launchpad and app inventory area, but this
  should be rechecked before claiming complete.
- User asked for a pass to avoid `unknown`. `tests/validate-app-runtime-surfaces.bats`
  currently has a source-tree check for lightweight apps avoiding literal
  `unknown` tokens.

## Recent completed slices

### Shared URL normalization in subnetcalc

Files:

- `apps/subnetcalc/app/internal/app/server.go`
- `apps/subnetcalc/app/internal/app/server_test.go`

Change:

- `oidcAuthority` in runtime config now uses
  `apphttp.NormalizeURL(s.cfg.OIDCIssuer)` instead of app-local
  `strings.TrimRight(...)`.
- Test fixture now passes an issuer with trailing slashes and expects the
  normalized issuer.
- Source regression prevents reintroducing the local OIDC issuer trim.

Verified:

```bash
make -C apps subnetcalc-test
bats tests/app-layout-consistency.bats
bats tests/validate-app-runtime-surfaces.bats
git diff --check -- apps/subnetcalc/app/internal/app/server.go apps/subnetcalc/app/internal/app/server_test.go
```

### Shared string defaulting in idp-core

Files:

- `apps/idp-core/app/internal/app/server.go`
- `apps/idp-core/app/internal/app/server_test.go`

Change:

- Replaced a local `defaultString` helper with `apphttp.StringDefault(...)`.
- Added `TestServerUsesSharedStringDefault`.

Verified:

```bash
make -C apps idp-core-test
bats tests/app-layout-consistency.bats
bats tests/validate-app-runtime-surfaces.bats
git diff --check -- apps/idp-core/app/internal/app/server.go apps/idp-core/app/internal/app/server_test.go
```

### Browser runtime config reading

Files:

- `apps/langfuse-demos/app/internal/app/web/app.js`
- `apps/chatgpt-sim/app/internal/app/web/app.js`
- corresponding app server tests

Change:

- Browser apps now use `readRuntimeConfig(...)` from `PlatformAppShell`.
- Tests forbid old `window.*_CONFIG || {}` fallbacks.

Verified:

```bash
make -C apps langfuse-demos-test
make -C apps chatgpt-sim-test
make -C apps js-check
bats tests/app-layout-consistency.bats
bats tests/validate-app-runtime-surfaces.bats
```

### Shared logout markup

Files:

- `apps/chatgpt-sim/app/internal/app/web/index.html`
- `apps/sentiment/app/internal/app/web/index.html`
- `apps/subnetcalc/app/internal/app/web/index.html`
- corresponding app server tests

Change:

- `logout-btn` uses shared `class="sign-in-link"` markup across apps.

Verified:

```bash
make -C apps subnetcalc-test
make -C apps chatgpt-sim-test
make -C apps sentiment-test
make -C apps js-check
bats tests/app-layout-consistency.bats
bats tests/validate-app-runtime-surfaces.bats
```

### Shared HTTP client and query parsing

Files:

- `apps/shared/apphttp/apphttp.go`
- `apps/shared/apphttp/apphttp_test.go`
- app callers in APIM simulator, Platform MCP, subnetcalc, and sentiment

Change:

- Added `NewHTTPClient(timeout time.Duration)`.
- Added `QueryInt(r, key, fallback)`.
- Replaced small repeated app-local behaviour.

Verified with affected app tests plus the app layout/runtime BATS checks.

### ChatGPT Sim OIDCIssuer normalization source regression

Files:

- `apps/chatgpt-sim/app/internal/app/server_test.go`

Change:

- Added `TestServerUsesSharedOIDCIssuerNormalization` — asserts
  `apphttp.NormalizeURL(s.cfg.OIDCIssuer)` is present and
  `strings.TrimRight(s.cfg.OIDCIssuer` is absent.
  Matches the equivalent regression in subnetcalc.
- The runtime config test at `TestRuntimeConfigIncludesNetworkPathToggle`
  already covered the behaviour (OIDCIssuer with trailing slashes, normalized
  output); the new test guards the implementation path.

Verified:

```bash
make -C apps chatgpt-sim-test
make -C apps js-check
bats tests/app-layout-consistency.bats
bats tests/validate-app-runtime-surfaces.bats
```

## Scan state

The scan for remaining app-local low-level behaviour has been completed:

```bash
rg -n "strings\\.TrimRight|strings\\.TrimSuffix|strings\\.TrimSpace\\(.*URL|http\\.Client\\{Timeout|&http\\.Client\\{Timeout|func .*JSON|func .*Error|func .*CORS|func .*Health|func .*Status|func .*Default|window\\.[A-Z0-9_]+_CONFIG \\|\\| \\{\\}|innerHTML|insertAdjacentHTML" apps/*/app/internal/app apps/*/app/internal/app/web apps/shared -g '*.go' -g '*.js'
```

All remaining hits are either legitimately app-local or have been explicitly
reviewed and left in place:

- `apps/chatgpt-sim/app/internal/app/server.go`
  - `oidcAuthority` now uses `apphttp.NormalizeURL(s.cfg.OIDCIssuer)`.
    Source regression added in `TestServerUsesSharedOIDCIssuerNormalization`.
  - Remaining `TrimRight`/`TrimSuffix` hits are URL path-building logic
    (e.g. `/chat/completions` → `/models` rewrite, MCP metadata URL
    derivation, OAuth route config). Do not replace with `NormalizeURL`.
- `apps/idp-core/app/internal/app/server.go`
  - local `writeError` remains because the payload shape is `{"detail": ...}`,
    not the canonical `{"error": ...}` used by `apphttp.WriteError`.
    Do not change without deciding the Portal API contract should change.
- `apps/platform-mcp/app/internal/app/server.go` and
  `apps/chatgpt-sim/app/internal/app/server.go`
  - Both have identical `writeRPC` / `writeRPCError` one-liners (JSON-RPC
    protocol). They pass the deletion test but are single-line each.
    Consolidating into a shared module is marginal and was consciously
    deferred. Do not replace with normal HTTP JSON error helpers.
- `apps/shared/appshell/app-shell.js`
  - `template.innerHTML` appears inside the shared shell. This is not
    app-local duplication. Treat separately if doing browser-hardening work.

## Suggested next vertical slice

The scan is clean. No further source-level consolidation is immediately
apparent. The remaining item before the goal is complete is runtime
verification:

1. Verify ChatGPT Sim can reach a running oMLX endpoint through the
   intended local URL (`http://llm.127.0.0.1.sslip.io` or
   `http://127.0.0.1:8000`).
2. Confirm traces appear in Langfuse after a chat request.

This requires a running local platform stack and cannot be verified from
source alone.

## Larger unfinished work

Before considering the goal complete, audit these explicitly:

- [x] Every lightweight app default path is Go-first and dependency-minimal.
      Verified: all lightweight app Dockerfiles are Go binary only; no
      npm/Vite/React/Python in any lightweight app build context.
- [x] Shared modules used by app `go.mod` files are copied into Docker build
      contexts and compose/Kubernetes image workflows. Verified: shared modules
      are resolved at Go build time via `replace` directives and compiled into
      the binary before the Docker build step.
- [x] No lightweight app reintroduces npm, Vite, React, npm-installed
      TypeScript, or Python dependencies in the default path. Verified: only
      `backstage` (expected) has npm in its Dockerfile.
- [ ] ChatGPT Sim can reach the running oMLX endpoint through the intended
      local URL and emits traces that appear in Langfuse. Requires a running
      local platform stack — not yet verified from source.
- [x] Langfuse-related apps appear correctly in Backstage/catalog inventory
      and the Grafana Platform Launchpad tiles. Verified: four tiles in
      `terraform/kubernetes/config/platform-launchpad.apps.json` (Langfuse,
      Langfuse Trace Chat DEV, Langfuse Tool Agent DEV, Langfuse Eval Runner
      DEV) plus ChatGPT Sim DEV. Backstage catalog-info.yaml files present for
      both `apps/langfuse-demos` and `apps/chatgpt-sim`.
- [x] App runtime surfaces avoid unclear `unknown` states where a more explicit
      label is appropriate. Verified: source scan clean;
      `tests/validate-app-runtime-surfaces.bats` covers this.
- [x] Frontend changes remain HTML, CSS, and vanilla JavaScript only, and are
      checked with `make -C apps js-check`. Verified: js-check passes.

## Verification habits

Use the smallest focused tests first:

```bash
make -C apps <app>-test
make -C apps shared-apphttp-test
make -C apps shared-appshell-test
make -C apps shared-idpauth-test
make -C apps js-check
bats tests/app-layout-consistency.bats
bats tests/validate-app-runtime-surfaces.bats
```

For compose or cluster behaviour, do not infer success from source tests.
Exercise the actual relevant compose or Kubernetes check.


