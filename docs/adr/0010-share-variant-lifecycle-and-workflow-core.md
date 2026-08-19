# ADR 0010: Concentrate the shared variant lifecycle and the guided-surface workflow core

- Status: Accepted
- Recorded: 2026-08-19

## Context

Two duplication classes had each produced live defects, and both were found by
architecture review rather than by a test.

**The variant adapters.** ADR 0006 established that focused subtree Makefiles
own variant-specific workflows. That held, but it said nothing about the parts
that were *not* variant-specific. `kubernetes/kind/Makefile` (~1600 lines) and
`kubernetes/lima/Makefile` (~1200 lines) had grown near-identical copies of
`state-reset`, `check-kubeconfig`, `gitea-sync`, the conflicting-cluster check,
and the ordered `--optional-file` tfvar list restated at ~25 call sites. Copies
drift silently: `make -C kubernetes/lima status` was a hard bash syntax error —
an `if ... then` with an empty `then` branch — dead since #163 and invisible to
the target-surface audit, shellcheck, and the 148-file gate.

**The guided surfaces.** ADR 0006 called the TUI "a thin command UI over the
status JSON and action set". A second guided surface arrived afterwards, and the
description stopped being true of it. The terminal TUI and the browser workflow
UI each assembled their own argv for `scripts/platform-workflow.sh`, sharing
zero code. The workflow core takes a positional *subcommand* (`options`,
`preview`, `apply`, `save-profile`) and a separate `--action` flag; the two
vocabularies overlap only on `apply`. The browser UI's run path passed the
*action* into the *subcommand* position, so every action except `apply` died on
`Unknown subcommand`. The preview path, written separately, got it right.

In both cases the duplication was not a style problem. It was the mechanism by
which one surface could be broken while its twin stayed green.

## Decision

Concentrate the genuinely shared parts, and keep the adapters thin rather than
absent.

**Make layer.** `mk/k8s-variant-lifecycle.mk` hosts the lifecycle targets both
local variants share, parameterised by variables the adapters set
(`KUBECONFIG_STACK_LABEL`, `CONFLICTING_CLUSTER_CHECK`,
`GITEA_SYNC_KUBECONFIG_TARGET`, `GITEA_SYNC_ASSERT_TARGET`,
`GITEA_SYNC_EXTRA_ENV`). `mk/k8s-terragrunt.mk` owns the tfvar resolution order
once, as `stack_tfvar_common` / `stack_tfvar_args` / `stack_tfvar_args_full`.

**Go layer.** `tools/platform-workflow-core` is an exported module both guided
surfaces import. It owns `Args`, `AppDefault`, `ActionUsesAutoApprove`,
`HiddenFromActionDropdown`, and the streaming `Run`. The subcommand is a
parameter distinct from `Selection.Action`, and each surface names it with a
package-level constant rather than passing a variable through.

ADR 0006 still stands: variant Makefiles remain execution adapters, and root
`make` / `platform-status` remain the operator-facing boundary. This ADR
narrows what an adapter is allowed to restate.

Two rules bound the extraction:

- A body with more than three real differences between variants stays in the
  adapter. Shared does not mean identical-by-force.
- Both surfaces must feed the core the same `options.json` facts. A surface that
  parses the payload but drops a field agrees with the other one only by
  coincidence.

## Consequences

- The drift class closes at the seam rather than one defect at a time. A
  lifecycle fix lands once for both variants.
- The TUI's Go tests become acceptance tests for argv the browser UI also
  produces.
- New shared surface needs new guards, because the compiler does not check Make
  variables or JSON field presence. `tests/variant-contracts.bats` pins the
  tfvar order and the shared lifecycle; `TestUIRulesReachTheCore` pins the
  `ui_rules` path that `stages[].app_toggles` would otherwise mask.
- Extraction moved code out of files that grep-based tests asserted on. Those
  tests must be repointed at the new home in the same change, and should assert
  the *intent* rather than a literal that parameterisation will delete — the
  failure mode `kubernetes/kind/tests/gitops-refresh.bats` already records.
- `options.json` still states the app-toggle stages twice (`ui_rules.
  app_toggle_stages` and `stages[].app_toggles`). Both copies are now consumed
  identically by both surfaces, but the duplication itself is unresolved and is
  the next thing to collapse.
- Adapter hook variables default to empty. Both current adapters set every hook
  and `.DEFAULT_GOAL := help`, so a missed hook degrades to printing help; a
  third variant should still set them explicitly.

## Evidence

- [mk/k8s-variant-lifecycle.mk](../../mk/k8s-variant-lifecycle.mk)
- [mk/k8s-terragrunt.mk](../../mk/k8s-terragrunt.mk)
- [tools/platform-workflow-core](../../tools/platform-workflow-core)
- [tests/variant-contracts.bats](../../tests/variant-contracts.bats)
- [tools/platform-workflow-ui/cmd/platform-workflow-ui/workflow_args_test.go](../../tools/platform-workflow-ui/cmd/platform-workflow-ui/workflow_args_test.go)
- [docs/reviews/architecture-review-20260817.html](../reviews/architecture-review-20260817.html) — candidates 1 and 2
- Related: [ADR 0006](./0006-operator-application-service-boundary.md), which this
  extends rather than supersedes
