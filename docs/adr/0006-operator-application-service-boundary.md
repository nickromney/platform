# ADR 0006: Treat make, status, and TUI as the operator-facing application service boundary

- Status: Accepted (retrospective)
- Recorded: 2026-04-21

## Context

As the repo expanded beyond a single stack path, operators needed one stable
workspace entrypoint that could answer three questions quickly:

- where should I go next
- what currently owns the machine
- what action is safe to run now

The current root operator surface answers those questions through three linked
entrypoints:

- root `make`, which is intentionally informational and routes users to focused
  subtree workflows
- `scripts/platform-status.sh`, which assembles the read model for ownership,
  readiness, blockers, and available actions across variants
- `tools/platform-tui`, which presents the same status/action surface in an
  interactive Bubble Tea chooser and falls back to plain status text when needed

The tests make this explicit. Root `make` is required to stay informational.
`platform-status` exposes variant-oriented fields and action metadata.
`platform-tui` is expected to consume that status JSON rather than invent a
separate model.

## Decision

Treat root `make`, `platform-status`, and `platform-tui` as the operator-facing
application service boundary for the `Local Stack Operations` context.

In that boundary:

- root `make` is the router and command catalog, not the place for
  stack-specific mutation logic
- `platform-status` is the canonical read model for machine ownership,
  readiness, blockers, and next actions
- `platform-tui` is a thin command UI over the status JSON and action set
- focused subtree Makefiles remain the authoritative place for variant-specific
  workflows and side effects

Repo-wide reporting and maintenance commands such as `lint`, `fmt`,
`check-version`, and `release*` still belong at the root because they are
workspace-wide services rather than variant-specific operations.

## Consequences

- Operators get one stable entry surface even as the number of variants grows.
- Status semantics become machine-readable and testable instead of living only
  in prose.
- The TUI stays cheap to maintain because it rides on the same JSON/action
  contract as scripts and tests.
- Stack-specific mutation logic stays close to the relevant subtree instead of
  leaking upward into the root workspace entrypoint.
- Future automation should prefer the status/action contract over scraping help
  text or reproducing runtime-detection logic elsewhere.

## Evidence

- [Makefile](../../Makefile)
- [scripts/platform-status.sh](../../scripts/platform-status.sh)
- [tools/platform-tui](../../tools/platform-tui)
- [tests/makefile.bats](../../tests/makefile.bats)
- [tests/platform-status.bats](../../tests/platform-status.bats)
- [tools/platform-tui/internal/tui/model_test.go](../../tools/platform-tui/internal/tui/model_test.go)
- Current history:
  - `d88aace` improved repo onboarding and root Make defaults
  - `0f65cec` added local runtime status and the TUI
  - `9ce3dc3` refined the status contract and its operator fields
