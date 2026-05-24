# ADR 0009: Treat idpauth as the auth+HTTP integration layer

- Status: Accepted
- Recorded: 2026-05-24

## Context

The `apps/shared/idpauth` package provides shared identity and authentication
primitives for all platform Go apps. It exports:

- `TokenVerifier` — interface for verifying bearer tokens
- `Authenticator` — centralises the bearer-token decision and `CurrentUser`
- `BootstrapVerifier` — startup helper to construct an OIDC verifier
- `Authenticator.Middleware` — HTTP middleware that gates handlers on auth
- `WriteClientPrincipalSession`, `WriteSessionArray` — HTTP response writers
- `BrowserBundle` — HTTP handler serving the shared browser auth bundle

The package already imports `apps/shared/apphttp` for `WriteNoCacheJSON`,
`WriteError`, `NoCacheHeaders`, and `MethodNotAllowed`.

During architecture review (2026-05-24), two questions arose:

1. Should `Authenticator.Middleware` live in `apphttp` rather than `idpauth`,
   since it is HTTP middleware?
2. Should `WriteClientPrincipalSession` and `WriteSessionArray` be moved out of
   `idpauth` into a separate HTTP adapter?

## Decision

Keep `Authenticator.Middleware`, `WriteClientPrincipalSession`,
`WriteSessionArray`, and `BrowserBundle` in `idpauth`.

`idpauth` is the auth+HTTP integration layer for platform apps. It depends on
`apphttp` for low-level HTTP utilities, and that dependency is intentional.
Reversing the import direction — putting auth-aware middleware in `apphttp` —
would create a **circular import**: `idpauth` imports `apphttp`, so `apphttp`
cannot import `idpauth`.

Separating auth concerns from HTTP concerns would require splitting `idpauth`
into two packages:

- `idpauth-domain` (pure: `UserClaims`, `TokenVerifier`, `Authenticator`,
  `AccessPolicy`, `AuthFailure`)
- `idpauth` (integration: imports domain + apphttp, provides Middleware,
  session writers, browser bundle)

That split is architecturally possible but invasive and provides no immediate
benefit. The current single-package shape is the right size for the current
number of apps and the current seam depth.

## Consequences

- `Authenticator.Middleware` belongs in `idpauth`, not `apphttp`.
  Future explorers: **do not re-suggest `apphttp.RequireAuth`** — it would
  create a circular import.
- `WriteClientPrincipalSession` and `WriteSessionArray` stay in `idpauth`.
  They are auth-aware response writers, not generic HTTP utilities.
- If `idpauth` grows substantially — for example, adding a pure domain test
  surface that should not depend on `net/http` — revisit the
  `idpauth-domain` + `idpauth` split at that time.

## Evidence

- [apps/shared/idpauth/idpauth.go](../../apps/shared/idpauth/idpauth.go)
- [apps/shared/apphttp/](../../apps/shared/apphttp/)
- Architecture review 2026-05-24: candidates B and C in
  [docs/plans/architecture-review-20260524.md](../plans/architecture-review-20260524.md)
