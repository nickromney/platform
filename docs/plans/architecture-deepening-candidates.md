# Architecture Deepening Candidates

<!-- markdownlint-disable MD013 -->

- Status: Draft
- Date: 2026-05-06
- Last reviewed: 2026-05-07
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

### 2. Deepen The Solution Variant Contract

Files:

- `kubernetes/kind/Makefile`
- `kubernetes/lima/Makefile`
- `kubernetes/slicer/Makefile`
- `kubernetes/workflow/options.json`
- `mk/stage-workflow.mk`
- `mk/k8s-terragrunt.mk`

Problem:
The repo has ratified `solution`, `variant`, `variant adapter`, `context`, and
`contract` language, but the implementation still keeps important variant facts
in parallel Makefile state. Kubeconfig path and context, state path, runtime
scope, registry host, host access path, blocker checks, readiness command, and
stage files are repeated across the three local variants. The current Modules
are shallow because the Interface for a variant is not one place; callers have
to learn the Makefile variables, workflow metadata, and variant scripts
together.

Candidate solution:
Create a first-class solution variant contract Module. The contract should
record the facts each adapter variant provides to the Kubernetes solution:
cluster access, state, stage ladder, registry, host access path, blockers, and
readiness. The existing variant Makefiles can remain the execution Adapters,
but they should consume or be generated from the same contract facts instead of
redeclaring them independently.

Expected benefits:
Variant changes gain Locality. Shared stage/apply behaviour gets more Leverage
because `kind`, `lima`, and `slicer` stop copying the same workflow Interface.
Tests can assert a variant contract matrix instead of treating each Makefile as
a separate source of truth.

### 3. Deepen The Readiness And Blocker Read Model

Files:

- `scripts/platform-status.sh`
- `scripts/platform-inventory.sh`
- `tests/platform-status.bats`
- `tests/assert-variant-active.bats`
- `kubernetes/workflow/options.json`

Problem:
`platform-status.sh` mixes host probing, ownership, readiness, blocker
construction, recommended actions, JSON projection, and text rendering.
Readiness and blocker language is real domain language, but the current Module
Interface is a large script output with many implied meanings.

Candidate solution:
Create a Local Stack Operations read-model Module with explicit ownership,
readiness facets, blockers, and recommended action projections. Shell status
output, inventory JSON, terminal TUI, and browser workflow UI should become
rendering Adapters over that read model.

Expected benefits:
Ownership and readiness changes gain Locality. Guided surfaces get more
Leverage from the same read model. Tests can exercise readiness and blockers at
the Interface instead of through several rendered surfaces.

### 4. Deepen The Host Access Path Contract

Files:

- `kubernetes/scripts/check-target-host-ports.sh`
- `kubernetes/kind/scripts/check-kind-host-ports.sh`
- `kubernetes/slicer/scripts/check-slicer-host-ports.sh`
- `kubernetes/lima/scripts/host-gateway-proxy.sh`
- `kubernetes/slicer/scripts/ensure-host-forwards.sh`
- `terraform/kubernetes/locals.tf`

Problem:
`host access path` is ratified as the umbrella for proxy, port-forward, and host
forward mechanics, but its Implementation is split across scripts, Make helper
modes, Terraform variables, and repeated port lists. The Seam is currently a
set of loose environment variables rather than a named contract.

Candidate solution:
Define a host access path contract with facts such as mode, gateway host port,
target port, public bind, admin NodePorts, required proxy or forward process,
degradation behaviour, and blocker message. Variant adapters should fill the
contract; checks and guided surfaces should project from it.

Expected benefits:
Ingress and local edge behaviour gain Locality. Host access tests gain Leverage
because they assert the contract once and then smoke-test each Adapter.

### 5. Deepen The Service Catalog Module

Files:

- `catalog/platform-apps.json`
- `apps/idp-core/app/main.py`
- `terraform/kubernetes/scripts/idp-catalog.sh`
- `terraform/kubernetes/scripts/idp-deployments.sh`
- `terraform/kubernetes/scripts/idp-secrets.sh`
- `schemas/idp/*.schema.json`

Problem:
The service catalog is now the source of application intent, but application
spec, environment request, deployment record, secret binding, and scorecard are
still implicit JSON conventions. Python routes and shell scripts each interpret
the catalog separately.

Candidate solution:
Add a service catalog Module with typed projections for application specs,
environments, deployment records, secret bindings, and scorecards. The portal
API and shell scripts should consume that Interface instead of embedding local
JSON traversal logic.

Expected benefits:
Catalog rule changes gain Locality. Portal API, scripts, SDK, MCP, Backstage,
and Grafana get more Leverage from the same projections. Tests can move from
string-level assertions to Interface-level catalog behaviour.

### 6. Deepen The Portal API Contract And Runtime Adapter

Files:

- `apps/idp-core/app/adapters.py`
- `apps/idp-core/app/models.py`
- `apps/idp-sdk/src/index.ts`
- `apps/idp-mcp/idp_mcp/server.py`
- `apps/backstage/catalog/entities.yaml`

Problem:
The runtime adapter currently mostly builds command strings, and SDK/MCP/
Backstage each hand-code partial portal API contract knowledge. As the portal
API grows, caller knowledge will spread unless the API contract and runtime
adapter Interface become deeper.

Candidate solution:
Make the portal API OpenAPI schema the canonical contract source for SDK/MCP/
Backstage validation or generation. Deepen `RuntimeAdapter` into a port that
models environment requests, deployment records, secret binding, and runtime
capabilities; Make commands should be one Adapter detail behind that seam.

Expected benefits:
Portal API changes gain Locality. SDK, MCP, Backstage, and tests get more
Leverage from the same contract. Missing runtime support, such as Slicer in the
current IDP adapter path, becomes a visible Adapter gap.

## Deeper Exploration: Solution Variant Contract

### Current Shape

The Kubernetes solution already has a metadata Interface in
`kubernetes/workflow/options.json`. It names variants, variant classes,
contexts, contracts, lifecycle mode, state scope, and readiness commands.

The executable Interface still lives mostly in the variant Makefiles:

- `kubernetes/kind/Makefile` owns kind-specific state files, kubeconfig facts,
  local registry host defaults, image distribution modes, and conflicting
  runtime checks.
- `kubernetes/lima/Makefile` owns Lima k3s bootstrap facts, host gateway proxy
  mode, image cache mode, state file, kubeconfig facts, and blocker checks.
- `kubernetes/slicer/Makefile` owns Slicer daemon/socket facts, VM sizing,
  network profile, host forwards, image cache mode, state file, kubeconfig
  facts, and blocker checks.

Shared Includes already exist, especially `mk/stage-workflow.mk` and
`mk/k8s-terragrunt.mk`, but they do not own the solution variant contract.
They assume the variant Makefile has already declared enough variables to make
the workflow valid.

### Duplicated Interface Facts

| Variant fact | Current locations |
| --- | --- |
| Variant id and path | `options.json`, variant Makefile path, status scripts |
| State file and lock file | each variant Makefile, workflow core state-lock helper |
| Kubeconfig path and context | each variant Makefile, status script defaults, docs |
| Stage ladder and stage files | `stage-ladder.mk`, variant Makefiles, `options.json` |
| Readiness command | `options.json`, variant Makefiles, status/inventory surfaces |
| Active-variant blockers | variant Makefiles, `kubernetes/scripts/assert-variant-active.sh`, status script |
| Registry runtime and push host | variant Makefiles, workflow core preset rendering, image cache scripts |
| Host access path | variant Makefiles, port/proxy/forward scripts, Terraform vars, docs |
| CNI/network profile | Slicer Makefile, workflow preset compatibility, stage files |

This is the Locality failure. A change to the variant Interface currently
requires a maintainer to inspect metadata, Make variables, shell scripts, docs,
and tests.

### Deletion Test

Deleting one variant Makefile would not delete the concept of a solution
variant. The same contract facts would have to reappear in a new Makefile,
workflow metadata, status probes, and scripts.

Deleting `options.json` would not delete variant complexity either, because the
Makefiles still know how to operate the variants. The signal is that the
contract is split: neither Module is deep enough to own the Interface alone.

Concentrating variant facts behind a solution variant contract would not remove
the adapter-specific Implementation. It would make the shared Interface stable
and leave kind, Lima, and Slicer to supply concrete adapter facts.

### Proposed Module Shape

Create a source-controlled variant contract per adapter variant, then use the
existing workflow options as the aggregated discovery Interface.

Candidate paths:

```text
kubernetes/variants/kind/variant.json
kubernetes/variants/lima/variant.json
kubernetes/variants/slicer/variant.json
```

or:

```text
kubernetes/workflow/variants/kind.json
kubernetes/workflow/variants/lima.json
kubernetes/workflow/variants/slicer.json
```

The first path makes `variant` a first-class Module. The second path keeps the
contract near the current workflow metadata. Either can work; the important
decision is that the variant facts are not copied by hand across Makefiles and
guided surfaces.

Initial Interface fields:

- `id`
- `path`
- `label`
- `class`
- `lifecycle_mode`
- `state_scope`
- `contexts`
- `state`
- `cluster_access`
- `stage_ladder`
- `readiness`
- `blockers`
- `registry`
- `host_access_path`
- `network_profile`
- `execution_adapter`

### What Stays Behind The Adapter Seam

Keep these in variant-specific Implementation:

- kind cluster creation and kubeconfig rewriting
- Lima VM lifecycle and k3s bootstrap
- Slicer daemon/socket/VM lifecycle
- concrete proxy or host-forward process management
- variant-specific reset and troubleshooting helpers

Move or derive these from the solution variant contract:

- paths and labels
- state file and lock file paths
- kubeconfig path and context defaults
- readiness command and readiness facets
- blocker list and conflicting variant checks
- local registry runtime and push host defaults
- host access path facts
- stage file mapping where it is not profile-dependent
- network profile capability and allowed values

### First Implementation Slice

The safest first slice is documentation plus contract validation:

1. Add per-variant contract JSON files with facts already present in the
   Makefiles.
2. Add a small validator that checks the contracts against the current
   Makefile-visible facts without changing execution.
3. Add tests that compare the contracts with `options.json` and the expected
   state/kubeconfig/registry/host-access facts.
4. Only after that, let `scripts/platform-workflow.sh options` aggregate from
   the variant contracts.
5. Later, use generated `variant.mk` or Make include fragments for low-risk
   Makefile convergence.

This avoids changing live stack operations in the first pass while making drift
visible.

### Implementation Notes

The first slice now exists:

- `kubernetes/variants/kind/variant.json`
- `kubernetes/variants/lima/variant.json`
- `kubernetes/variants/slicer/variant.json`
- `kubernetes/workflow/render-options.sh`
- `tests/variant-contracts.bats`

`scripts/platform-workflow.sh` still exposes the stable
`options --output json` Interface, but it now renders variant facts from the
per-variant contracts into `.variants[].variant_contract`. Stack execution is
unchanged: the Makefiles remain the execution Adapters.

The next implementation slice should reduce duplication without changing the
operator surface. Good candidates:

1. Move `target_state_lock_file` in `scripts/platform-workflow.sh` to read
   `.variant_contract.state.state_lock_file`.
2. Move local registry runtime host selection to
   `.variant_contract.registry.runtime_host`.
3. Add a generated or validated `variant.mk` fragment for state and kubeconfig
   defaults, then compare it with the hand-authored Makefile variables before
   allowing Make to consume it.

Items 1 and 2 are complete. A validation surface for item 3 now exists through
the shared `variant-contract-print` Make target. It prints the hand-authored
Makefile defaults for state, cluster access, and registry facts as JSON, and
`tests/variant-contracts.bats` compares that output with the source contracts.
This makes drift visible while keeping the Makefiles as the execution Adapters.

### Grilling Questions

These decisions should be settled before implementation:

1. Should the contract live under `kubernetes/variants/` as a first-class
   variant Module, or under `kubernetes/workflow/variants/` as workflow
   metadata?
2. Should the first pass only validate contract drift, or should it immediately
   make `options.json` aggregate from the per-variant contracts?
3. Should Make consume generated `variant.mk` fragments eventually, or should
   Make remain hand-authored with contract tests guarding drift?
4. Should `host_access_path` be a nested part of the variant contract now, or
   a separate Module after the variant contract lands?
5. Should Slicer network profile facts live in the variant contract, or in a
   later profile/preset Module?

## Implementation Progress

### Candidate 2: Solution Variant Contract

Implemented:

- `kubernetes/variants/*/variant.json` records the first-class variant
  contract for kind, Lima, and Slicer.
- `kubernetes/workflow/render-options.sh` renders workflow options with
  `.variants[].variant_contract` sourced from those files.
- `scripts/platform-workflow.sh` reads state-lock, registry runtime host,
  registry push host, and selected preset compatibility from the rendered
  contract instead of hardcoded variant cases.
- `mk/common.mk` exposes `variant-contract-print`, a narrow Makefile JSON
  projection for state, cluster access, and registry defaults.
- `tests/variant-contracts.bats` checks contract shape, workflow option drift,
  and Makefile default drift.

### Candidate 3: Readiness And Blocker Read Model

Implemented:

- `scripts/platform-status-read-model.sh` projects existing `platform-status`
  JSON into ownership, readiness, blockers, parsed blocker ownership, action
  facts, and recommended action facts.
- `tests/platform-status-read-model.bats` covers the projection without
  changing `platform-status.sh` behaviour.

This keeps the status script as the probing Adapter while creating a smaller
read-model Interface for future TUI/browser/status surfaces.

### Candidate 4: Host Access Path Contract

Implemented:

- `kubernetes/host-access/render-contracts.sh` projects host access facts from
  `kubernetes/variants/*/variant.json`.
- `tests/host-access-contracts.bats` validates kind, Lima, and Slicer modes,
  required proxy/forward processes, gateway ports, and shared host ports.

This keeps host access execution in the existing variant scripts while creating
a testable contract Interface for local ingress behaviour.

### Candidate 5: Service Catalog Module

Implemented:

- `apps/idp-core/app/catalog.py` adds typed catalog/read-model helpers for
  application specs, deployment records, secret bindings, and scorecards.
- `apps/idp-core/app/main.py` delegates derived read endpoints to those helpers
  while keeping raw catalog endpoints stable.
- `apps/idp-core/tests/test_catalog.py` covers projection defaults and
  extra-field preservation.

This concentrates service catalog projection rules behind one Module instead
of duplicating JSON traversal in each portal API endpoint.

### Candidate 6: Portal API Contract And Runtime Adapter

Implemented:

- `apps/idp-core/app/contracts.py` adds a portal runtime adapter contract
  projection and OpenAPI contract summary.
- `apps/idp-core/tests/test_contracts.py` covers supported runtimes,
  Makefile-backed runtime adapter metadata, portal API operation coverage, and
  the current Slicer runtime-adapter gap.

This makes the portal API/runtime Adapter contract explicit without changing
route behaviour.

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
- Added an explicit `version_check` policy to each catalog image and moved
  local catalog `default_tag` values to version pins. Checked-in target tfvars
  and generated workflow presets now render pinned local registry refs instead
  of `latest`.
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
- Added catalog-owned `build` specs for `idp-core`, `platform-mcp`,
  `backstage`, and `keycloak`, then made the kind local platform image builder
  resolve build context and Dockerfile facts from the Image Catalog Module
  instead of hard-coding those procedural build calls.
- Added catalog-owned workload build specs for `sentiment-api`,
  `sentiment-auth-ui`, subnetcalc frontends, subnetcalc API, APIM simulator,
  and the platform MCP image. Kind, Lima, and Slicer workload image builders now
  iterate the Image Catalog Module instead of carrying their own build list.
- Moved Grafana VictoriaLogs plugin image build inputs into the catalog,
  including base image refs, cache repos, plugin fetch image refs, archive
  verification inputs, and version tag strategy.
- Added an Image Catalog version-check projection consumed by
  `check-component-version.sh` so local and checked-elsewhere image policies
  are read from the catalog Interface.
- Added generated kind operator override validation against the catalog, with
  explicit allowance for source-fingerprint tags where the catalog owns
  fingerprint inputs.
- Corrected `platform-mcp` classification so the Image Catalog treats it as a
  platform image for kind, Lima, and Slicer external refs. The real kind
  `reset / 100 apply / 900 apply` path now renders `platform-mcp` from the host
  local platform cache and converges `mcp` to Synced/Healthy instead of pulling
  a missing Gitea workload image.
- Added `kubernetes/workflow/image-build-lib.sh` as the shared image-builder
  Adapter for Docker command assembly, build-arg resolution, cache-hit checks,
  tag pushing, and catalog build loops. Kind, Lima, and Slicer workload image
  builders now expose only variant runtime facts and consume that Adapter.
- Moved catalog build default-tag resolution into the Image Catalog Module, so
  catalog build loops build the pinned catalog tag by default instead of
  carrying `TAG=latest` through each variant builder.
- Added `kubernetes/workflow/image-catalog-context-lib.sh` as the generated
  build-context preparation Adapter. The Backstage catalog-copy rules now live
  next to the Image Catalog context Interface instead of inside the kind
  platform image builder.
- Extended the Image Catalog version-check projection with
  `preload_alignment_images`, including external latest lookup policy,
  checked-elsewhere metadata, and preload alignment policy for Argo CD,
  Prometheus, Grafana, Loki, Tempo, and VictoriaLogs. `check-component-version.sh`
  now drives those preload image checks from the catalog projection instead of
  hard-coding each image matcher in its preload loop.
- Extended the target-ref validator into a generator with `--print-expected`,
  so Lima and Slicer external platform/workload image maps can be rendered from
  the catalog Interface and compared against the checked-in target tfvars.

Additional findings deliberately left out of this pass:

- Build execution is still procedural in the variant image builder scripts; the
  catalog now owns build specs, fingerprint inputs, Grafana plugin inputs,
  shared Docker command assembly, cache probing, build-arg resolution, and
  generated Backstage context preparation. Grafana plugin archive preparation
  remains a kind platform image-builder Implementation detail.
- `keycloak_image` is a dedicated Terraform input rather than part of
  `external_platform_image_refs`, so the catalog marks Keycloak as not rendered
  into the external platform image map.
- `check-component-version.sh` still owns deployed/codebase/latest reporting
  and the external image audit over arbitrary Dockerfiles/manifests. The
  catalog now classifies local catalog image refs and drives preload alignment
  policy for known chart-backed images, but it does not replace the full
  version checker image Interface.
- Base GitOps manifests may still contain in-cluster placeholder refs such as
  `localhost:30090/...:latest`; those are render inputs, not catalog default
  tags or target tfvars refs.

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
- Removed Terraform's duplicate external image env assignments from the
  policies repo sync path so external workload/platform image refs now travel
  through `GITOPS_RENDER_CONTRACT_FILE` on the Terraform Adapter path while the
  shell renderer keeps env fallback compatibility for direct calls.
- Added a golden rendered-tree BATS test for contract-driven external workload
  and platform image rewrites.
- Added a Terraform test asserting external image refs are present in
  `local.policies_repo_render_contract` and that
  `local.policies_repo_render_hash` is derived from the contract JSON.
- Promoted external image contract key, env fallback, image id, and manifest
  group mappings into a render-input table inside `sync-gitea-policies.sh`.
- Removed chart, Grafana, VictoriaLogs plugin, and Signoz auth image render env
  duplication from `null_resource.sync_gitea_policies_repo`; those values now
  travel through `GITOPS_RENDER_CONTRACT_FILE` on the Terraform Adapter path.
- Added golden rendered-tree tests for gateway route host/header rendering,
  SSO and Backstage pruning, and Grafana chart values from the GitOps render
  contract.
- Added `local.app_repo_sync_contracts`, generated app repo sync contract JSON
  files, and a shared `sync-gitea-app-repo.sh` Adapter for sentiment and
  subnetcalc repo sync.
- Added a shared `review-environment-dispatch.sh` Module for Gitea Actions
  workflow dispatch and retry handling, then wired the sentiment/subnetcalc
  image wait paths through it.
- Added a review environment contract assertion covering namespace, registry
  secret, wildcard certificate SAN, runner labels, and branch workflow
  dispatch alignment.
- Promoted GitOps enablement and host render inputs into the same render-input
  table pattern used for external images. Terraform now carries those render
  values through `GITOPS_RENDER_CONTRACT_FILE`, while the policy repo sync
  environment is reduced to runtime Adapter details such as Gitea access,
  deploy keys, kubeconfig, and script paths.
- Split the policy repo renderer into a pure `render_policy_repo_tree` Adapter
  that writes a rendered directory and a separate Gitea push runtime Adapter.
  The pure renderer can now be sourced and exercised without Gitea admin
  credentials, deploy keys, or local access setup.
- Added a shared `wait-app-image-readiness.sh` Module for Gitea commit polling,
  Actions runner readiness, registry tag polling, workflow failure handling,
  and policies repo tag polling.
- Added generated app image readiness contract JSON files for sentiment and
  subnetcalc, paralleling app repo sync contracts. The Terraform wait resources
  now delegate repo, workflow, image, policy, and failure-consequence facts to
  the shared helper instead of carrying duplicated heredocs.
- Added `terraform/kubernetes/contracts/review-environment.json` as the
  source-controlled review environment substrate contract. Terraform reads this
  contract for namespace, registry secret, runner labels, and wildcard review
  certificate SAN derivation, and the Backstage template test now verifies the
  scaffolded workflow remains aligned with the same contract.
- Added `terraform/kubernetes/scripts/tofu-test-gitops-features.sh`, a bounded
  runner for `tests/gitops_features.tftest.hcl` that emits OpenTofu/provider
  diagnostics and terminates lingering processes when the test exceeds its
  wall-clock budget.

Additional findings deliberately left out of this pass:

- The shell renderer still exposes the old render env Interface for
  compatibility and direct-call tests. Terraform now uses the contract for
  external image refs, enablement, host values, chart versions, Grafana values,
  and Signoz auth image. Gitea push runtime values are isolated from pure
  rendering.
- Golden contract and rendered-tree tests now cover external images, gateway
  routes, SSO pruning, Backstage pruning, and Grafana chart values. Full render
  output is still not frozen as a repository tree fixture.
- App repo sync, review workflow dispatch, app image readiness, and review
  environment substrate facts now have shared contract Modules.

## Completed Follow-Up Items

1. Extend the Image Catalog Module to own workload build specs for
   `sentiment-api`, `sentiment-auth-ui`, subnetcalc frontends, subnetcalc API,
   and APIM simulator, then make variant workload image builders consume that
   Interface. Implemented.
2. Move Grafana VictoriaLogs plugin image build inputs into the Image Catalog
   Module, including base image refs, plugin fetch image refs, plugin archive
   policy, and version tag strategy. Implemented.
3. Add an Image Catalog version-check projection used by
   `check-component-version.sh` so local, external, checked-elsewhere, and
   non-comparable policies are read from one Module. Implemented for local
   catalog image classification.
4. Add generated kind operator override validation against
   `kubernetes/workflow/image-catalog.json`, matching the existing Lima/Slicer
   target-ref validator. Implemented.
5. Promote GitOps external image env fallback mapping into a small render-input
   Module inside `sync-gitea-policies.sh`, so contract keys, env fallback names,
   and manifest replacement ids live in one table. Implemented.
6. Remove more Terraform render env vars from
   `null_resource.sync_gitea_policies_repo`, starting with chart versions and
   observability image values already present in `local.policies_repo_render_contract`.
   Implemented for chart versions, Grafana values, VictoriaLogs plugin URL, and
   Signoz auth image.
7. Add golden GitOps render tests for gateway routes, SSO route pruning,
   Backstage removal, and Grafana chart value rendering. Implemented.
8. Move app repo sync contracts for `sentiment` and `subnetcalc` into a shared
   app repo sync Module instead of duplicating Terraform local-exec scripts.
   Implemented.
9. Factor workflow dispatch and retry handling for app repositories into a
   shared review-environment dispatch Module with a testable Interface.
   Implemented.
10. Add a review environment contract test that proves namespace, registry
    secret, wildcard certificate SAN, runner labels, and branch workflow
    dispatch stay aligned. Implemented.
11. Correct `platform-mcp` as a platform image across kind, Lima, and Slicer
    external refs, and prove the fix with the real kind stage-900 apply path.
    Implemented.
12. Promote GitOps enablement and host render inputs into a render-input table
    and remove those render-only values from the Terraform policy sync env
    Interface. Implemented.
13. Deepen the variant image builder Module further by moving Docker command
    assembly, cache-hit checks, and build-arg resolution behind one shared
    shell Adapter instead of keeping near-identical functions in kind, Lima,
    and Slicer. Implemented.
14. Move generated Backstage build-context assembly into an Image Catalog
    context-preparation Adapter so catalog facts and context copy rules stay in
    one Module. Implemented.
15. Extend the Image Catalog version-check projection to include external
    latest lookup policy, preload alignment policy, and checked-elsewhere
    metadata for non-local images. Implemented for chart-backed preload image
    alignment.
16. Finish the generated catalog projection for target tfvars and kind operator
    overrides so HCL ref maps are rendered from one Module instead of corrected
    by hand and tested after the fact. Implemented for Lima/Slicer target
    tfvars and the existing kind operator override renderer.
17. Split policy repo rendering into a pure rendered-tree Adapter that writes
    to a directory and a separate Gitea push Adapter, so golden tests can cover
    the full tree without Gitea runtime details. Implemented.
18. Replace the sentiment/subnetcalc wait-image heredocs with a shared app
    image readiness Module for Gitea API polling, runner readiness, registry
    tag polling, and policy repo tag polling. Implemented.
19. Add contract JSON files for app image readiness, paralleling app repo sync
    contracts, so sentiment and subnetcalc wait paths stop hand-assembling
    repo, image, policy, and consequence facts. Implemented.
20. Move review environment substrate facts into a source-controlled contract
    file consumed by Terraform, the Backstage template, and tests, instead of a
    Terraform-only local. Implemented.
21. Add a bounded Terraform test strategy for GitOps feature tests so provider
    hangs produce actionable diagnostics without masking completed assertions.
    Implemented with a timeout wrapper for `tests/gitops_features.tftest.hcl`.
22. Replace local catalog `latest` defaults with version-pinned default tags
    and make catalog build loops resolve their default build tag from the Image
    Catalog Module. Implemented for kind, Lima, Slicer, Docker Desktop, workflow
    presets, and generated target projections.

## Next Architecture Deepening Items

1. Add full rendered-tree golden fixtures for the policy repo after the pure
    renderer exists, covering the complete `apps/` and `cluster-policies/`
    output for a small set of GitOps render contracts.
