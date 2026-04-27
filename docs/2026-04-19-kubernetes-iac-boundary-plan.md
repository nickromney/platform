# Kubernetes IaC Boundary And Idempotence Plan

**Last Updated:** 2026-04-19

**Status:** Ready for execution

## Overview

This plan is intentionally narrow.

It does **not** try to make this repository "pure Terraform".
It does **not** assume shell in an IaC repo is inherently wrong.
It does **not** justify refactoring by aesthetics alone.

It exists to answer four concrete questions for the Kubernetes surfaces in this
repo:

1. Where is the real ownership boundary between Terragrunt, Terraform, Make,
   and shell?
1. Which imperative steps are acceptable bootstrap escape hatches, and which
   are hiding too much inside `apply`?
1. Can we prove runtime idempotence instead of arguing about it?
1. Is there a small amount of Terragrunt consolidation worth doing without
   moving host/bootstrap logic into HCL?

Scope for this plan:

- `terraform/kubernetes`
- `kubernetes/kind`
- `kubernetes/lima`
- `kubernetes/slicer`

Out of scope for this plan:

- redesigning the whole Terragrunt layout
- replacing shell broadly just to reduce shell line count
- changing validated cluster/bootstrap flows without evidence

## Working Rules

These rules govern every phase in this plan.

1. A refactor only proceeds if it does at least one of:
   - removes duplicated Terragrunt or Make invocation wiring
   - reduces second-apply or second-plan churn
   - replaces a shell mutation with a clearly simpler provider-native resource
   - makes imperative behavior more visible and better classified
1. Terragrunt owns invocation and configuration layering, not host lifecycle.
1. Terraform owns durable cluster state and narrowly-scoped bootstrap edges that
   must participate in the dependency graph.
1. Make and shell keep host/runtime/bootstrap and validation concerns:
   - Docker or VM lifecycle
   - image build and cache sync
   - host forwards and proxies
   - kubeconfig repair and merge
   - `check-*` targets and browser verification
1. Every imperative step must end up with one explicit label:
   - `terraform-durable`
   - `terraform-bootstrap`
   - `operator-bootstrap`
   - `validation-only`
   - `candidate-provider-native`
1. Every phase ends with a stop gate. If the evidence says "good enough", stop.

## Desired Outcome

By the end of this plan, the repository should have:

- one durable markdown source of truth for the boundary decisions
- a repeatable way to prove idempotence on the local Kubernetes targets
- less duplicated Terragrunt/Make invocation wiring
- a smaller and better-justified Terraform imperative tail
- a clear backlog of what is worth changing later and what should be left alone

## Execution Order

### Phase 0: Boundary Ledger

**Goal:** replace intuition with a written classification of the current seams.

**Deliverables:**

- `docs/iac-boundaries.md`
- a ledger of the current Terraform imperative surface in `terraform/kubernetes`
- a ledger of the main shell entrypoints in the Kubernetes surfaces

**Tasks:**

1. Enumerate the `null_resource` and `local-exec` usage in
   `terraform/kubernetes`.
1. Enumerate the shell entrypoint surface in:
   - `kubernetes/kind/scripts`
   - `kubernetes/lima/scripts`
   - `kubernetes/slicer/scripts`
   - `terraform/kubernetes/scripts`
1. Classify each item into one of the allowed labels from `Working Rules`.
1. Record the trigger basis for each Terraform imperative step:
   - stable hash and dependency driven
   - cluster recreation driven
   - validation or wait only
   - noisy or suspicious
1. Record the current seam decisions in plain English:
   - Terragrunt concern
   - Terraform concern
   - Make or shell concern

**Acceptance:**

- every current Terraform imperative step is classified
- every material shell entrypoint is classified
- there is a written explanation for why Lima and Slicer stage `100` stay out of
  Terraform
- there is a written explanation for why image-cache/build/forward/check flows
  stay out of Terragrunt

**Stop gate:**

- if the ledger shows the current shell boundary is mostly well-classified and
  the real problem is only a small set of noisy Terraform edges, continue to
  Phase 1 and Phase 2 only
- if the ledger reveals broad confusion of ownership, continue to all phases

### Phase 1: Idempotence Harness

**Goal:** prove rerun behavior instead of debating it.

**Deliverables:**

- one opt-in runtime idempotence target per local Kubernetes stack
- one shared allowlist of accepted second-apply churn
- one short results document after the first execution pass

**Tasks:**

1. Add a stack-local runtime harness for:
   - `kubernetes/kind`
   - `kubernetes/lima`
   - `kubernetes/slicer`
1. The harness should run:
   - `apply`
   - same `apply` again
   - `plan`
1. Start with stage `100` and stage `900`.
1. Capture outcomes into a stable artifact under `.run/` or another ignored
   location.
1. Create an explicit allowlist for known acceptable churn only.
1. Fail the harness if non-allowlisted churn appears.

**Target command shape:**

- `make -C kubernetes/kind test-idempotence STAGE=100`
- `make -C kubernetes/kind test-idempotence STAGE=900`
- same pattern for Lima and Slicer

**Acceptance:**

- second apply is either a true no-op or explained by the allowlist
- second plan is empty or explained by the allowlist
- the plan explains any environment-sensitive noise, especially kubeconfig
  rewriting between host and devcontainer contexts

**Stop gate:**

- if idempotence is already good enough and the noise is narrow and understood,
  skip broad refactors and continue only with Terragrunt dedup plus one small
  Terraform cleanup
- if the harness shows repeated unexpected churn, continue to Phase 3

### Phase 2: Terragrunt And Make Dedup

**Goal:** remove duplicated invocation wiring without moving runtime bootstrap
into Terragrunt.

**Deliverables:**

- one shared place for repeated Terragrunt argument assembly
- less duplicated `init`, `plan`, and `apply` scaffolding across:
  - `kubernetes/kind/Makefile`
  - `kubernetes/lima/Makefile`
  - `kubernetes/slicer/Makefile`
- optional live entrypoints only if they reduce duplication without obscuring
  behavior

**Tasks:**

1. Identify the repeated pieces across the three stack Makefiles:
   - state path wiring
   - var-file layering
   - common `terragrunt init`
   - common `terragrunt plan/apply` invocation assembly
   - shared profile capture setup
1. Move repeated pieces into the smallest shared layer that keeps the runtime
   behavior obvious.
1. Keep stack-specific preflight and bootstrap logic local to each stack.
1. Avoid new Terragrunt hooks for:
   - VM or daemon lifecycle
   - host forwards
   - image build or cache sync
   - browser checks
   - kubeconfig repair

**Acceptance:**

- stack behavior is unchanged
- there is less duplicated Terragrunt invocation code
- the seam is clearer rather than more magical
- no host/bootstrap behavior moved into Terragrunt hooks

**Stop gate:**

- if the dedup requires hiding too much behavior in Terragrunt, stop and keep
  the duplication

### Phase 3: Reclassify Validation-Only Apply Steps

**Goal:** remove validation and waiting behavior from the Terraform apply path
when it does not define durable state.

**Primary candidates:**

- `wait_gitea_actions_runner_ready`
- `wait_sentiment_images`
- `wait_subnetcalc_images`
- `wait_headlamp_deployment`
- `argocd_repo_server_restart`
- `argocd_refresh_gitops_repo_apps`
- `check_kind_cluster_health_after_oidc`

**Tasks:**

1. Review each candidate and decide whether it is:
   - required for graph convergence
   - only a readiness check
   - only a health assertion
   - a restart or refresh side effect that belongs after apply
1. Move only the clearly non-durable items to `check-*` or post-apply Make
   targets.
1. Preserve explicit ordering for true bootstrap edges that still need to happen
   during apply.

**Acceptance:**

- Terraform apply becomes less noisy
- readiness or smoke checks have a clearer home
- no essential cluster convergence behavior is lost

**Stop gate:**

- if moving a step out of apply makes recovery or first-time convergence less
  reliable, keep it in Terraform and document why

### Phase 4: One Provider-Native Pilot

**Goal:** prove that one targeted shell-to-provider migration is worthwhile
before attempting more.

**Preferred first candidate:**

- `kind_storage`

**Possible secondary candidates:**

- `bootstrap_mkcert_ca`
- narrow Cilium or Hubble patching only if it becomes simpler in provider form

**Tasks:**

1. Pick exactly one candidate.
1. Replace it with provider-native Terraform only if the resulting shape is
   materially simpler.
1. Re-run the idempotence harness before and after.
1. Compare:
   - complexity
   - readability
   - rerun behavior
   - failure clarity

**Acceptance:**

- the replacement is clearly simpler
- second apply and second plan are cleaner
- tests still pass

**Stop gate:**

- if the provider-native version is not simpler, revert and keep the script

## Candidate Classification To Start From

This is the default working classification before implementation evidence
changes it.

### Likely Keep In Terraform For Now

- `ensure_kind_kubeconfig`
- `configure_kind_apiserver_oidc`
- `recover_kind_cluster_after_oidc_restart`
- Gitea bootstrap and seeding steps that Argo depends on for first convergence

### Likely Move Out Of Apply Into Validation Or Ops

- wait-only resources
- readiness polling resources
- health assertion resources
- refresh and restart helpers that do not define durable state

### Likely Best Provider-Native Candidate

- `kind_storage`

### Explicitly Not A Terragrunt Concern

- Lima or Slicer stage `100` bootstrap
- host gateway and host forward management
- image cache ensure and sync
- local image build paths
- Playwright and `check-*` flows
- kubeconfig repair and merge logic

## Parallel Work Packets

These packets are intentionally small and agent-safe. They can be assigned in
parallel once this plan is accepted.

### Packet A: Boundary Ledger

**Goal:** produce the classification document.

**Inputs:**

- `terraform/kubernetes/*.tf`
- `terraform/kubernetes/scripts`
- `kubernetes/{kind,lima,slicer}/scripts`

**Deliverable:**

- `docs/iac-boundaries.md`

**Acceptance:**

- every imperative step is labeled
- the current seam decisions are explicit
- the document includes "keep", "move", and "do not touch" calls

### Packet B: Idempotence Harness

**Goal:** add the runtime proof path and allowlist.

**Inputs:**

- `kubernetes/kind/Makefile`
- `kubernetes/lima/Makefile`
- `kubernetes/slicer/Makefile`
- existing `check-*` and stack verification scripts

**Deliverable:**

- stack-local `test-idempotence` or equivalent target
- ignored output location for captured results
- allowlist with comments

**Acceptance:**

- can run stage `100` and `900` harnesses on demand
- fails on non-allowlisted drift

### Packet C: Terragrunt Dedup

**Goal:** reduce repeated invocation/config wiring only.

**Inputs:**

- `terraform/root.hcl`
- `terraform/kubernetes/terragrunt.hcl`
- the three stack Makefiles

**Deliverable:**

- smaller shared Terragrunt/Make invocation layer

**Acceptance:**

- no behavior change
- no bootstrap migration into Terragrunt
- less duplicated argument assembly

### Packet D: Validation-Only Reclassification

**Goal:** shrink the Terraform apply path where durable state is not being
defined.

**Inputs:**

- `terraform/kubernetes/gitops.tf`
- `terraform/kubernetes/sso.tf`
- `terraform/kubernetes/hostaliases.tf`
- related `check-*` scripts

**Deliverable:**

- one small PR moving one or more clearly non-durable steps into post-apply
  checks

**Acceptance:**

- cleaner apply behavior
- unchanged convergence

### Packet E: Provider-Native Pilot

**Goal:** replace one low-risk shell-backed durable step if and only if it is
better.

**Input candidate:**

- `terraform/kubernetes/storage.tf`

**Deliverable:**

- one pilot implementation plus before/after idempotence proof

**Acceptance:**

- simpler than the shell version
- cleaner rerun behavior

## Verification

Use the smallest relevant verification surface at each step.

### Fast Static Checks

- `make -C kubernetes/kind test`
- `make -C kubernetes/lima test`
- `make -C kubernetes/slicer test`

### Runtime Proof Commands

When a phase requires live proof, use the validated stack paths already
documented in the repo-local platform guidance.

Minimum confidence path per stack:

- `kind`: stage `100` and `900`
- `lima`: stage `100` and `900`
- `slicer`: stage `100` and `900`

Each runtime change must finish with:

1. first apply succeeds
1. second apply behaves as expected
1. plan after second apply behaves as expected
1. relevant `check-*` targets still pass

## Explicit Non-Goals

Do **not** do any of the following under this plan:

- "reduce shell in IaC" as a goal by itself
- move Lima or Slicer bootstrap under Terragrunt hooks
- hide complex stack behavior in opaque Terragrunt pre-hooks or post-hooks
- replace working shell with provider code that is larger or harder to debug
- treat validation-only scripts as evidence of architectural failure

## Exit Conditions

This plan is complete when all of the following are true:

- the repo has a durable boundary document
- runtime idempotence is measured instead of assumed
- Terragrunt duplication is reduced where it is truly boilerplate
- clearly non-durable apply steps are either moved or explicitly justified
- at most one provider-native pilot has been attempted unless it is obviously
  successful

If those conditions are met and the remaining shell surface is well-tested and
well-classified, stop. That is a good outcome.
