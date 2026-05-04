# Guided Workflow Variant Presets — Review Addendum

<!-- markdownlint-disable MD013 -->

- Status: Draft
- Date: 2026-05-03
- Relates to: [guided-workflow-variant-presets-plan.md](guided-workflow-variant-presets-plan.md)

This document records gaps and suggested additions identified during a review of
the parent plan. Each item is self-contained so it can be resolved independently
and struck off once addressed.

---

## Gap 1: No Phase 0 — tfvars Landscape Audit

The parent plan assumes the option schema can be written without first auditing
what already exists in the repository. The original brief explicitly flagged
this as an implementation hurdle: not all options are exposed atomically across
the `100`–`900` stage tfvars files.

Before Phase 1 begins, someone needs to walk every `*.tfvars` file across
`kubernetes/kind`, `kubernetes/lima`, and `kubernetes/slicer` and answer:

- Which variables exist across all three variants, and which are
  variant-specific?
- Which variables are currently absent from the generated tfvars (i.e. the UI
  would need to add them, not just surface them)?
- Which variables have hard-coded values that cannot be overridden without
  changing the Terraform module itself?

Without this, the option schema will be aspirational rather than grounded in
what the Terraform layer currently accepts.

**Suggested addition:** Insert a Phase 0 — *tfvars landscape audit* — before
the existing Phase 1. Deliverable: a flat inventory table of every variable, its
type, which variants carry it, which stages it appears in, and whether it is
currently operator-controllable. This table becomes the empirical basis for the
`options` section of `kubernetes/workflow/options.yaml`.

---

## Gap 2: APIM Simulator Is Absent

The original brief mentioned `Backstage, APIM-simulator, Keycloak` as the
enterprise-y deployable pieces. The plan covers Backstage and Keycloak
throughout but never mentions the APIM simulator.

If it is a deployable app it belongs in the stage `700` Apps panel alongside
`sentiment`, `subnetcalc`, and `hello-platform`. If it plays a different role
(e.g. a platform service rather than a reference app), the plan should state
that distinction explicitly so the option schema encodes it correctly.

**Suggested addition:** Add `apim-simulator` to the Apps panel listing in the
UI plan and to the example app-set preset entries.

---

## Gap 3: Backstage Stage Placement Is Unresolved

Backstage appears in two distinct roles across the plan:

- As a stage `700` app ("Backstage / developer portal surfaces" in the Apps
  panel)
- As a stage `900` platform surface (it is part of the `local-idp-12gb` / IDP
  experience, which depends on SSO)

These are not the same toggle. A user deploying to stage `700` does not yet have
SSO. A user at stage `900` expects Backstage to be SSO-integrated via Keycloak.
Treating these as one option will produce either a broken deployment at `700` or
a confusing toggle at `900`.

The option schema's `introduced_at_stage` field is the right mechanism for
encoding the answer, but the plan needs to decide:

- Is Backstage a stage `700` app that deploys unauthenticated or with basic auth,
  and gains SSO when the operator later reaches stage `900`?
- Or is Backstage exclusively a stage `900` platform surface, ineligible before
  SSO is available?

Open question 2 in the parent plan touches on this but does not resolve it. The
answer should be made explicit before the option schema is written, because it
affects both `introduced_at_stage` and the `dependencies` field for every
Backstage-related option.

---

## Gap 4: Local Image Registry at Port 5002 Is Not Named

The original brief specifically mentioned "pull from local docker cache (the
service running on port 5002)" as a concrete existing service, not a
hypothetical. The parent plan has an `Image distribution` preset group with
`local-cache` as an option, which is the right abstraction, but the concrete
detail is absent.

The option schema should include a field for the registry URL/port. The
`local-cache` preset should name the default address (`localhost:5002`) as its
default value rather than leaving it implicit. Operators who run the registry on
a different port need to be able to override it without editing a preset.

**Suggested addition:** In the option schema, add an option such as:

| Field | Value |
| --- | --- |
| `id` | `local_registry_url` |
| `label` | Local image registry URL |
| `type` | string |
| `default_by_preset` | `localhost:5002` when `local-cache` is active |
| `advanced` | true |
| `introduced_at_stage` | `100` |

---

## Gap 5: Mid-Apply Progress Is Not Distinguished From Post-Apply Query

The deployment read model (Phase 6) is described as a query run after Terraform
completes. The original brief asks about showing state *during* a long apply:
"a grid of what we have deployed so far."

A `terraform apply` at stage `900` can run for 20–40 minutes. The read model
should distinguish two modes:

**Post-apply query** (what Phase 6 describes): combine Terraform state +
Argo CD sync + live Kubernetes resources. Run on demand or after a successful
exit.

**Mid-apply progress** (currently absent): stream Terraform output to the UI
and poll Kubernetes pod readiness on a timer so the deployment grid updates
while the apply is running. This requires a different implementation path:
stdout streaming is already present, but the grid panel needs to refresh
independently rather than waiting for the process to exit.

These two modes have different implementation requirements. The plan should
assign ownership — Phase 3 (browser UI streaming) or Phase 6 (read model) — and
clarify whether the grid shows only resources known to Terraform state or also
resources that Argo CD has reconciled after Terraform exited.

---

## Gap 6: No Complexity Budget for the Default UI View

The UI plan describes the full expanded state in detail but does not specify
what an operator sees before expanding anything. The original brief said "I am
imagining a simple UI." Without a stated default-view constraint, implementations
tend to drift toward showing everything by default, which defeats the
progressive disclosure intent.

**Suggested addition:** Add a paragraph to the First Screen section that
explicitly names what is visible in the default collapsed state and what requires
a deliberate expansion:

> Default view (nothing expanded): variant recommendation with readiness
> indicator, stage selector, preset picker, action selector, readiness button,
> and command preview button. All stage panels are collapsed. App toggles,
> observability stack, identity stack, advanced overrides, and diagnostic output
> are behind explicit expansion. The operator should be able to run a
> `readiness → plan → apply` sequence without expanding anything.

This also serves as the acceptance criterion for Phase 3.

---

## Gap 7: Hosted and Cloud Variant Impact Is Deferred Without Analysis

Option C (shared post-100 stack with swappable bootstrap) is correctly marked as
deferred. However, the original brief asked "what would that do to the choices
here?" for AKS, Hetzner, or bare-metal variants.

The parent plan defers without analysing which option groups are variant-local
and which are portable. If this analysis is not done before the schema is
written, the schema may hardcode assumptions that have to be undone when a hosted
variant is added.

**Suggested addition:** Add a short portability table to the Option Schema
section or the Folder Organisation section:

| Option group | Portable to hosted variants | Notes |
| --- | --- | --- |
| Cluster resource profile | No | Memory/node count is provider-managed. |
| Image distribution | Partially | Local cache and preload do not apply; pull and baked do. |
| Local registry URL | No | Not available on hosted infrastructure. |
| Network profile | Partially | CNI choice may be locked by the provider. |
| Observability stack | Yes | Independent of substrate. |
| Identity stack | Yes | Independent of substrate. |
| App set | Yes | Independent of substrate. |
| OpenTofu vs Terraform | Yes | Binary choice only. |

This table lets the schema author mark non-portable options with an
`applies_to_variants` deny-list from the start, rather than patching them later.

---

## Minor Observations

### Compatibility alias window for `950-local-idp`

Open question 4 asks how long the alias remains visible. This needs a concrete
answer before the schema is published — not after. An unresolved open question
in a shipped schema becomes permanent. Recommend setting a one-release
compatibility window explicitly and encoding it in the schema's `deprecated`
field once that field exists.

### Single vs multiple presets

Open question 1 (single high-level preset vs one preset per group) has
implementation consequences for Phase 2's tfvars rendering. If two presets from
different groups can be active simultaneously, the override merge order must be
specified before the rendering code is written. Recommend resolving this as a
prerequisite to Phase 2, not alongside it.

Suggested resolution: allow one preset per group, with the UI showing a picker
per group in the advanced panel and a summary of active presets in the default
view. This is the most flexible model without producing a combinatorial explosion
of preset interactions.

### Kubernetes health summary needs named queries

Phase 6 refers to a "Kubernetes health summary" without naming what it queries.
Without a concrete list, implementations vary and operators cannot predict what
will appear. Suggested minimum set:

- Node ready/not-ready count
- Pod phase counts by namespace (running, pending, crashloopbackoff, failed)
- Certificate expiry within 7 days
- Argo CD application sync and health status per app
- HTTPRoute and Gateway accepted/programmed conditions

---

## Suggested Phase 0 Outline

Add before the existing Phase 1:

### Phase 0: tfvars Landscape Audit

Deliverables:

- flat inventory of all Terraform variables across `kubernetes/kind`,
  `kubernetes/lima`, and `kubernetes/slicer` stage tfvars files
- classification of each variable: which variants carry it, which stages
  introduce it, whether it is currently operator-controllable
- list of variables that are hard-coded in the Terraform module and cannot yet
  be overridden via tfvars
- Backstage stage placement decision documented and agreed

Done criteria:

- the inventory table exists and is committed alongside the plan
- every variable that the option schema will expose has a confirmed tfvar name
  and a confirmed stage of introduction
- variables not yet controllable are marked as out-of-scope for Phase 1 with a
  note on what Terraform change would unlock them
