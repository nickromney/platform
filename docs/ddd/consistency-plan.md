# Consistency Plan

This plan moves the repo from "the translation problem is visible" to "code
and glossary are consistent".

Scope is intentionally narrow. Launch is days away. Every change must be
reachable by red/green TDD, and the plan stops as soon as the remaining gaps
are either accepted overloads or deferred wire-contract renames.

## Rules

1. **Every change starts with a red test** that fails against current code
   and asserts the glossary-aligned behavior.
2. **Green means the red test passes and the existing suite still passes.**
3. **Wire contracts are frozen** — no endpoint, header, enum value, or
   published response field is renamed pre-launch. See
   [contracts.md](./contracts.md) for the full list.
4. **Internal identifiers are fair game** — classes, functions, private
   variables, and docs may be renamed freely as long as tests stay green.
5. **One direction per gap.** For each gap: either the code moves to match
   the glossary, or the glossary moves to match the code. No third option.
6. **Stop gate:** when the remaining gaps are either accepted overloads
   (documented in this file) or wire-contract renames (deferred to
   post-launch), this plan is done.

## Gap Ledger

Each row has a direction, a red test description, and a green condition.

### A. Docs-only alignment

These are glossary edits to match current code. Zero runtime risk.

| # | Gap | Direction | Red | Green |
| --- | --- | --- | --- | --- |
| A1 | Glossary `auth method` values match the `AuthMethod` enum: `none, api_key, jwt, azure_swa, apim, azure_ad`. | Resolved. | `tests/ddd-consistency.bats` asserts the glossary row contains the ratified enum vocabulary. | BATS check passes; glossary and code agree. |
| A2 | Glossary `Easy Auth` is Azure-specific; code uses `azure_swa` and `azure_ad`. | Resolved. | `tests/ddd-consistency.bats` fails if `Easy Auth` appears outside the Identity And Access section. | BATS check passes; `Easy Auth` stays confined to a single Azure-specific glossary cell. |
| A3 | Glossary now treats `lookup` as a frontend orchestration term, not a backend domain term. | Resolved. | `tests/ddd-consistency.bats` fails if the old "not yet a clear domain term" wording remains. | BATS check passes; `lookup` appears only as a frontend orchestration term in the glossary. |

### B. Internal code alignment (zero wire change)

Pydantic request/response models are wire contracts. Internal types are not.
All changes in this group keep JSON payloads byte-identical.

| # | Gap | Direction | Red | Green |
| --- | --- | --- | --- | --- |
| B1 | `SubnetIPv4Request.mode` is now typed as `CloudMode` with the glossary values `Standard, AWS, Azure, OCI`. | Resolved. | `tests/test_subnets.py::TestIPv4SubnetCalculation::test_cloud_mode_request_contract` fails if `CloudMode` or the typed request field is missing. | The contract test passes, `mode` still serializes to the same JSON strings, and `uv run --extra dev python -m pytest tests` stays green. |
| B2 | Sentiment labels now flow through a glossary-backed `SentimentLabel` module. | Resolved. | `server.test.js` imports `SentimentLabel` and fails if the analyze path returns a label outside `positive`, `negative`, `neutral`. | `sentiment-label.js` defines the vocabulary, label writes normalize through it, and the HTTP payload stays unchanged. |
| B3 | Mixed-signal neutralization now lives in `comment-analysis-policy.js` instead of inline in `server.js`. | Resolved. | `server.test.js` imports `commentAnalysisPolicy` and fails if the mixed-signal tie-break cannot be exercised outside the HTTP path. | `comment-analysis-policy.js` owns the cue lists and tie-break logic, `server.js` delegates to it, and the sentiment test suite stays green. |
| B4 | Subnetcalc analysis doc names `Address`, `Network`, `CloudflareMembership`, `PrivateRangeMatch` as value objects; code works directly with `ipaddress` types and booleans. | Accepted gap. | n/a | Accepted overload — `ipaddress.IPv4Network` plays the role of `Network` adequately for launch. Post-launch task. |
| B5 | Glossary says `stack` means "the whole collection of apps realized for a solution variant"; code and tests use `stack` for compose slices, kind in-cluster shape, and app demos. | Accepted gap. | n/a | Accepted overload — `stack` is context-dependent pre-launch; post-launch candidate for rename in operator docs only. |

### C. Operator surface alignment

These touch shell scripts and BATS tests. Status-output format has consumers
(`platform-tui.sh`, `platform-status.bats`) that must move in the same PR.

| # | Gap | Direction | Red | Green |
| --- | --- | --- | --- | --- |
| C1 | Operator status and TUI surfaces now use variant-oriented keys and labels instead of provider/project aliases. | Resolved. | `tests/platform-status.bats` fails if `active_provider*`, `active_project*`, `providers`, `projects`, or action-level `provider` / `project` aliases remain. | The BATS checks pass, `platform-tui.sh` consumes only variant-oriented fields, and the migration note for generated release notes is: `platform status` renamed `active_provider*` aliases to `active_variant*` / `variant`. |
| C2 | Status output uses `claimed by` for ingress/VM ownership; glossary ratifies `ownership`. | Resolved. | n/a | `claimed by` remains an acceptable human-readable rendering of ownership. |

### D. Post-launch only

These stay out of scope until a version bump is planned.

- Renaming `AuthMethod` enum values (`azure_swa` → something glossary-pure).
- Renaming subnetcalc endpoints.
- Collapsing `api-fastapi-azure-function` and `api-fastapi-container-app`.
- Adding `POST /api/v1/lookup` (additive but adds wire surface area; defer).
- Promoting `AuthMethod` to a shared package.
- Extracting a shared `/network/diagnostics` payload between `subnetcalc` and
  `sd-wan`.

## Execution Order

Run in this order. Each block is a single PR.

1. **PR 1 — Docs only (A1, A2, A3).** Pure markdown. No code risk.
2. **PR 2 — `CloudMode` (B1).** Red first, then implementation. Expect zero
   JSON diff; verify with existing `test_subnets.py`.
3. **PR 3 — `SentimentLabel` + `CommentAnalysisPolicy` (B2, B3).** Red first
   for each. Bundle because they touch the same file.
4. **PR 4 — `active_variant` rename (C1).** Changes operator surface. Move
   script, TUI consumer, and BATS tests together. Ship with a release note.
5. **Stop.** Remaining items (B4, B5, D) are documented as accepted or
   deferred and will not block launch.

## TDD Checklist Per Change

Before opening each PR:

- [ ] new test file or case exists
- [ ] new test fails on `main` (red verified)
- [ ] implementation landed
- [ ] new test passes (green verified)
- [ ] existing test suite passes unchanged
- [ ] no wire JSON diff (verified by an existing integration or snapshot
      test where one exists)
- [ ] glossary row updated from "direction of travel" to "resolved"

## Done Criteria For This Plan

- Every row in the Gap Ledger is either **resolved** or explicitly marked
  **accepted gap** or **post-launch**.
- `ubiquitous-language.md` has no term that contradicts code reachable by a
  red test.
- `contracts.md` is unchanged — no wire surface moved.
- Release notes mention the one operator-surface rename (`active_provider`
  → `active_variant`).
