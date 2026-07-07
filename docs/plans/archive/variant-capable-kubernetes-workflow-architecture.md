# Variant-Capable Kubernetes Workflow Architecture

## Summary

The local Kubernetes workflow should stay focused on `kind`, `lima`, and
`slicer`, but its core vocabulary must be capable of supporting future
bare-metal, attached, or hosted Kubernetes variants.

The AKS baseline in `~/Developer/personal/aks-course-development` is useful as
an architecture stress test. It shows where a future hosted platform would need
multiple state boundaries, explicit dependency inputs, and provider-specific
module or root composition. It should not be copied into this repo, and AKS is
not being implemented here.

## Decisions

- Keep the operator ladder as `solution -> variant -> stage -> preset ->
  override`.
- Keep `target` as the Makefile and compatibility noun, but expose `variant` in
  guided surfaces and workflow metadata.
- Treat a `variant` as an adapter that satisfies contracts. Terraform modules,
  Terragrunt roots, shell scripts, hosted provider APIs, or external setup are
  implementation details behind the adapter.
- Treat a `context` as a deployable or state boundary. Current local contexts
  are `local-substrate` and `platform-stack`; future hosted variants may split
  network, identity, cluster, and platform stack contexts.
- Treat a `contract` as the facts a context provides or consumes: kubeconfig,
  ingress, DNS, registry, CNI, identity, resource sizing, lifecycle mode, and
  state scope.
- Keep stages as the teaching progression. Stages do not need to map one-to-one
  to Terraform roots, state files, or cloud contexts.
- Keep presets as overlays on options and contracts, not hidden stage numbers.
- Do not create a monolithic `variant` Terraform module.

## AKS Baseline Lessons

- The AKS baseline's flexibility comes from separate Terraform contexts and
  numbered variable sets. That informs our metadata model, but the Azure folder
  tree and stage numbering should not be imported.
- AKS-style variable sets map to presets and overlays here. For example,
  minimum-cost AKS settings map to resource presets such as `minimal`, not to a
  new stage.
- Hosted variants need explicit external dependency sources:
  `created_by_previous_context`, `provided_by_user`, `discovered`, or
  `not_applicable`.
- Provider-specific inventory can come from Terraform/OpenTofu outputs or
  `show -json`, but guided surfaces should expose provider-neutral status:
  cluster access, nodes, CNI, ingress, GitOps, apps, observability, identity,
  and raw logs.
- Capability toggles should be validated in workflow metadata before Terraform
  or OpenTofu receives invalid combinations.

## Current Implementation

- `scripts/platform-workflow.sh options --execute --output json` emits local
  variants, variant classes, contexts, contracts, configuration options, source
  precedence, provider-neutral status facets, and future external dependency
  source names.
- `scripts/platform-workflow.sh preview --execute --output json` includes the
  selected variant metadata, stage context, required contracts, and effective
  config source precedence.
- The browser workflow UI preserves the simple first screen and renders the
  selected variant contract as an advanced preview detail.
- The TUI continues to call the shared workflow core and uses `variant` in
  operator-facing copy while still passing the legacy `--target` flag.
- `docs/ddd/ubiquitous-language.md` ratifies `variant adapter`, `context`,
  `contract`, `lifecycle mode`, and `state scope`.

## Compatibility Rules

- Existing `kubernetes/kind`, `kubernetes/lima`, and `kubernetes/slicer`
  Makefiles remain the operational entrypoints.
- Existing workflow commands using `--target kind|lima|slicer` continue to work.
- Existing preview JSON fields such as `target`, `stack_path`, `stage`,
  `action`, `command`, and `app_overrides` remain present.
- Future unsupported variant classes are metadata only. They must not be
  selectable or executable until an adapter exists.

## Acceptance Tests

- Workflow options expose rich variant/context/contract metadata while retaining
  legacy `targets`.
- Workflow preview exposes the selected variant contract and effective config
  source precedence.
- Matrix tests still prove existing local stage/action/app combinations render
  the same Make commands.
- Browser UI `/api/options` hides legacy `targets` and returns variant metadata.
- TUI tests prove local variants, stage shortcuts, reset, and app toggles still
  behave as before.
