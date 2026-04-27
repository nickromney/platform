# ADR 0005: Vendor APIM simulator as a supporting context runtime

- Status: Accepted (retrospective)
- Recorded: 2026-04-21

## Context

`apim-simulator` is not a native in-repo domain that grew inside `platform`.
It existed as a standalone repo with its own release flow, docs, tests, and
runtime shapes.

Inside `platform`, only the `subnetcalc` path needs a narrow APIM-shaped
runtime. Later history therefore moved from carrying a broad in-repo copy
toward a smaller vendored subset and explicit vendoring metadata.

## Decision

Keep `apim-simulator` authoritative in its own repo and vendor only the narrow
runtime subset needed by `platform`.

Treat the vendored subtree as:

- a supporting context for the `subnetcalc` path
- an anticorruption and mediation layer at the boundary
- upstream-owned code that should be refreshed by vendoring, not edited in
  place as if it were a native domain module

## Consequences

- The `platform` repo keeps a runnable APIM-mediated path without inheriting
  the entire upstream development surface.
- Upstream-first changes stay possible because the standalone repo remains
  authoritative.
- The vendored subtree remains intentionally narrow: runtime package,
  contracts, lockfiles, metadata, and Dockerfile, not upstream tutorials,
  tests, UI, or examples.
- DDD-wise, APIM stays a supporting context instead of becoming confused with
  the `subnetcalc` domain core.
- Stage-specific identity wiring belongs in the platform manifests that run
  APIM, not in the APIM simulator domain. For example, Kubernetes stage `900`
  configures the Keycloak issuer and `apim-simulator` resource audience, while
  other deployments can supply different OIDC values or run without Keycloak.
- The env-driven APIM fallback config is provider-neutral: anonymous local
  mode needs no identity provider, and non-anonymous OIDC mode requires an
  explicit issuer, audience, and JWKS URI.

## Evidence

- [apps/subnetcalc/apim-simulator.vendor.json](../../apps/subnetcalc/apim-simulator.vendor.json)
- [apps/subnetcalc/README.md](../../apps/subnetcalc/README.md)
- [docs/ddd/contracts.md](../ddd/contracts.md)
- Current history: `e8230c5` introduced vendoring in `platform`; `548c260`
  narrowed the subtree further into the current runtime-oriented shape.
