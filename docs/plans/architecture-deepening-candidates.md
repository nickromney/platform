# Architecture Deepening Candidates

<!-- markdownlint-disable MD013 -->

- Status: Draft
- Date: 2026-05-06
- Scope: Local Stack Operations architecture review
- Source process: `improve-codebase-architecture`

## Purpose

This note records the strongest deepening opportunities found during a
codebase architecture pass. The aim is not to prescribe implementation yet. It
keeps the candidate list stable so each item can be explored without losing the
broader context.

## Candidates

### 1. Deepen The Guided Workflow Contract

Files:

- `scripts/platform-workflow.sh`
- `tools/platform-workflow-ui/platform_workflow_ui/workflow.py`
- `tools/platform-workflow-ui/platform_workflow_ui/main.py`
- `tools/platform-tui/internal/tui/model.go`
- `tests/platform-workflow.bats`
- `tests/platform-workflow-ui.bats`

Problem:
The guided workflow has a strong conceptual Interface, but stages, variants,
actions, presets, app-toggle rules, and next-stage logic are duplicated across
Bash, Python, Go, JavaScript, and tests. The current Modules are shallow
because each guided surface needs to know too much of the workflow
Implementation.

Candidate solution:
Promote the workflow options into one data-backed Module. Keep
`scripts/platform-workflow.sh` as the authoritative Adapter from operator
intent to Make command. Make the terminal TUI and browser workflow UI consume
that Interface instead of recreating it.

Expected benefits:
Stage, action, preset, and variant changes gain Locality. Guided surfaces get
more Leverage from the workflow core, and tests can assert that every surface is
derived from one Interface.

## Deeper Exploration: Guided Workflow Contract

### Current Shape

The workflow core already exposes a substantial JSON Interface through:

```bash
scripts/platform-workflow.sh options --execute --output json
```

That Interface includes variants, variant classes, contexts, contracts, stages,
actions, apps, status facets, source precedence, preset groups, presets, and
configuration options.

The browser workflow UI already exposes that JSON at `/api/options`, but the
rendered UI still uses local Python constants and inline JavaScript for most of
the actual choices and rules. The terminal TUI has the same facts embedded in
Go.

### Duplicated Interface Facts

The same workflow facts currently appear in several Implementations:

| Workflow fact | Workflow core | Browser workflow UI | Terminal TUI |
| --- | --- | --- | --- |
| Variants | `workflow_options_json`, `target_path`, `validate_target` | `VARIANTS`, `variant_to_target`, guided cards | `screenTarget` menu |
| Stage list and labels | `workflow_options_json`, `validate_stage`, text options | `STAGES`, `stage_descs`, guided buttons | `screenStage` menu, `stageHint` |
| Action list | `workflow_options_json`, `validate_action`, `action_uses_stage` | `ACTIONS`, guided action buttons | `screenAction` menu |
| App toggle stages | stage metadata plus Bash logic | `APP_STAGES`, JS `stageDefault`, UI visibility | `stageHasAppToggles`, `stageDefault` |
| App defaults | preset/app-set logic in Bash rendering | `app_default`, JS `effectiveAppDefault` | `appDefault` |
| Preset groups | `workflow_options_json`, `set_preset`, render functions | `PRESET_GROUPS`, radio controls | preset bundle screen |
| Curated setup profiles | implicit in CLI preset combinations | `applySetupProfile` JavaScript | `applyPresetBundle` Go |
| Follow-on apply stages | absent from core options | `next_stages` Python | `nextItems` Go |
| Variant/action command mapping | `build_command_args` | `build_workflow_args` Python | `workflowArgs` Go |

This is the main Locality failure. A real workflow-language change currently
requires a maintainer to audit shell, Python, JavaScript, Go, and BATS/Python
tests.

### Deletion Test

Deleting the browser UI or terminal TUI would not delete workflow complexity;
it would push the same stage/action/preset logic back to the workflow core or
another caller.

Deleting `scripts/platform-workflow.sh` would make the complexity reappear
across every guided surface because it is the current Adapter from operator
intent to Make command.

Deleting the duplicated constants from the UIs would not remove behaviour. It
would concentrate behaviour behind the workflow Interface. That is the signal
that the contract Module would be deeper than the current per-surface lists.

### Proposed Module Shape

Create a `guided workflow contract` Module with a data Interface that the
workflow core and guided surfaces can all consume.

Candidate path:

```text
kubernetes/workflow/options.json
```

or:

```text
scripts/platform-workflow-options.json
```

The first path better matches the domain taxonomy because the guided workflow is
about the `kubernetes` solution. The second path is simpler for shell callers.
Either way, the Module should be source-controlled data, not generated output.

Initial Interface fields:

- `schema_version`
- `variants`
- `variant_classes`
- `contexts`
- `contracts`
- `stages`
- `actions`
- `apps`
- `preset_groups`
- `presets`
- `setup_profiles`
- `configuration_options`
- `ui_rules`

The current `workflow_options_json` Bash function becomes a reader/validator of
that contract instead of the owner of the data.

### What Stays Behind The Workflow Core Seam

The workflow core should remain the Adapter that turns operator intent into an
executable command. The data Module should not know how to execute Make or how
to render every generated tfvars line.

Keep these in `scripts/platform-workflow.sh` for now:

- CLI parsing and compatibility errors
- validation that needs runtime shell context
- generated operator tfvars rendering
- command preview and command execution
- state-lock preflight
- variant-specific runtime env values such as local registry host mapping

Move or derive these from the data Module:

- variants and paths
- stage ids, labels, contexts, contracts, and shortcuts
- action ids, labels, whether they use a stage, and whether they accept auto-approve
- app ids and the stages where app toggles are meaningful
- preset groups, allowed preset ids, labels, stage eligibility, and variant eligibility
- curated setup profiles used by both guided surfaces
- follow-on stage suggestions after successful apply

### Interface Additions Needed Before UI Consumption

The existing JSON is close but not quite enough for the guided surfaces to be
thin Adapters. Add:

```json
{
  "actions": [
    {
      "id": "apply",
      "label": "Apply",
      "uses_stage": true,
      "uses_auto_approve": true,
      "supports_app_toggles": true
    }
  ],
  "stages": [
    {
      "id": "700",
      "label": "app repos",
      "shortcut": "7",
      "app_toggles": true,
      "next_apply_stages": ["800", "900"]
    }
  ],
  "setup_profiles": [
    {
      "id": "idp-demo",
      "label": "IDP demo",
      "variant": "kind",
      "stage": "900",
      "presets": {
        "resource_profile": "local-idp-12gb",
        "image_distribution": "local-cache",
        "network_profile": "cilium"
      }
    }
  ]
}
```

The exact field names should align with `docs/ddd/ubiquitous-language.md`:
`variant`, `stage`, `preset`, `guided surface`, `workflow core`, and
`command preview`.

### Test Surface

The Interface is the test surface. Good tests after this refactor would be:

- `platform-workflow options --output json` validates against a schema.
- Every variant/stage/action accepted by the data contract previews
  successfully or carries an explicit unsupported reason.
- The browser workflow UI page contains choices derived from `/api/options`,
  not from local constants.
- The terminal TUI menus are built from the same options payload.
- Curated setup profiles produce the same workflow args in Python and Go as
  direct CLI invocation.
- App-toggle default logic is tested once against the contract, then smoke
  tested through each guided surface.

### Grilling Questions

These are the decisions to settle before implementing:

1. Should the contract live under `kubernetes/workflow/` because it describes
   the Kubernetes solution, or under `scripts/` because the workflow core is the
   first consumer?
2. Should setup profiles be first-class contract entries, or should they remain
   UI conveniences composed from preset groups?
3. Should the workflow core continue to emit all option data from Bash for one
   compatibility step, or should it immediately read the JSON contract?
4. Should `next_apply_stages` be domain data in the contract, or guided-surface
   behaviour derived from the stage ladder?
5. Should preset overlay rendering be tackled in the same pass, or kept as the
   follow-up candidate so this first change only deepens the workflow
   Interface?

### Decisions

1. The workflow contract lives under `kubernetes/workflow/` because it describes
   the Kubernetes solution guided workflow, not only the shell Adapter.
2. Setup profiles are kept as `guided_surface_profiles`: they are onboarding
   affordances over preset groups, not a stronger platform contract than the
   underlying preset Interface.
3. The Bash workflow core reads the JSON contract and continues to emit
   `options --output json`, so LLM agents and callers keep the same discovery
   entrypoint.
4. Follow-on apply stages remain guided-surface behaviour. They are recorded
   under `ui_rules`, not promoted to stage semantics.
5. The first implementation pass deepened the workflow Interface only. A
   follow-up pass then handled the additional Locality findings found while
   implementing it.

### Implementation Notes

Implemented first pass:

- Added `kubernetes/workflow/options.json` as the source-controlled guided
  workflow contract Module.
- Moved workflow option data out of `scripts/platform-workflow.sh`.
- Made the workflow core read the contract for options JSON, variant paths,
  stage/action validation, action auto-approve semantics, and preset allowed
  values.
- Made the browser workflow UI derive variants, stages, actions, preset groups,
  apps, and guided setup profiles from the contract.
- Made the terminal TUI derive variants, stages, actions, guided setup profiles,
  app-toggle stages, auto-approve semantics, and next-stage guided shortcuts
  from the same contract, with a fallback for startup resilience.

Additional findings handled in the follow-up pass:

- Moved preset overlay values into the workflow contract and made the Bash
  workflow core render generic HCL assignments from those data-backed overlays.
  Runtime values such as the local registry host still remain behind the Bash
  Adapter.
- Made browser workflow UI form/history payloads derive app names and app-set
  defaults from the contract instead of naming the current reference apps
  directly.
- Made the terminal TUI app-toggle flow derive app names, app defaults, and CLI
  overrides from the contract.
- Changed terminal TUI contract loading to walk up to the repo contract and to
  try `platform-workflow.sh options --output json` before using fallback data.
  The remaining fallback is now a minimal startup fallback, not a duplicate of
  guided profiles or next-stage behaviour.
- Added guided-surface metadata for variants, stages, actions, app labels,
  profile/action ordering, app-toggle hints, next-stage rules, and platform
  surface rows, then made the browser workflow UI and terminal TUI consume that
  metadata for guidance and display copy.

Residual finding:

- The terminal TUI still keeps a minimal no-contract fallback so it can start
  when neither the JSON contract nor the workflow script can be loaded. That
  fallback should remain startup-only and should not grow new guided behaviour.

### 2. Deepen Image Distribution Into An Image Catalog Module

Files:

- `scripts/platform-workflow.sh`
- `kubernetes/kind/scripts/render-operator-overrides.sh`
- `kubernetes/kind/scripts/build-local-platform-images.sh`
- `kubernetes/lima/targets/lima.tfvars`
- `kubernetes/slicer/targets/slicer.tfvars`

Problem:
Image intent is spread across workflow rendering, kind overrides, build
scripts, target tfvars, Terraform locals, and GitOps rewrites. The Image
Distribution seam has real Adapters, but the Interface is implicit and
scattered.

Candidate solution:
Introduce a declarative image catalog Module containing image id, role, source
fingerprint inputs, Dockerfile/context, build args, default tag strategy, and
per-variant registry Adapter facts. Generate tfvars refs, build loops, override
files, and golden tests from it.

Expected benefits:
Image rollout correctness gains Locality, tag drift becomes easier to prevent,
and new workloads or future variants get Leverage from one image intent
Interface.

### Implementation Notes

Implemented first pass:

- Added `kubernetes/workflow/image-catalog.json` as the source-controlled Image
  Distribution Interface for platform image ids, workload image ids, default
  tags, source fingerprint inputs, and variant registry hosts.
- Added `kubernetes/workflow/image-catalog-lib.sh` as a small Bash Adapter
  library for current shell scripts.
- Added an explicit `version_check` policy to each catalog image so floating
  local `latest` tags are declared as internal/non-comparable instead of being
  silently outside `check-component-version.sh` semantics.
- Made `kubernetes/kind/scripts/render-operator-overrides.sh` derive
  source-fingerprint tags and generated external image ref maps from the image
  catalog.
- Made `kubernetes/kind/scripts/build-local-platform-images.sh` derive
  source-fingerprint tags for `idp-core`, `platform-mcp`, `backstage`, and
  `keycloak` from the same catalog.
- Updated Docker optimization contract tests so source fingerprint assertions
  target the catalog instead of expecting the same source path lists to remain
  duplicated in each script.
- Added a Docker optimization contract test requiring every catalog image to
  declare its version-check policy.
- Added a catalog target-ref validator so Lima and Slicer external platform and
  workload image refs are checked against the image catalog instead of silently
  duplicating catalog values.

Additional findings deliberately left out of this pass:

- Build loops are still procedural in `build-local-platform-images.sh`; the
  catalog now owns fingerprint inputs, but Dockerfile/context/build-arg
  execution remains in the script.
- `keycloak_image` is a dedicated Terraform input rather than part of
  `external_platform_image_refs`, so the catalog marks Keycloak as not rendered
  into the external platform image map.
- `check-component-version.sh` still owns external image latest lookup,
  deployed/codebase/latest reporting, and preload image alignment. The catalog
  now declares that its local images are intentionally non-comparable, but it
  does not yet replace the version checker image Interface.

### 3. Deepen GitOps Rendering Behind A Render Contract

Files:

- `terraform/kubernetes/gitops.tf`
- `terraform/kubernetes/locals.tf`
- `terraform/kubernetes/scripts/sync-gitea-policies.sh`
- `kubernetes/kind/tests/sync-gitea-policies.bats`

Problem:
Terraform passes a wide environment Interface into
`sync-gitea-policies.sh`, while hash inputs and render inputs are maintained
separately. The shell Implementation then performs many imperative rewrites.
The renderer is necessary, but its Interface is too wide and under-structured.

Candidate solution:
Have Terraform emit a single `gitops_render_contract` JSON file under the run
dir. Make the renderer accept `--contract <file>`, leaving env vars only for
runtime Adapter details like Gitea access.

Expected benefits:
GitOps render intent gets one Interface, render hash inputs gain Locality, and
tests can move toward golden contracts plus rendered-tree assertions.

### Implementation Notes

Implemented first slice:

- Factored `local.policies_repo_render_contract` out of the render hash in
  `terraform/kubernetes/locals.tf`, so the hash and render intent now share the
  same Terraform object.
- Added a generated `.run` JSON artifact for the GitOps render contract and
  passed its path to `sync-gitea-policies.sh`.
- Made `sync-gitea-policies.sh` load render defaults from
  `GITOPS_RENDER_CONTRACT_FILE` while keeping Gitea credentials, local access,
  deploy keys, kubeconfig, and other runtime Adapter details in environment
  variables.
- Added a BATS test proving render inputs can come from the GitOps render
  contract.

Additional findings deliberately left out of this pass:

- The shell renderer still exposes the old env Interface for compatibility and
  tests. The contract path is now available, but the env Interface has not been
  deleted.
- Golden contract and rendered-tree tests are still future work. The current
  test proves contract loading, not full rendered output equivalence.
- App repo sync and review-environment workflow dispatch remain separate
  procedural Terraform local-exec paths.
