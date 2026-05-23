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

## Interrupted scan state

The last scan was looking for remaining app-local low-level behaviour:

```bash
rg -n "strings\\.TrimRight|strings\\.TrimSuffix|strings\\.TrimSpace\\(.*URL|http\\.Client\\{Timeout|&http\\.Client\\{Timeout|func .*JSON|func .*Error|func .*CORS|func .*Health|func .*Status|func .*Default|window\\.[A-Z0-9_]+_CONFIG \\|\\| \\{\\}|innerHTML|insertAdjacentHTML" apps/*/app/internal/app apps/*/app/internal/app/web apps/shared -g '*.go' -g '*.js'
```

Notable remaining hits:

- `apps/chatgpt-sim/app/internal/app/server.go`
  - several URL construction paths use `strings.TrimRight` and
    `strings.TrimSuffix`.
  - Some are legitimate path-building logic, not simple normalization.
  - Good next candidate: `oidcAuthority` in runtime config still uses
    `strings.TrimRight(s.cfg.OIDCIssuer, "/")` and can likely move to
    `apphttp.NormalizeURL(...)`, matching subnetcalc.
- `apps/chatgpt-sim/app/internal/app/server.go`
  - `PublicBaseURL`, MCP metadata URL, OIDC metadata, and OAuth route config
    normalization are more domain-specific. Do not blindly replace all of these
    with `NormalizeURL`; inspect behaviour and tests first.
- `apps/idp-core/app/internal/app/server.go`
  - local `writeError` remains because the payload shape is `{"detail": ...}`,
    not the canonical `{"error": ...}` used by `apphttp.WriteError`.
    Do not change without deciding the Portal API contract should change.
- `apps/platform-mcp/app/internal/app/server.go`
  - local JSON-RPC error writer remains protocol-specific. Do not replace with
    normal HTTP JSON error helpers.
- `apps/shared/appshell/app-shell.js`
  - `template.innerHTML` appears inside the shared shell. This is not app-local
    duplication. Treat separately if doing browser-hardening work.

## Suggested next vertical slice

Best next slice:

1. Add a ChatGPT Sim runtime config regression showing `OIDCIssuer` with
   trailing slashes emits a normalized `oidcAuthority`.
2. Update `apps/chatgpt-sim/app/internal/app/server.go` to use
   `apphttp.NormalizeURL(s.cfg.OIDCIssuer)` for that one runtime config field.
3. Add or update source regression to forbid
   `strings.TrimRight(s.cfg.OIDCIssuer, "/")`.
4. Run:

```bash
make -C apps chatgpt-sim-test
make -C apps js-check
bats tests/app-layout-consistency.bats
bats tests/validate-app-runtime-surfaces.bats
git diff --check -- apps/chatgpt-sim/app/internal/app/server.go apps/chatgpt-sim/app/internal/app/server_test.go
```

This is aligned with the current architecture direction and low risk because it
matches the subnetcalc cleanup.

## Larger unfinished work

Before considering the goal complete, audit these explicitly:

- Every lightweight app default path is Go-first and dependency-minimal.
- Shared modules used by app `go.mod` files are copied into Docker build
  contexts and compose/Kubernetes image workflows.
- No lightweight app reintroduces npm, Vite, React, npm-installed TypeScript, or
  Python dependencies in the default path.
- ChatGPT Sim can reach the running oMLX endpoint through the intended local
  URL and emits traces that appear in Langfuse.
- Langfuse-related apps appear correctly in Backstage/catalog inventory and the
  Grafana Platform Launchpad tiles.
- App runtime surfaces avoid unclear `unknown` states where a more explicit
  label such as `unavailable`, `missing`, or `not configured` is appropriate.
- Frontend changes remain HTML, CSS, and vanilla JavaScript only, and are
  checked with `make -C apps js-check`.

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

## Worktree warning

The worktree is heavily dirty and includes many changes from this long session
and possibly user edits. Do not revert unrelated files. Before each new slice,
inspect the files you intend to touch and use `git diff -- <files>` to separate
the current slice from earlier changes.

