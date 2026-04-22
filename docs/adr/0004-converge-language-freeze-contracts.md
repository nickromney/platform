# ADR 0004: Converge on DDD language without breaking shipped contracts

- Status: Accepted (retrospective)
- Recorded: 2026-04-21

## Context

The repo introduced a ratified DDD glossary late in the current product shape,
after roughly six months of existing operator terms, test names, headers,
payloads, and API paths had already accumulated between October 2025 and April
2026.

That creates two truths:

- internal names and docs still need convergence toward a cleaner ubiquitous
  language
- shipped wire-visible contracts cannot be renamed casually without breaking
  consumers

The current DDD support docs already reflect this tension: one document defines
the glossary, another freezes contract surfaces, and the consistency plan uses
red/green tests to move the codebase toward the glossary.

## Decision

Use a two-speed model:

- converge internal names, docs, tests, and operator wording toward the
  ratified DDD vocabulary
- freeze external endpoints, headers, enum values, and published payload keys
  until an explicit versioned breaking-change decision is made

Keep the ratified distinctions that matter most:

- `solution` and `variant` are domain-taxonomy terms
- `target` remains a Makefile and workflow noun
- product names stay where they are the real operator language

## Consequences

- The repo can improve its language incrementally without destabilizing shipped
  behavior.
- Glossary alignment becomes testable work rather than aspirational prose.
- Accepted overloads can be documented instead of hidden.
- Breaking renames move out of ad hoc refactors and into explicit versioned
  change control.

## Evidence

- [docs/ddd/ubiquitous-language.md](../ddd/ubiquitous-language.md)
- [docs/ddd/contracts.md](../ddd/contracts.md)
- [docs/ddd/consistency-plan.md](../ddd/consistency-plan.md)
- [tests/ddd-consistency.bats](../../tests/ddd-consistency.bats)
- Current history: `63878e2` introduced the first DDD vocabulary pass and
  `f74dd5f` added the consistency plan and contract catalog.
