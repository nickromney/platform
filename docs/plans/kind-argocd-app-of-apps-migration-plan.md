# Kind Argo CD App-Of-Apps Migration Plan

**Last Updated:** 2026-05-19

**Status:** Planning

## Purpose

Decide how to move the `kubernetes/kind` reference variant toward the Argo CD
app-of-apps GitOps pattern without weakening the cumulative stage model or
causing avoidable prune/recreate churn on existing local clusters.

The short conclusion from this planning pass is:

- the app-of-apps path already exists and is mostly wired
- `kubernetes/kind/stages/900-sso.tfvars` still pins
  `enable_app_of_apps = false`
- a fresh-cluster migration is small-to-medium work
- an existing-cluster migration needs a deliberate adoption step because direct
  Terraform-owned child Applications have Argo CD finalizers
- one app-of-apps-only manifest drift bug should be fixed before making this
  the default: `apps/argocd-apps/80-chatgpt-sim.application.yaml` uses a
  different repo URL than the direct Terraform Application

## Domain And ADR Constraints

This plan follows the current `Local Stack Operations` language:

- `kind` remains the reference variant.
- `100` through `900` remain cumulative stages.
- Argo CD, Gitea, app repos, observability, and SSO stay stage outcomes.
- Application specs and deployment records should remain visible through Argo
  CD Applications, the GitOps repo, status checks, and Launchpad/readiness
  surfaces.

Relevant decisions:

- ADR 0001: the repo is a local stack operations workspace.
- ADR 0002: the cumulative stage model and `kind` reference variant are stable.
- ADR 0006: root `make`, status, and guided surfaces are the operator-facing
  application interface; variant-specific side effects stay in the focused
  subtree.
- `docs/iac-boundaries.md`: `sync_gitea_policies_repo` is a Terraform
  bootstrap step, while Argo refreshes and many waits are readiness or
  validation behavior.

## Architecture Verification

Current stage 900 behavior:

- `kubernetes/kind/stages/900-sso.tfvars` sets
  `enable_app_of_apps = false`.
- Terraform directly creates many Argo CD `Application` objects when direct
  mode is active.
- `terraform/kubernetes/app-of-apps.tf` can instead create one root
  `Application` named `app-of-apps`.
- That root Application syncs `apps/argocd-apps` from the rendered
  `platform/policies` GitOps repo.
- `terraform/kubernetes/locals.tf` changes the expected GitOps app inventory:
  in direct mode it lists child app names; in app-of-apps mode it lists only
  `app-of-apps`.
- `terraform/kubernetes/scripts/sync-gitea-policies.sh` copies and rewrites the
  GitOps repo tree, prunes child app manifests by feature flags, vendors chart
  inputs, and renders route/image details.

Direct Terraform child Applications currently include policy, cert-manager,
gateway, runner, workload, agentgateway, observability, IDP, MCP, ChatGPT sim,
and SSO proxy Applications. In app-of-apps mode, many of those become children
under `apps/argocd-apps`, but some Application objects still remain
Terraform-owned: Gitea, Headlamp, and SSO proxy Applications.

Existing tests and checks already know about the split:

- `terraform/kubernetes/tests/bootstrap_app_of_apps.tftest.hcl`
- `terraform/kubernetes/tests/direct_workload_apps.tftest.hcl`
- `kubernetes/kind/tests/sync-gitea-policies.bats`
- `kubernetes/kind/tests/platform-gateway-tls.bats`
- `terraform/kubernetes/scripts/check-gateway-stack.sh`
- `terraform/kubernetes/scripts/check-cluster-health.sh`
- `terraform/kubernetes/scripts/check-component-version.sh`

## Deepening Opportunities

### 1. Deepen Application Spec Publication Behind One GitOps Ownership Module

**Files**

- `terraform/kubernetes/app-of-apps.tf`
- `terraform/kubernetes/locals.tf`
- `terraform/kubernetes/*apps*.tf`
- `terraform/kubernetes/apps/argocd-apps/*.application.yaml`
- `terraform/kubernetes/scripts/sync-gitea-policies.sh`

**Problem**

The current interface is shallow. Callers must know whether an application spec
is published by a direct Terraform `kubectl_manifest`, by a rendered child
Application manifest, or by both. The same application spec facts are spread
across Terraform strings, checked-in GitOps manifests, render pruning, status
checks, and docs.

The deletion test says the direct child Application resources are not earning
enough depth for the later stages: deleting them would not delete the real
complexity; it would reappear as child Application manifest ownership and
migration/adoption rules.

**Solution**

Make app-of-apps the normal application spec publication seam for `kind` once
Gitea exists. Keep Terraform responsible for bootstrap modules that genuinely
need to exist before GitOps can reconcile: Argo CD, Gitea, repo credentials,
GitOps repo sync, bootstrap CRDs, and the root `app-of-apps` Application.

**Benefits**

This improves locality by putting child Application desired state in one GitOps
tree. It improves leverage because tests and status checks can reason about
one publication interface instead of parallel Terraform and GitOps adapters.

### 2. Add A Migration Adapter For Existing Direct-Mode Clusters

**Files**

- `kubernetes/kind/Makefile`
- `kubernetes/kind/scripts/*`
- `terraform/kubernetes/app-of-apps.tf`
- `terraform/kubernetes/scripts/check-cluster-health.sh`
- `terraform/kubernetes/scripts/check-gateway-stack.sh`

**Problem**

Flipping `enable_app_of_apps` on an existing direct-mode cluster can make
Terraform destroy state-owned child Applications while the root app is being
created. Because those Applications have Argo CD finalizers, deletion can prune
live resources before app-of-apps recreates the children.

**Solution**

Provide a one-time migration adapter for existing clusters. It should create or
verify the root app, remove Terraform ownership pressure from direct child
Applications without pruning their live resources, then let app-of-apps adopt
the same names from Git.

**Benefits**

This concentrates the dangerous adoption behavior in one module instead of
spreading manual instructions across operators. Tests can target the migration
interface directly.

### 3. Finish Deepening The GitOps Render Contract

**Files**

- `terraform/kubernetes/locals.tf`
- `terraform/kubernetes/gitops.tf`
- `terraform/kubernetes/scripts/sync-gitea-policies.sh`
- `kubernetes/kind/tests/sync-gitea-policies.bats`

**Problem**

The GitOps renderer is already moving toward a render contract, but
app-of-apps makes the contract more load-bearing. Any child manifest drift
becomes a first-class reconciliation failure. The visible example is
`80-chatgpt-sim.application.yaml`, whose repo URL differs from the direct
Terraform Application.

**Solution**

Require child Application manifests to be generated or normalized from the same
render contract used by Terraform. Add tests that compare direct-mode
Application source facts against rendered app-of-apps child source facts for
all supported application specs.

**Benefits**

This improves locality by making render drift detectable at the render seam.
It improves leverage because one golden rendered-tree test can protect many
child Applications.

### 4. Align The Deployment Read Model With Parent/Child Application Ownership

**Files**

- `terraform/kubernetes/scripts/check-cluster-health.sh`
- `terraform/kubernetes/scripts/check-gateway-stack.sh`
- `terraform/kubernetes/scripts/check-app.sh`
- `terraform/kubernetes/scripts/check-component-version.sh`
- Grafana Launchpad render inputs

**Problem**

The deployment read model already has app-of-apps awareness, but the ownership
model is mixed. Some checks treat `app-of-apps` as special while still listing
individual child Applications. That is reasonable during migration, but it
should become explicit.

**Solution**

Define the read model in terms of mode:

- direct mode expects Terraform-owned child Applications
- app-of-apps mode expects the parent plus child Applications created from Git
- bootstrap-only Terraform-owned Applications are documented exceptions

**Benefits**

This keeps readiness checks useful for both modes and prevents status surfaces
from accidentally hiding failed child Applications behind a healthy parent.

## Recommended Direction

Use app-of-apps as the default for fresh `kind` stage `500+` GitOps-backed
stages, not only at stage `900`.

Reasoning:

- Stage `400` has Argo CD but no in-cluster Gitea policies repo, so direct
  Terraform ownership is still appropriate.
- Stage `500` adds Gitea and re-enables the full Argo CD controller set. This
  is the first stage where the GitOps repo can be the normal publication seam.
- Later stages can add policies, app repos, observability, and SSO by changing
  rendered child Application manifests rather than adding more direct
  Terraform resources.

Keep direct mode as a compatibility adapter until app-of-apps has passed a full
stage `900` rebuild and migration drill.

## Execution Plan

### Phase 0: Fix Known Drift Before Any Default Change

**Goal:** remove the known app-of-apps-only correctness gap.

**Tasks**

1. Fix `terraform/kubernetes/apps/argocd-apps/80-chatgpt-sim.application.yaml`
   so it uses the same policies repo source shape as the direct Terraform
   `argocd_app_chatgpt_sim` Application.
2. Add a render or manifest test that would catch this mismatch.
3. Audit all child Application manifests for repo URL, path, destination,
   sync-wave, and sync options drift against direct Terraform Applications.
4. Decide whether the audit is a one-time test fixture or a reusable
   comparison helper.

**Acceptance**

- No child Application points at a stale or different policies repo URL.
- Direct and app-of-apps source facts match for every duplicated application
  spec.
- Existing render tests still pass.

**Suggested verification**

```bash
make -C kubernetes/kind test
TOFU_TEST_FILTER=tests/bootstrap_app_of_apps.tftest.hcl terraform/kubernetes/scripts/run-opentofu-tests.sh --execute
TOFU_TEST_FILTER=tests/direct_workload_apps.tftest.hcl terraform/kubernetes/scripts/run-opentofu-tests.sh --execute
```

### Phase 1: Make App-Of-Apps A Fresh-Cluster Stage Path

**Goal:** prove the default path on a clean `kind` cluster before supporting
adoption from existing direct-mode state.

**Tasks**

1. Enable app-of-apps for `kubernetes/kind/stages/500-gitea.tfvars` and later
   stages, or introduce a narrowly named profile first if a softer rollout is
   preferred.
2. Keep stage `400` in direct bootstrap mode.
3. Update expected app inventory logic so stage `500+` checks know the normal
   mode is app-of-apps.
4. Ensure `sync_gitea_policies_repo` completes before the root app is applied.
5. Ensure the root app hard-refresh path and health checks wait for child app
   creation, not only parent existence.

**Acceptance**

- Clean stage `500` creates Gitea, pushes the policies repo, creates
  `app-of-apps`, and reconciles child Applications relevant to the stage.
- Clean stage `900` reaches the same end-user stack shape as direct mode.
- Argo CD shows parent and child Application health clearly.

**Suggested verification**

```bash
make -C kubernetes/kind reset AUTO_APPROVE=1
make -C kubernetes/kind 100 apply AUTO_APPROVE=1
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind check-health
make -C kubernetes/kind check-gateway-stack
make -C kubernetes/kind check-sso-e2e
```

### Phase 2: Define The Existing-Cluster Migration Adapter

**Goal:** avoid finalizer-driven resource pruning when an already-applied
direct-mode cluster moves to app-of-apps.

**Tasks**

1. Run a direct-mode stage `900` apply and capture the Terraform plan after
   flipping only `enable_app_of_apps=true`.
2. Classify every planned destroy:
   - child Application that should be adopted by GitOps
   - bootstrap Application that should remain Terraform-owned
   - unexpected resource change
3. Build a migration adapter that:
   - verifies the rendered `apps/argocd-apps` tree is already in Gitea
   - creates or verifies `app-of-apps`
   - removes Argo CD finalizers from direct child Applications only when the
     same child manifest exists in Git
   - lets Terraform stop managing direct child Applications without pruning
     live resources
4. Make the adapter dry-run by default and require an explicit execute flag.
5. Document whether the supported migration is adoption-in-place or reset-first.

**Acceptance**

- Existing direct-mode clusters can migrate without losing gateway, policy,
  workload, observability, or SSO resources.
- The migration adapter refuses to continue if the child manifest is missing
  from the rendered GitOps tree.
- The plan after migration no longer wants to delete live application-managed
  resources.

**Suggested verification**

```bash
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind gitea-sync AUTO_APPROVE=1
make -C kubernetes/kind check-health
make -C kubernetes/kind check-gateway-stack
```

Then run the migration adapter in dry-run and execute modes once it exists.

### Phase 3: Reduce Mixed Ownership

**Goal:** make remaining Terraform-owned Applications intentional rather than
accidental.

**Tasks**

1. Decide whether Headlamp belongs under app-of-apps. It currently remains
   Terraform-owned in app-of-apps mode.
2. Decide whether SSO proxy Applications belong under app-of-apps. They
   currently remain Terraform-owned in app-of-apps mode.
3. Keep Gitea direct unless there is a separate bootstrap redesign, because the
   GitOps repo depends on it.
4. Update `local.argocd_gitops_repo_app_names` so it represents the intended
   ownership model rather than only the current implementation.
5. Update docs that currently claim Argo CD uses app-of-apps without explaining
   that kind stage `900` still defaults to direct mode.

**Acceptance**

- Every Terraform-owned Argo CD Application has a documented bootstrap reason.
- Every non-bootstrap platform or workload app is owned by the GitOps child
  tree.
- Docs use one consistent operator story.

### Phase 4: Promote Or Retire Direct Mode

**Goal:** decide whether direct mode remains a compatibility adapter or is
removed.

**Tasks**

1. Keep direct mode until app-of-apps passes:
   - clean stage `900`
   - direct-to-app-of-apps migration
   - idempotent second apply
   - health, gateway, and SSO checks
2. If direct mode remains, document it as a compatibility adapter and keep
   tests.
3. If direct mode is retired, delete direct child Application resources in a
   separate cleanup plan after migration support has existed for at least one
   local release cycle.

**Acceptance**

- Operators have a clear default path.
- Tests cover the supported path and any retained compatibility adapter.
- Removing direct mode is not coupled to the first default flip.

## Testing Strategy

Static and render tests:

- `make -C kubernetes/kind test`
- `TOFU_TEST_FILTER=tests/bootstrap_app_of_apps.tftest.hcl terraform/kubernetes/scripts/run-opentofu-tests.sh --execute`
- `TOFU_TEST_FILTER=tests/direct_workload_apps.tftest.hcl terraform/kubernetes/scripts/run-opentofu-tests.sh --execute`
- targeted Bats tests for rendered `apps/argocd-apps` manifests

Runtime confidence path:

- clean `kind` stage `900` rebuild
- second `900 apply` to expose churn
- `check-health`
- `check-gateway-stack`
- `check-gateway-urls`
- `check-sso`
- `check-sso-e2e`

Migration confidence path:

- start from direct-mode stage `900`
- sync the policies repo
- run migration adapter dry-run
- run migration adapter execute
- apply app-of-apps mode
- rerun health and SSO checks

## Risks

| Risk | Mitigation |
| --- | --- |
| Direct child Application finalizers prune live resources during migration | Add an explicit migration adapter and refuse to proceed unless matching child manifests exist in Git |
| Parent app looks healthy while a child app is missing or degraded | Keep deployment read model checks at the child Application level |
| Rendered child manifests drift from direct Terraform Applications | Add direct-vs-child source fact tests before flipping defaults |
| Stage `500` creates app-of-apps before the policies repo is ready | Keep `sync_gitea_policies_repo` and repo-server restart dependencies ahead of root app creation |
| Docs overstate app-of-apps as the current default | Update docs in the same change that changes the default, or clarify optional mode before then |

## Open Questions

1. Should app-of-apps become the default at stage `500`, or should it first be
   exposed through a profile to gather one clean rebuild result?
2. Should Headlamp and SSO proxy Applications move under app-of-apps, or remain
   direct because their secrets and identity wiring are Terraform-heavy today?
3. Is an adoption-in-place migration worth the extra adapter, or is a reset
   acceptable for `kind` because it is the local reference variant?
4. Should `ApplicationSet` be used later for repeated app/environment surfaces,
   or should this pass stay strictly with app-of-apps child Applications?

## First Implementation Slice

The first slice should be intentionally small:

1. Fix the `chatgpt-sim` child Application repo URL drift.
2. Add a test that fails on direct-vs-child source drift.
3. Run focused Terraform and Bats tests.
4. Produce a clean plan for enabling app-of-apps at stage `500+`, without
   applying it yet.

This slice gives immediate correctness value even if the final decision is to
keep direct mode for one more cycle.
