# ADR 0001: Treat platform as a local stack operations workspace

- Status: Accepted (retrospective)
- Recorded: 2026-04-21

## Context

The lineage behind `platform` did not start as a greenfield platform
workspace.

The earlier work started with the `subnetcalc` app in October 2025. The local
Kubernetes stack was then built around that app so it could be exercised in a
repeatable local platform shape.

By the time the `platform` repo itself was created in March 2026, its initial
state already combined two concerns:

- a substantial `apps/subnet-calculator` application family
- a staged `kubernetes/kind` local-cluster stack

From there, the repo kept expanding around operator workflows:

- more local variants under `kubernetes/`
- root `make`, `status`, and `tui` surfaces that route operators into the
  right local workflow

The current DDD docs now say this plainly: the repo's primary concern is local
stack operation on one machine, while the sample apps remain separate bounded
contexts.

## Decision

Treat the repo root as the `Local Stack Operations` workspace and bounded
context.

That means:

- `platform` stays the broad repo/theme word
- the root operator language is about solution, variant, stage, readiness, and
  ownership
- app domains under `apps/` remain separate bounded contexts with their own
  language and rules

## Consequences

- Root onboarding, Makefiles, status helpers, and tests optimize for operator
  workflows rather than for a single application model.
- App domains can evolve independently without redefining the repo's primary
  purpose.
- The top-level tree stays intentionally mixed: operator workflows live at the
  root, while application domains stay under `apps/`.

## Evidence

- [README.md](../../README.md)
- [Makefile](../../Makefile)
- [docs/ddd/README.md](../ddd/README.md)
- [docs/ddd/context-map.md](../ddd/context-map.md)
- Current history: the `platform` initial commit `23b2689` already contained
  both `apps/subnet-calculator` and `kubernetes/kind`, which is consistent
  with the earlier `subnetcalc`-first lineage.
