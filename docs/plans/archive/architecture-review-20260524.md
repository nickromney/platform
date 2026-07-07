# Architecture Review — apps/ Pass 1 + Loop 2

- Date: 2026-05-24
- Scope: `apps/` Go shared libraries + app servers; `tools/platform-tui`; `apps/idp-mcp`; `apps/shared/appshell`
- Process: `/improve-codebase-architecture` skill — loop 2 complete
- Status: **Complete**

---

## What Was Done

1. Explored `apps/` Go code thoroughly (Explore agent + manual reading of all main.go and server.go files)
2. Read all 8 ADRs and the existing `docs/plans/architecture-deepening-candidates.md`
3. Generated HTML report (opened in browser): `/var/folders/y7/ltslr0t54vv51fv7p_xvjr5c0000gn/T/architecture-review-20260524-100436.html`
4. Ran grilling loop on all 6 initial candidates — all resolved
5. Fixed incidental bug in `apps/idp-core/app/cmd/idp-core/main.go` (debugging comments removed)
6. Updated `docs/plans/architecture-deepening-candidates.md` with apps/ findings (candidates A–D)
7. Ran second-pass Explore agent on `tools/platform-tui`, `apps/idp-mcp`, `apps/shared/appshell`

---

## Grilled and Resolved Candidates

### A. `idpauth.BootstrapVerifier` — STRONG, later implemented in Loop 2

**The duplication:**

```text
subnetcalc/main.go:35-42  │ var verifier idpauth.TokenVerifier
sentiment/main.go:35-42   │ if auth.ShouldVerifyOIDC("frontend") {
chatgpt-sim/main.go:21-27 │     oidcVerifier, err := idpauth.NewOIDCVerifier(...)
apim-simulator/main.go:33 │     if err != nil { log.Fatalf(...) }
                          │     verifier = oidcVerifier
                          │ }
```

**Proposed interface** (to add to `apps/shared/idpauth/idpauth.go`):

```go
// BootstrapVerifier constructs an OIDC verifier when shouldVerify is true and
// the required config fields are present. Returns nil without error when
// shouldVerify is false (e.g. frontend-only role). Fatal log on misconfiguration
// is left to the caller so main.go retains its error-handling style.
func BootstrapVerifier(ctx context.Context, cfg RuntimeAuthConfig, shouldVerify bool) (TokenVerifier, error) {
    if !shouldVerify {
        return nil, nil
    }
    return NewOIDCVerifier(ctx, cfg.OIDCIssuer, cfg.VerifierAudience(), cfg.OIDCJWKSURI)
}
```

**Call sites after:**

- subnetcalc: `verifier, err := idpauth.BootstrapVerifier(ctx, auth, auth.ShouldVerifyOIDC("frontend"))`
- sentiment: same
- chatgpt-sim: `verifier, err := idpauth.BootstrapVerifier(ctx, auth, cfg.AuthMode == "oidc" && cfg.Role == "shell")`
- apim-simulator: `verifier, err := idpauth.BootstrapVerifier(ctx, auth, cfg.OIDC.Issuer != "" && !cfg.AllowAnonymous)`
  (needs adapter since apim uses its own OIDC config struct — minor wrapping required)

---

### B. `idpauth.Authenticator.Middleware` — STRONG, later implemented in Loop 2

**The duplication** (identical in subnetcalc, sentiment, chatgpt-sim `server.go`):

```go
func (s *server) requireAuth(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if _, ok := s.currentUser(w, r); !ok { return }
        next.ServeHTTP(w, r)
    })
}
func (s *server) currentUser(w http.ResponseWriter, r *http.Request) (idpauth.UserClaims, bool) {
    claims, failure := (idpauth.Authenticator{Mode: s.cfg.AuthMode, Verifier: s.verifier}).CurrentUser(r)
    if failure != nil {
        apphttp.WriteError(w, failure.StatusCode, failure.MessageFor(idpauth.AuthFailureMessages{...}))
        return idpauth.UserClaims{}, false
    }
    return claims, true
}
```

**Proposed interface** (to add to `apps/shared/idpauth/idpauth.go`):

```go
// Middleware returns an HTTP middleware that gates handlers on successful
// authentication. On failure it writes an error response using the optional
// custom messages and returns without calling next.
func (a Authenticator) Middleware(msgs AuthFailureMessages) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            _, failure := a.CurrentUser(r)
            if failure != nil {
                apphttp.WriteError(w, failure.StatusCode, failure.MessageFor(msgs))
                return
            }
            next.ServeHTTP(w, r)
        })
    }
}
```

**Critical constraint:** `apphttp` CANNOT import `idpauth` (circular). `idpauth → apphttp` already exists.
`RequireAuth` belongs in `idpauth`, NOT `apphttp`. Future explorers: do not re-suggest `apphttp.RequireAuth`.

**Call site after** (subnetcalc server.go):

```go
auth := idpauth.Authenticator{Mode: cfg.AuthMode, Verifier: verifier}
requireAuth := auth.Middleware(idpauth.AuthFailureMessages{
    MissingBearerToken: "Missing or invalid bearer token",
    InvalidToken:       "Invalid token",
})
// then: mux.Handle("POST /api/v1/...", requireAuth(http.HandlerFunc(s.handler)))
```

`currentUser` for `whoami` stays per-app (it returns claims, not just gates).

---

### C. `idpauth` is an auth+HTTP integration module — accepted design

`idpauth` imports `apphttp` by design. `WriteClientPrincipalSession`, `WriteSessionArray`, `BrowserBundle`
are HTTP handlers inside the auth module. This is intentional, not leakage. Separating would require
splitting into `idpauth-domain` + `idpauth-http` — invasive, no immediate payoff.

**Do not re-suggest** moving HTTP response writing out of `idpauth` without first creating
a pure `idpauth-domain` module.

---

### D. Sentiment store seam — deferred (one adapter = hypothetical seam)

`newStore(cfg)` is called inside `NewServer`. `store` is an unexported struct with no interface.
Tests use `t.TempDir()` for real-but-isolated I/O. Only one adapter exists.
By the "one adapter = hypothetical seam" rule: defer until a second implementation (in-memory, S3) appears.

---

## Bug Fixed

`apps/idp-core/app/cmd/idp-core/main.go` — 5 lines of debugging commentary
(`// Wait, ListenAndServe is still in apphttp in my write_file?` etc.) removed.

---

## Second-Pass Findings (resolved in Loop 2)

### E. `tools/platform-tui` — shallow helpers and missing tests

**Resolved findings:**

- `internal/tui/model.go`: `stageDisplay()` (line ~716) is a **no-op** — returns its argument unchanged. Delete it.
- `internal/tui/model.go`: `appToggleStageSummary()` and `appDefaultOverride()` are each called from exactly one site. Inline them or delete the indirection.
- No tests for `resizeOutputViewport()` dimension calculation (viewport fallback widths/heights at lines ~608-619)
- No tests for `loadWorkflowOptionsFromScript()` error paths (script failures are silently swallowed)

**Lower priority:**

- `cmd/platform-tui/main.go`: `getenv()` and `isTerminal()` are untested private helpers. Inline or delete.
- `clearRunResult()`, `focusPreviewItem()`, `setRunOutput()` are shallow coordinators with no invariant logic. Inline or remove.

**Strength:** Resolved cleanup pass, not structural

---

### F. `apps/idp-mcp/cmd/idp-mcp/main.go` — tool registry consolidation

Tool names appeared **twice** in the old adapter: once in the tool schema list and once in
the dispatch switch. A new tool required editing both places.

**Proposed shape:**

```go
var tools = map[string]mcpTool{
    "platform_status": {
        Description: "...",
        InputSchema: map[string]any{"type": "object", "properties": map[string]any{}},
        Handler: func(ctx context.Context, c *client, args map[string]any) (any, error) {
            return c.platformStatus(ctx)
        },
    },
}
```

Generate tool definitions from the registry values and dispatch from the matching handler.

Also: expand coverage for HTTP request construction and per-tool calls.

**Strength:** Resolved

---

### G. `apps/shared/appshell/` — correctly deep, no candidates

Deletion test passes: deleting appshell would scatter complexity across all 7 apps that use it.
`RuntimeConfigPayload` interface is the right size. `WriteScriptConfigForRequest` pattern is clean.
Private helpers are appropriately private and tested through the public interface.

**Verdict: No candidates.**

---

## Loop 2 — Implemented (2026-05-24)

### A. `idpauth.BootstrapVerifier` — implemented

Added `BootstrapVerifier(issuer, audience, jwksURI string, shouldVerify bool) (TokenVerifier, error)`
to `apps/shared/idpauth/idpauth.go`. Bug found during testing and fixed: the original
implementation returned `NewOIDCVerifier(...)` directly, which would return a non-nil
interface wrapping a typed nil pointer on error (the Go interface-nil trap). Fixed by
explicitly returning `nil, err`. Updated all four main.go files:

- `apps/subnetcalc/app/cmd/subnetcalc/main.go` — removed 6-line OIDC block + `"context"` import
- `apps/sentiment/app/cmd/sentiment/main.go` — same
- `apps/chatgpt-sim/app/cmd/chatgpt-sim/main.go` — same
- `apps/apim-simulator/app/cmd/apim-simulator/main.go` — same

### B. `idpauth.Authenticator.Middleware` — implemented

Added `(Authenticator).Middleware(msgs AuthFailureMessages) func(http.Handler) http.Handler`
to `apps/shared/idpauth/idpauth.go`. Updated three server.go files:

- `apps/subnetcalc/app/internal/app/server.go` — wired `Middleware` in `NewServer`, deleted `requireAuth` method
- `apps/sentiment/app/internal/app/server.go` — same
- `apps/chatgpt-sim/app/internal/app/server.go` — deleted `requireAuth` (was dead code: defined but never called)

### C. ADR 0009 — recorded

`docs/adr/0009-idpauth-is-auth-http-integration-layer.md` records why `Middleware`
belongs in `idpauth` (not `apphttp`) and why `WriteClientPrincipalSession` stays in
`idpauth`. Prevents the circular-import mistake from being re-suggested.

### E. platform-tui `stageDisplay` — implemented

`tools/platform-tui/internal/tui/model.go`: `stageDisplay()` converted from a no-op
(returned its argument unchanged) to a method that looks up stage labels from the
loaded options. Single-call helpers `appToggleStageSummary` and `appDefaultOverride`
were reviewed: both contain non-trivial multi-branch logic; inlining would make call
sites longer without a depth improvement. Kept as-is.

### F. `idp-mcp` tool registry consolidation — implemented

`apps/idp-mcp/cmd/idp-mcp/main.go`: consolidated tool definitions and
tool-call dispatch into a single registry. Adding a tool now requires editing
exactly one place. Added 7 new tests covering: registry/definition alignment,
per-tool dispatch, unknown-tool error, handler callability.
The current Go adapter covers dispatch logic with `go test`.

---

## Files Modified (Loop 2)

| File | Change |
|------|--------|
| `apps/shared/idpauth/idpauth.go` | Added `BootstrapVerifier` + `Authenticator.Middleware` |
| `apps/subnetcalc/app/cmd/subnetcalc/main.go` | Use `BootstrapVerifier`, remove `context` import |
| `apps/sentiment/app/cmd/sentiment/main.go` | Same |
| `apps/chatgpt-sim/app/cmd/chatgpt-sim/main.go` | Same |
| `apps/apim-simulator/app/cmd/apim-simulator/main.go` | Same |
| `apps/subnetcalc/app/internal/app/server.go` | Wire `Middleware` in `NewServer`, delete `requireAuth` |
| `apps/sentiment/app/internal/app/server.go` | Same |
| `apps/chatgpt-sim/app/internal/app/server.go` | Delete dead `requireAuth` |
| `docs/adr/0009-idpauth-is-auth-http-integration-layer.md` | New ADR |
| `apps/idp-mcp/cmd/idp-mcp/main.go` | Consolidate `TOOLS` dict |
| `apps/idp-mcp/cmd/idp-mcp/main_test.go` | Add dispatch/registry tests |
| `apps/idp-mcp/go.mod` | Go module for the MCP adapter |
| `tools/platform-tui/internal/tui/model.go` | Fix `stageDisplay` (no-op → label lookup) |

---

## Loop 3 — Implemented (2026-05-24)

### G. `idp-core` runtime Adapter registry — implemented

Second-pass review found that `apps/idp-core/app/internal/app/server.go`
still constructed the runtime Adapter registry inline and exposed only
`generic_kubernetes`, `kind`, and `lima`. That contradicted the current
Local Stack Operations language where Lima is a first-class local variant,
and it left the registry as a shallow map wrapper with nondeterministic list
order.

Implemented:

- Added `workflow.NewPlatformRuntimeRegistry()` as the single Portal API
  runtime Adapter registry.
- Added the Lima Make-backed runtime Adapter.
- Made `Registry.List()` deterministic by sorting Adapter names.
- Updated Portal API, browser SSO, and DDD/runtime-portability docs to include
  `lima` in the current runtime Adapter set.

Tests added:

- `apps/idp-core/app/internal/workflow/workflow_test.go` proves the registry
  exposes `generic_kubernetes`, `kind`, `lima`, and `lima` in deterministic
  order.
- The existing Portal API runtime test now asserts the same public runtime
  list.

### Remaining Loop 3 Findings

No high or medium recommendations remain from this pass. The remaining known
items are deliberately low/speculative:

- `apps/platform-mcp` tool registry consolidation remains deferred until a
  fourth tool appears.
- `sentiment` store interface remains deferred until a second store Adapter
  exists.
- The terminal TUI minimal no-contract fallback should remain startup-only.

---

## Files Modified (Loop 1 / Session 1)

| File | Change |
|------|--------|
| `apps/idp-core/app/cmd/idp-core/main.go` | Removed 5-line debugging commentary |
| `docs/plans/architecture-deepening-candidates.md` | Added apps/ Pass 1 section (candidates A–D, bug note) |
| `docs/plans/architecture-review-20260524.md` | This file (new) |
