# Retrospective ADRs

These records capture architecture decisions that shaped the repo before the
lightweight DDD pass made them explicit.

They are retrospective on purpose:

- the lineage started with the `subnetcalc` app work in October 2025, and the
  local Kubernetes stack was built around that app
- by the time the `platform` repo was created in March 2026, its initial
  commit already contained both the app family and the staged local-cluster
  stack
- later history added `sd-wan/lima`, `kubernetes/lima`, `kubernetes/slicer`,
  status/TUI workflows, and the current DDD glossary
- `apim-simulator` remained a separate repo first, then became a vendored
  runtime subset inside `apps/subnetcalc`

The DDD docs under [`../ddd`](../ddd/README.md) define the current language and
contracts. These ADRs explain why the repo ended up with that shape.

## Records

- [ADR 0001: Treat platform as a local stack operations workspace](./0001-local-stack-operations-workspace.md)
- [ADR 0002: Use cumulative stages and a reference variant](./0002-cumulative-stages-and-reference-variant.md)
- [ADR 0003: Separate app domain cores from delivery, identity, and mediation](./0003-separate-domain-cores-from-supporting-contexts.md)
- [ADR 0004: Converge on DDD language without breaking shipped contracts](./0004-converge-language-freeze-contracts.md)
- [ADR 0005: Vendor APIM simulator as a supporting context runtime](./0005-vendor-apim-simulator-runtime.md)
- [ADR 0006: Treat make, status, and TUI as the operator-facing application service boundary](./0006-operator-application-service-boundary.md)

## How To Read These

- Start with the DDD glossary and context map if you want the current model.
- Read these ADRs if you want the historical rationale behind that model.
- Treat these as accepted records unless a newer ADR explicitly supersedes one.
