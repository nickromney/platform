# DDD Architecture and Ubiquitous Language

This directory provides the canonical Domain-Driven Design (DDD) model for the
platform.

The architecture is split into two layers:

- the current implementation and test dialect
- the ratified domain language that the code should continue converging on

The repo uses precise operational language in Makefiles, status helpers, stack
checks, and BATS tests. That language is useful evidence, but it is not
automatically the same thing as the ubiquitous language.

## Artifacts

- [Ubiquitous Language](./ubiquitous-language.md) — The canonical vocabulary.
- [Context Map](./context-map.md) — Relationship between domains and services.
- [Retrospective ADRs](../adr/README.md) — Historical decisions recovered from
  the repo lineage.
- [Contracts Between Contexts](./contracts.md) — Frozen wire-visible interfaces.
- [Consistency Plan](./consistency-plan.md) — The roadmap used to align code and docs.
- [Solution Variant Comparison](./solution-variant-comparison.md) — Implementation differences.
- [Subnetcalc Analysis](./subnetcalc-analysis.md) — Subnetcalc domain model.
- [Sentiment Analysis](./sentiment-analysis.md) — Sentiment domain model.
- [SD-WAN Analysis](./sd-wan-analysis.md) — SD-WAN domain model.

## Current State Of The Solution

- The repo's primary concern is local stack operation: bringing up and
  managing a useful solution variant on one machine.
- The most mature problem-domain model is `subnetcalc`.
- `apps/sentiment` is a smaller domain with a simpler model and cleaner
  request flow.
- Identity, routing, and API mediation are critical supporting
  contexts between the user and the application domains.
- BATS coverage specifies execution contracts, helper delegation, machine
  ownership, and variant readiness.

The term `platform` remains the repo/theme word. The sharp path taxonomy is
`solution` first (e.g., `kubernetes`, `sd-wan`), then `variant` (e.g., `kind`,
`lima`, `slicer`).

## Implementation Principles

- **Glossary and Code Consistency**: The implementation uses the ratified terms
  defined in the [Ubiquitous Language](./ubiquitous-language.md).
- **Frozen Wire Contracts**: External endpoints, JSON schemas, and enums stay
  frozen to prevent breaking changes — see [Contracts](./contracts.md).
- **Separation of Concerns**: Business meaning is separated from hosting and
  topology details wherever possible.

## Pre-Launch Alignment

- The goal is consistency between the codebase and glossary.
- The [Consistency Plan](./consistency-plan.md) tracks what is resolved, what is
  still an accepted gap, and what is deferred until post-launch.
- The major terminology questions (`lookup`, `target` vs `variant`, `host access
  path`) are resolved, but not every glossary/code mismatch is closed yet.
