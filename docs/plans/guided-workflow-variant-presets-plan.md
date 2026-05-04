# Guided Workflow Variant Presets Plan

<!-- markdownlint-disable MD013 -->

- Status: Draft, revised after review
- Date: 2026-05-03
- Scope: Kubernetes solution guided workflow, browser workflow UI, terminal TUI,
  staged Terraform/OpenTofu configuration, presets, generated operator tfvars,
  readiness, deployment read models, and future variant organisation
- Review provenance:
  [guided-workflow-variant-presets-addendum.md](guided-workflow-variant-presets-addendum.md)
- Architecture stress test:
  [variant-capable-kubernetes-workflow-architecture.md](variant-capable-kubernetes-workflow-architecture.md)

## Purpose

The browser workflow UI and terminal TUI should make the staged Kubernetes
solution easier to understand and operate without becoming a second Terraform
interface.

The durable operator model remains:

- choose the `kubernetes` solution
- choose a solution variant
- choose a cumulative stage from `100` through `900`
- choose an action such as readiness, plan, apply, status, or reset
- optionally apply named presets and a small set of understandable overrides
- preview the exact command and generated tfvars before any mutating action
- stream command output and expose diagnostics while the command runs
- query what appears to be deployed after or between runs

The guided surfaces should be "batteries included but optional": opinionated
defaults for learners, explicit escape hatches for operators who want to tune
the stack.

## Vocabulary Guardrails

Use the ratified DDD vocabulary from
`docs/ddd/ubiquitous-language.md`.

| Term | Use in this plan |
| --- | --- |
| solution | The first-level grouping, currently `kubernetes`. |
| variant | The concrete operable path beneath a solution, such as `kubernetes/kind`, `kubernetes/lima`, or `kubernetes/slicer`. |
| target | Makefile and workflow-core implementation noun. Keep it in CLI compatibility surfaces where it already exists. |
| stage | The cumulative build ladder, `100` through `900`. |
| preset | A named overlay of choices on top of a stage baseline and variant default. |
| preset group | A category where at most one preset is active, such as resource profile or observability stack. |
| option | A single configurable value that can render to tfvars, env vars, command flags, or UI-only metadata. |
| readiness | Whether a variant can be safely operated now. Existing `prereqs` targets remain as compatibility entrypoints. |
| generated operator tfvars | Temporary override files under `.run/operator/`, not long-term platform intent. |
| deployment read model | Query-side view of what is deployed and healthy. |

The guided surfaces should say `variant` to users. The workflow core can keep
`--target` for compatibility, but its JSON should add `variants` and eventually
treat `targets` as a legacy alias.

## Current Problems

1. The guided surfaces currently expose only two app toggles,
   `sentiment` and `subnetcalc`, and those toggles consume too much attention
   compared with variant, stage, readiness, and preset choices.
2. The web UI, TUI, and workflow core duplicate the same vocabulary and stage
   rules in shell, Python, JavaScript, and Go.
3. `950-local-idp` behaves like a stage in the workflow, but it is really a
   resource-oriented overlay on top of a late-stage IDP path.
4. The stage tfvars are cumulative, but the UI has no machine-readable model of
   which option belongs to which stage, which dependency it has, whether it is
   variant-specific, or whether changing it could rebuild the cluster.
5. The current folder shape asks users and agents to think about
   `kubernetes/kind`, `kubernetes/lima`, and `kubernetes/slicer` before the UI
   can explain what those variants mean.
6. There is no structured inventory command that answers "what did I deploy?"
   across Terraform state, Argo CD, and live Kubernetes resources.
7. There is no separate model for mid-apply progress versus post-apply
   inventory.
8. The default UI view needs a complexity budget so progressive disclosure does
   not become accidental overexposure.

## Design Principles

1. Keep Makefiles authoritative for execution.
2. Keep Terraform/OpenTofu authoritative for infrastructure intent.
3. Keep the stage ladder visible and stable.
4. Put complexity behind progressive disclosure, not behind hidden magic.
5. Prefer inline risk explanations over modal warnings.
6. Render web UI and TUI from the same workflow metadata.
7. Preserve direct Makefile usage for experienced operators.
8. Treat `kind` as the reference teaching variant and Lima/Slicer as adapter
   variants unless a later ADR changes that.
9. Treat presets as overlays, not new stages.
10. Treat generated tfvars as derived output that can be previewed and deleted.

## Stage, Preset, And Override Model

### Stage

A stage is the cumulative baseline:

| Stage | Label | Meaning |
| --- | --- | --- |
| `100` | cluster available | Variant-specific cluster bootstrap boundary. |
| `200` | Cilium | CNI layer where supported. |
| `300` | Hubble | Cilium visibility layer where supported. |
| `400` | Argo CD | GitOps controller. |
| `500` | Gitea | Internal Git provider. |
| `600` | policies | Policy and certificate foundations. |
| `700` | app repos | App sources and app deployment manifests. |
| `800` | observability | Gateway TLS, monitoring, dashboards, and operator surfaces. |
| `900` | SSO | Identity, access proxying, and authenticated portal surfaces. |

The stage ladder should remain numeric and cumulative. It is the learning path.

Do not add `000` to the ladder. The things that feel like stage `000` are
readiness and variant preparation:

- tool availability
- Docker Desktop memory
- Lima or Slicer daemon state
- host-port ownership
- local image cache availability
- Terraform/OpenTofu binary choice
- kubeconfig selection for existing clusters

These belong in a pre-stage readiness panel. Stage `100` remains the first
infrastructure outcome: cluster available.

### Preset

A preset is a named overlay applied after the stage baseline and variant
defaults, and before custom overrides.

Presets should sit beside the stage ladder, not inside it. A user should be
able to say:

- variant: `kind`
- stage: `900`
- resource profile: `local-idp-12gb`
- image distribution: `local-cache`
- observability stack: `minimal-observability`
- app set: `reference-apps`
- custom override: `worker_count=2`

Use one active preset per preset group. This avoids combinatorial names such as
`local-idp-12gb-no-reference-apps-lgtm-cache` while still letting the user
compose choices deliberately.

Preset merge order:

1. stage baseline
2. variant defaults
3. resource profile preset
4. image distribution preset
5. network profile preset
6. observability stack preset
7. identity stack preset
8. app set preset
9. custom user overrides

The preview must show the effective value and source for every option that is
not hidden as internal implementation detail.

| Preset group | Examples | Stage relationship |
| --- | --- | --- |
| Resource profile | `local-full`, `local-12gb`, `minimal`, `airplane` | Can affect many stages, especially `100`, `700`, `800`, and `900`. |
| Image distribution | `pull`, `local-cache`, `preload`, `baked`, `airplane` | Usually affects `100` and workload deployment. |
| Network profile | `cilium`, `default-cni` | Chosen at or before stage `100`, visible through later stages. |
| Observability stack | `victoria`, `lgtm`, `minimal-observability`, `none` | Eligible once stage `800` is selected. |
| Identity stack | `keycloak`, `dex`, `external-oidc` | Eligible once stage `900` is selected. |
| App set | `reference-apps`, `no-reference-apps`, `custom-local-apps` | Eligible once stage `700` is selected. |

Options such as "Grafana LGTM instead of VictoriaLogs" belong to the
observability-stack preset group under the stage `800` capability. They should
not become new stage numbers.

### Override

An override is a user-specific value that wins over stage, variant, and preset
defaults.

Overrides should render to generated operator tfvars under `.run/operator/`.
Saved profiles may persist named override sets, but generated files remain
derived artifacts.

The UI should show an effective configuration summary:

| Source | Example |
| --- | --- |
| Stage default | Stage `900` enables SSO. |
| Variant default | Slicer may select a different host access path. |
| Preset overlay | `local-idp-12gb` disables heavier observability defaults. |
| Custom override | User sets `worker_count = 2`. |

## Replace `950-local-idp` With A Preset Alias

The current `950-local-idp` naming is unclear because it looks like a new stage
after SSO. The useful behavior is not really "stage 950". It is a late-stage
IDP experience tuned for constrained local resources.

The replacement model should be:

- canonical stage: `900`
- canonical resource profile preset: `local-idp-12gb`
- optional display label: `Local IDP, 12 GB`
- compatibility alias: `950-local-idp`

Avoid the term `lite` unless the docs define precisely what is lightweight. A
better description is:

> Runs the local IDP and portal path on a 12 GB Docker Desktop budget by
> disabling or externalizing the heaviest optional pieces.

Compatibility rule:

- accept `950-local-idp` in the workflow core for one planned compatibility
  window after the schema ships
- render it as `stage=900,preset=local-idp-12gb` in preview JSON
- mark it deprecated in the schema once a `deprecated` field exists
- remove it from default UI pickers before removing CLI compatibility

## Resolved Platform Surface Decisions

### Backstage

Backstage should be modelled as a stage `900` platform surface unless a
deliberate non-SSO Backstage mode is added later.

Rationale:

- the current Terraform effective flag is gated by SSO and Argo CD
- the useful local developer portal path depends on Keycloak/oauth2-proxy
- exposing it at stage `700` would imply either a broken route or a second auth
  mode that does not currently exist as a product decision

Schema implication:

- `enable_backstage` is introduced at stage `900`
- dependencies include `enable_sso` and `enable_argocd`
- resource presets may default it on or off
- the Apps panel can mention the developer portal as a platform surface, but it
  should not be treated as a plain stage `700` demo app

### APIM Simulator

The APIM simulator must be represented explicitly.

It is already a service catalog entry and a deployed platform/demo capability,
not just an incidental part of subnetcalc. The option schema should distinguish:

- `apim-simulator` as API mediation/platform capability
- `subnetcalc` as a reference workload that may use APIM
- app-set presets that include or exclude the reference workload set

Initial rule:

- `apim-simulator` becomes meaningful at stage `700` with app repos
- it depends on Argo CD and the GitOps app path
- if SSO is enabled later, APIM can participate in the authenticated route and
  token validation story

## Effective Config Audit Before Schema Work

Do not start by inventing `kubernetes/workflow/options.yaml` directly. First
audit the effective configuration landscape.

The original implementation hurdle remains real: not all options are exposed
atomically in the `100` through `900` stage tfvars, and some user-visible
choices currently flow through Makefile variables, generated operator overrides,
or Terraform locals.

Audit these inputs:

- `kubernetes/*/stages/*.tfvars`
- `kubernetes/*/targets/*.tfvars`
- `kubernetes/*/profiles/*.tfvars`
- `kubernetes/slicer/stages/default-cni/*.tfvars`
- `kubernetes/kind/scripts/render-operator-overrides.sh`
- variant Makefiles and exported `TF_VAR_*` values
- Terraform variables and validation blocks
- Terraform locals that turn raw variables into effective behavior
- service catalog app entries

The audit should produce a flat table with:

| Field | Meaning |
| --- | --- |
| `variable` | Terraform variable, env var, Make variable, or catalog field. |
| `type` | Boolean, integer, string, enum, path, map, list, or derived. |
| `variants` | Variants where it applies. |
| `introduced_at_stage` | First stage where it matters. |
| `stage_files` | Stage tfvars where it appears. |
| `target_files` | Target tfvars where it appears. |
| `profiles` | Profiles that override it. |
| `generated_by` | Script or Makefile that writes it, if any. |
| `operator_controllable` | Yes, no, or needs Terraform/module work. |
| `impact` | Cluster rebuild, Terraform reconcile, GitOps reconcile, or read-only. |
| `notes` | Dependencies, validation rules, or portability constraints. |

This audit becomes the empirical basis for the schema. Variables not currently
controllable should be marked out of scope until the Terraform or wrapper layer
is changed.

## Option Schema

Introduce one machine-readable workflow schema after the effective config audit.
The initial implementation can be a JSON or YAML file consumed by
`scripts/platform-workflow.sh`, or generated by the workflow core from shell
data. The important contract is that all guided surfaces consume the same
metadata.

Candidate path:

```text
kubernetes/workflow/options.yaml
```

Candidate generated output:

```sh
scripts/platform-workflow.sh options --output json
```

Required top-level sections:

- `schema_version`
- `solutions`
- `variants`
- `stages`
- `preset_groups`
- `presets`
- `options`
- `dependencies`
- `actions`
- `docs`
- `compatibility_aliases`

Each option should include:

| Field | Purpose |
| --- | --- |
| `id` | Stable option identifier for UI/TUI state. |
| `label` | Human-readable label. |
| `group` | UI grouping such as `cluster`, `network`, `apps`, `observability`, or `identity`. |
| `type` | Boolean, integer, string, enum, path, list, or map. |
| `tfvar` | Terraform variable name when the option renders to tfvars. |
| `env` | Environment variable name when the option renders to env. |
| `make_variable` | Make variable name when the option must flow through Make. |
| `introduced_at_stage` | First stage where the option becomes meaningful. |
| `applies_to_variants` | Variant allow-list or deny-list. |
| `default_by_stage` | Stage-specific defaults where needed. |
| `default_by_variant` | Variant-specific defaults where needed. |
| `default_by_preset` | Preset-specific defaults where needed. |
| `dependencies` | Other options or stages required for the value to work. |
| `impact` | `cluster_rebuild`, `terraform_reconcile`, `gitops_reconcile`, or `read_only`. |
| `portable_to_hosted` | Whether the option should appear for future hosted variants. |
| `docs_url` | Local docs path or external reference. |
| `advanced` | Whether to hide behind advanced disclosure by default. |
| `deprecated` | Compatibility metadata for aliases such as `950-local-idp`. |

The schema should be source of truth for:

- web UI controls
- TUI prompts
- `preview` risk badges
- generated operator tfvars
- preset merge order
- docs snippets for available options
- BATS fixtures that verify the guided surfaces stay aligned

## Portability Matrix

Hosted and bare-metal variants should not force a schema redesign later. Mark
each option group with portability from the start.

| Option group | Portable to hosted variants | Notes |
| --- | --- | --- |
| Cluster resource profile | No | Memory and node count are provider-managed or cluster-provider-specific. |
| Image distribution | Partially | Pull and external image refs apply; local cache, preload, and baked node images are local-runtime concepts. |
| Local registry URL | No | The port `5002` cache is a local operator service, not hosted infrastructure. |
| Network profile | Partially | CNI choice may be locked by AKS/EKS/GKE or by a bare-metal baseline. |
| Observability stack | Yes | Mostly independent of substrate once Kubernetes is reachable. |
| Identity stack | Yes | Mostly independent of substrate, though ingress and DNS differ. |
| App set | Yes | Independent of substrate once registry and ingress assumptions are satisfied. |
| OpenTofu vs Terraform | Yes | Binary choice for execution, not a cluster feature. |
| Host access path | No | Local proxy, port-forward, and host-forward mechanics are variant-specific. |

This table should feed `applies_to_variants` and future variant definitions.

## Local Image Cache And Registry Options

The local image cache is concrete and should be named.

Current defaults include port `5002`, but different actors see different host
names:

- host push path: usually `127.0.0.1:5002`
- kind runtime pull path: usually `host.docker.internal:5002`
- Lima runtime pull path: usually `host.lima.internal:5002`
- Slicer runtime pull path: variant-derived gateway address or explicit cache
  host

Model this as separate options rather than a single ambiguous string:

| Option | Meaning |
| --- | --- |
| `local_registry_enabled` | Whether the local cache is used. |
| `local_registry_push_host` | Host-side push address, default `127.0.0.1:5002`. |
| `local_registry_runtime_host` | Address pods or containerd use to pull images. |
| `local_registry_scheme` | Usually `http` for local cache. |
| `image_distribution_mode` | Pull, local cache, preload, baked, or hybrid. |

The `local-cache` preset should set these defaults per variant instead of
burying `5002` in profile files or scripts.

The `airplane` preset should be stricter than `local-cache`: it should prefer
preflight synchronization and should fail early if required images are missing
from the local cache, rather than falling back to internet pulls.

## UI Plan

### Default View Complexity Budget

The default view should stay simple.

Default view, with nothing expanded:

- variant recommendation with readiness indicator
- stage selector
- active preset summary
- action selector
- readiness button
- command preview button
- latest command status if a command is running

Everything else is behind explicit expansion:

- stage panels
- app set controls
- observability stack controls
- identity stack controls
- advanced overrides
- generated tfvars
- raw diagnostic output
- deployment inventory details

The operator should be able to run a basic sequence without expanding anything:

```text
readiness -> plan -> apply
```

This is an acceptance criterion for the browser UI.

### First Screen

Show a compact operator cockpit:

- solution: `kubernetes`
- recommended variant, with readiness summary
- stage selector
- one-line active preset summary
- action selector
- readiness button
- command preview button

The UI should not begin by asking whether `subnetcalc` or `sentiment` should be
deployed. Those are stage `700` app-set choices.

### Stage Ladder

Render the ladder vertically:

- previous stages expanded enough to show effective choices when the operator
  opens them
- current stage open by default only after the operator expands the ladder
- future stages greyed and collapsed but readable
- `Expand all` and `Collapse all` controls
- per-stage badges for `stage default`, `variant`, `preset`, `custom`, and
  `risky`

If the selected stage is `200`, stage `100` remains visible because those
choices affect the substrate. If the user edits a stage `100` value while
planning stage `900`, show inline risk text:

> This may recreate or restart the cluster because it changes the bootstrap
> boundary.

### Apps And Platform Surfaces Panel

Move app choices into a stage `700+` panel, but distinguish app workloads from
platform surfaces.

Initial app workload entries:

- `hello-platform`
- `sentiment`
- `subnetcalc`
- future custom local app specs

Initial platform or mediation entries:

- `apim-simulator`
- Backstage / developer portal, introduced at stage `900`
- IDP core / portal API, introduced at stage `900`
- platform MCP, where enabled by the IDP path

Do not hardcode app toggles in the UI. Use the service catalog plus workflow
option schema to decide which entries are selectable, which are informational,
and which are locked by dependencies.

### Presets Panel

The default view shows a compact active-preset summary. The expanded Presets
panel shows one picker per preset group:

- resource profile
- image distribution
- network profile
- observability stack
- identity stack
- app set

Initial preset candidates:

- `default`
- `minimal`
- `local-idp-12gb`
- `airplane`
- `no-reference-apps`
- `local-cache`
- `pull`
- `observability-victoria`
- `observability-lgtm`
- `observability-minimal`
- `identity-keycloak`
- `identity-dex` if still supported by the Terraform path

Invalid preset/stage/variant combinations should be visible but locked with a
short inline reason.

### Readiness And Diagnostics

The readiness button should run the existing focused readiness/prereqs target
for the selected variant and stream console output. The output is valuable
because it already includes remediation commands for missing tools and active
variant conflicts.

On failure, show:

- exit code
- command
- last relevant output
- blocker summary from status JSON where available
- docs links
- copyable diagnostic bundle

The diagnostic bundle should include:

- variant
- stage
- active presets
- action
- generated tfvars excerpt
- exact command
- exit code
- status JSON excerpt
- last N lines of stdout/stderr
- recent Kubernetes events if available
- links to local docs

This supports the Nextra-style "copy this into your LLM" workflow without
building an LLM integration into the platform.

## HTMX Fit And Boundary

HTMX is flexible enough for the revised guided workflow, provided the UI keeps
server-owned truth on the server.

Use HTMX for:

- server-rendered preview fragments
- effective config summaries
- stage panel fragments
- readiness command output
- job polling
- mid-apply progress grid refresh
- post-apply inventory refresh
- out-of-band updates for command history or status badges

Use small local JavaScript for:

- expand all / collapse all
- preserving which `<details>` panels are open
- copy buttons
- output follow/pause
- keyboard shortcuts, if added

Do not use HTMX as a client-side state store. The canonical state should be:

- form values in the browser
- parsed and validated by the workflow UI server
- resolved against workflow schema
- previewed by `scripts/platform-workflow.sh`
- rendered back as HTML fragments

If the UI starts needing rich local graph editing, drag/drop layout, or
offline mutation queues, revisit the frontend choice. The stage ladder,
show/hide controls, progressive disclosure, job streaming, and polling status
panels do not require React/Vue/Svelte.

## Mid-Apply Progress

Mid-apply progress is not the same as post-apply inventory.

While a command is running, the UI should show two independent streams:

- command output from the running Makefile/workflow command
- progress grid refreshed from read-only Kubernetes and Argo queries

The progress grid should poll on a slower interval than command output, such as
every 5 to 10 seconds, and should tolerate resources not existing yet.

Minimum progress signals:

- node ready/not-ready count
- namespace existence for expected stage capabilities
- pod phase counts by namespace
- deployments/statefulsets available versus desired
- Argo CD application sync and health status, when Argo exists
- Gateway and HTTPRoute accepted/programmed conditions, when Gateway API exists
- recent warning events

The progress grid must be labelled as observed live state, not as Terraform
truth.

## Deployment Read Model

Add a read-only inventory command for the GUI/TUI to answer:

> What appears to be deployed right now?

Candidate command:

```sh
scripts/platform-inventory.sh --variant kind --stage 900 --output json
```

The command should combine:

- current status JSON
- selected stage and effective option sources
- `terraform show -json` when state exists
- Kubernetes nodes, namespaces, pods, deployments, statefulsets, HTTPRoutes,
  Gateways, certificates, and Argo CD Applications
- known service catalog entries and their expected environments
- available URLs from existing `show-urls` helpers

Minimum health summary:

- node ready/not-ready count
- pod phase counts by namespace
- CrashLoopBackOff, ImagePullBackOff, failed, and pending counts
- certificate expiry within 7 days
- Argo CD application sync and health status per app
- HTTPRoute and Gateway accepted/programmed conditions

Terraform state alone is not enough because much of the live shape is
reconciled by Argo CD and Kubernetes controllers after Terraform bootstraps the
GitOps path.

## Folder Organisation Options

The current repo already has a shared Terraform module under
`terraform/kubernetes` and variant-specific operator folders under
`kubernetes/kind`, `kubernetes/lima`, and `kubernetes/slicer`.

The question is whether the operator-facing folder layout should converge.

### Option A: Keep Variant Folders, Move Shared Intent Up

This is the recommended first step.

Keep:

```text
kubernetes/kind
kubernetes/lima
kubernetes/slicer
```

Add shared workflow intent:

```text
kubernetes/workflow/options.yaml
kubernetes/workflow/presets/*.yaml
kubernetes/workflow/stages/*.yaml
kubernetes/workflow/variants/*.yaml
```

Variant folders keep:

- Makefile entrypoints
- variant-specific readiness checks
- stage `100` bootstrap mechanics
- variant target tfvars
- compatibility wrappers

Shared workflow metadata owns:

- stage labels
- preset definitions
- option metadata
- dependency rules
- UI grouping
- risk labels

Pros:

- lowest migration risk
- preserves current confidence paths
- aligns with ADR 0002
- avoids breaking direct `make -C kubernetes/kind ...` users
- enables the UI/TUI work immediately

Cons:

- users can still see multiple variant folders
- some stage tfvars duplication remains until generation or consolidation is
  added

### Option B: Single Kubernetes Operator Folder

Move toward:

```text
kubernetes/
  Makefile
  workflow/
  variants/
    kind/
    lima/
    slicer/
  stages/
  presets/
```

Operator command shape:

```sh
make -C kubernetes VARIANT=kind STAGE=900 apply
make -C kubernetes VARIANT=slicer STAGE=900 PRESET=airplane apply
```

The old folders become compatibility shims:

```sh
make -C kubernetes/kind 900 apply
```

Pros:

- the folder structure matches the DDD solution/variant taxonomy
- one visible entrypoint for the Kubernetes solution
- easier for the browser UI to explain "choose a variant" without exposing path
  selection first

Cons:

- larger migration
- more Makefile compatibility surface
- higher risk of breaking scripts and docs that use the old paths
- should happen only after the schema exists and tests lock down behavior

### Option C: Variant Adapter With Shared Platform Stack

Split the implementation so each variant adapter satisfies explicit contracts
and the shared platform stack consumes those contracts. Stage `100` can remain
the teaching stage for "cluster available" without forcing every future
provider to use the same Terraform root or state layout.

Possible shape:

```text
terraform/kubernetes-adapters/
  kind/
  lima/
  slicer/
  existing/
terraform/kubernetes-stack/
  stages/
  capabilities/
```

The adapter side would output:

- kubeconfig path
- kubeconfig context
- cluster name
- variant facts
- ingress or host access facts
- image distribution facts
- lifecycle mode and state scope
- supported capability flags

The stack side would consume those facts and apply Cilium, Hubble, Argo CD,
Gitea, policies, apps, observability, and SSO where supported. Future hosted or
bare-metal variants may satisfy the same contracts with several Terraform roots,
provider APIs, scripts, or external inputs rather than one large Terraform
module.

Pros:

- conceptually clean
- useful for future hosted or bare-metal variants
- makes `existing` a first-class variant
- reduces pressure to encode every substrate difference in one Terraform module

Cons:

- highest implementation risk
- Terraform provider configuration and Terragrunt dependency ordering need care
- current shared module already works across variants
- stage `100` and later stages are not perfectly separable because networking,
  image distribution, host access, and CNI choices leak across the boundary

Recommendation: defer this until Options A and B prove the workflow contract.
The UI/schema work should make this refactor easier later, but it should not be
the first move.

## Abstracting Folder Choice In The UI

The UI can abstract folder choice without immediately changing the repo layout.

Instead of asking users to choose a folder, ask for a variant:

- `kind`: reference teaching variant
- `lima`: adapter variant for Lima-backed k3s
- `slicer`: adapter variant for Slicer-backed k3s
- future `existing`: adapter variant for an already reachable Kubernetes
  cluster

Use readiness data to recommend a variant:

- Docker available and no conflicting ownership: recommend `kind`
- Lima VM available and Docker Desktop unavailable: recommend `lima`
- Slicer daemon healthy and selected by operator: recommend `slicer`
- existing kubeconfig selected: recommend `existing`

Do not silently switch variants for mutating actions. Show the recommendation
and require the operator to preview the command.

## OpenTofu And Terraform Choice

OpenTofu should remain the default. Terraform compatibility should be exposed as
an advanced early option:

- label: IaC engine
- default: OpenTofu
- allowed values: `tofu`, `terraform`
- impact: `terraform_reconcile`
- UI group: advanced readiness or execution settings

The workflow core should validate the selected binary during readiness and show
the exact command in preview.

## Custom Local Apps

Custom app folders should not be a one-off UI path field that bypasses the rest
of the platform model.

Add this in two steps:

1. Extend the service catalog/application spec model so a local app folder can
   be represented as app intent.
2. Let the Apps panel choose catalog apps plus one or more local app specs.

The generated operator tfvars should only carry enough information for the
existing Terraform/GitOps render path to include those apps. The longer-term
owner should be the service catalog and IDP environment machinery.

## Implementation Plan

### Phase 0: Effective Config Audit

Deliverables:

- flat inventory of all stage, target, profile, generated override, Make/env,
  Terraform variable, Terraform local, and catalog-controlled options
- classification of each variable by variant, stage, source, type,
  controllability, impact, and portability
- explicit Backstage placement decision recorded as stage `900` platform surface
- explicit APIM simulator classification recorded as API mediation/platform
  capability
- explicit local cache defaults for push host and runtime host per variant

Done criteria:

- the audit table exists and is committed alongside the plan
- every variable the schema will expose has a confirmed source and render path
- variables not yet controllable are marked out of scope with notes on the
  required Terraform or wrapper changes
- the schema author does not need to infer behavior from scattered tfvars

### Phase 1: Shared Workflow Schema

Deliverables:

- add `kubernetes/workflow/options.yaml`
- add schema validation tests
- update `scripts/platform-workflow.sh options --output json` to emit
  `variants`, `stages`, `preset_groups`, `presets`, `options`,
  `compatibility_aliases`, and legacy `targets`
- update web UI and TUI tests to consume fixture output
- keep execution behavior unchanged

Done criteria:

- stage order is generated from one source
- variant labels are generated from one source
- `target` remains accepted by CLI compatibility paths
- `950-local-idp` is exposed as a compatibility alias for
  `stage=900,preset_group.resource_profile=local-idp-12gb`
- schema fixtures cover at least kind, Lima, Slicer, and Slicer default-CNI

### Phase 2: Generic Override Rendering And Precedence

Deliverables:

- replace hardcoded app-only override rendering with schema-driven rendering
- render generated operator tfvars for boolean, enum, integer, string, path,
  list, and map options
- define and test preset merge order
- fix kind tfvars layering so explicit user overrides cannot be silently
  clobbered by generated operator/runtime overrides
- add tests for `worker_count`, app toggles, Backstage, APIM simulator, local
  registry/cache, image distribution, and observability profile choices

Done criteria:

- preview shows the generated tfvars content
- apply uses the same file previewed to the operator
- runtime-detected values and user-selected values have explicit precedence
- invalid preset/stage/variant combinations fail before mutating actions

### Phase 3: Browser UI Stage Ladder

Deliverables:

- render variant, stage, preset groups, and option controls from workflow JSON
- enforce the default-view complexity budget
- add collapsible vertical stage ladder
- add source badges for stage, variant, preset, and custom values
- move app selection into stage `700+`
- model Backstage as stage `900` platform surface
- add APIM simulator as API mediation/platform capability
- add inline risk messages for stage `100` substrate changes
- add readiness button that streams focused Makefile output
- add HTMX partials for preview, stage panels, readiness output, and job status

Done criteria:

- no hardcoded `sentiment` or `subnetcalc` controls in browser UI code
- basic `readiness -> plan -> apply` path works without expanding panels
- future stages can be inspected but not accidentally applied
- command preview remains the safety handoff before mutation

### Phase 4: Terminal TUI Parity

Deliverables:

- consume the same workflow JSON as the browser UI
- present progressive pages rather than one prompt per option
- keep output streaming and next-stage shortcuts
- add preset group selection and advanced option editing
- show the same effective config summary as the browser UI

Done criteria:

- TUI and browser UI offer the same variants, stages, preset groups, actions,
  app catalog entries, and platform surfaces
- direct Makefile users are unaffected

### Phase 5: Preset Library

Deliverables:

- `default`
- `minimal`
- `local-idp-12gb`
- `airplane`
- `no-reference-apps`
- `reference-apps`
- `local-cache`
- `pull`
- `observability-victoria`
- `observability-lgtm`
- `observability-minimal`
- `identity-keycloak`
- `identity-dex` if still supported by the Terraform path

Done criteria:

- presets are overlays, not new stages
- exactly one preset per group is active
- presets declare which stages and variants they apply to
- invalid preset/stage/variant combinations explain themselves in the UI
- the `airplane` preset fails early when required cached images are absent

### Phase 6: Mid-Apply Progress And Deployment Read Model

Deliverables:

- add read-only inventory JSON command
- add progress-grid JSON or HTML fragment for running jobs
- show deployed capabilities and apps in a grid
- show Kubernetes health summary
- show Argo CD sync/health where available
- show Gateway/HTTPRoute/certificate status where available
- show raw logs/events behind disclosure controls
- add copyable diagnostic bundle
- add docs links from option metadata and failure categories

Done criteria:

- the UI can explain what was requested, what Terraform knows, and what
  Kubernetes currently reports
- while an apply is running, the UI can show observed live progress separately
  from raw command output
- failed runs produce enough context to paste into an LLM or issue without
  manually collecting state

### Phase 7: Kubernetes Solution Wrapper

Deliverables:

- introduce `kubernetes/Makefile` as a solution-level wrapper if tests show the
  schema contract is stable
- support `VARIANT=<name>` and `STAGE=<number>` without moving existing folders
- keep old variant folders as compatibility entrypoints
- update docs to teach the solution-level command shape

Done criteria:

- `make -C kubernetes VARIANT=kind STAGE=900 apply` works
- `make -C kubernetes/kind 900 apply` still works
- status/readiness output uses `variant` language consistently

### Phase 8: Folder Consolidation Decision

Deliverables:

- decide between keeping Option A or moving toward Option B based on actual
  operator experience
- if moving to Option B, migrate files behind compatibility wrappers
- defer Option C until a future hosted, bare-metal, or existing-cluster variant
  needs a stronger bootstrap/stack split

Done criteria:

- the folder shape is a product decision backed by usage and tests, not a
  prerequisite for the guided UI

## Sub-Agent Implementation Option

After Phase 0 and the schema shape are specified in enough detail, this work can
be split across sub-agents with non-overlapping write ownership.

Suggested split:

| Agent | Ownership | Output |
| --- | --- | --- |
| Config audit agent | `docs/plans/**`, generated audit table only | Effective config inventory and schema inputs. |
| Workflow schema agent | `kubernetes/workflow/**`, `scripts/platform-workflow.sh`, workflow BATS tests | Schema, JSON output, compatibility aliases. |
| Web UI agent | `tools/platform-workflow-ui/**` | Schema-driven browser UI, HTMX partials, and stage ladder. |
| TUI agent | `tools/platform-tui/**` | Schema-driven terminal pages and parity tests. |
| Preset/tfvars agent | `kubernetes/**/stages`, `kubernetes/**/profiles`, override rendering tests | Preset overlays and tfvars precedence fixes. |
| Status agent | `scripts/platform-status.sh`, new inventory/progress script, status tests | Deployment read model and diagnostic bundle inputs. |
| Docs agent | `docs/**`, `AGENTS.md` only after behavior lands | Operator docs and migration notes. |

Use sub-agents only after the audit and schema shape are locked. Before that
point, the work is too coupled and agents are likely to invent incompatible
models.

## Risks And Mitigations

| Risk | Mitigation |
| --- | --- |
| UI becomes a Terraform variable editor | Expose curated options first, hide advanced toggles, keep command preview central. |
| Stage/preset/override precedence is confusing | Always show effective value source and generated tfvars. |
| `950-local-idp` compatibility lingers forever | Mark it as alias in schema, hide it from default UI after the compatibility window, then remove later. |
| Variant folders and new schema diverge | Add tests that compare workflow JSON, Makefile stage lists, and stage files. |
| Kind operator overrides clobber UI choices | Fix tfvars precedence before broadening exposed options. |
| Hosted or bare-metal variants force a redesign | Model variants and readiness contracts now; defer Terraform module split until needed. |
| HTMX partials become tangled | Keep server-side state canonical and restrict local JavaScript to UI affordances. |
| Mid-apply progress is mistaken for apply success | Label progress as observed live state and keep command exit code authoritative. |

## Remaining Open Questions

1. Should `observability-lgtm` replace the current VictoriaLogs path, or sit
   beside it as an alternate preset?
2. Is `identity-dex` still a supported preset, or should Keycloak be the only
   local stage `900` identity stack?
3. What is the exact compatibility window for accepting `950-local-idp` after
   the schema ships?
4. Which local image cache modes should be allowed to fall back to internet
   pulls, and which should fail closed?
5. What is the smallest custom local app spec that can enter the service
   catalog without bypassing IDP environment machinery?

## Near-Term Recommendation

Implement Option A first:

1. Run the effective config audit.
2. Add shared workflow metadata under `kubernetes/workflow`.
3. Teach the workflow core to emit variant-oriented JSON with legacy target
   compatibility.
4. Model `950-local-idp` as `stage=900` plus the `local-idp-12gb` resource
   profile.
5. Fix generated tfvars precedence.
6. Build the browser stage ladder from the schema with HTMX partials and small
   local JavaScript only for local affordances.
7. Port the same schema to the TUI.
8. Add the inventory/progress read model.
9. Only then decide whether to collapse operator entrypoints into a single
   `kubernetes` folder.

This gives the UI a clean domain model without forcing a risky Terraform or
folder-layout migration before the operator experience is understood.
