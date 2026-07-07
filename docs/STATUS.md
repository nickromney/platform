# Platform Status

This is the living status page for the platform repository. Historical planning
notes live under [`docs/plans/archive`](plans/archive/).

## Current Architecture

- The main operator path is the staged local Kubernetes solution under
  [`kubernetes/kind`](../kubernetes/kind/). The root `Makefile` routes users to
  focused Makefiles rather than operating the whole repo directly.
- `kind` is the reference variant. [`kubernetes/lima`](../kubernetes/lima/)
  adapts the same shared stack onto a local VM substrate on a best-effort,
  validated-on-demand basis. Slicer support was removed (niche, chargeable
  product; kind covers the reference path).
- Stages are cumulative: `100` bootstrap, `200` Cilium, `300` Hubble, `400`
  Argo CD, `500` Gitea, `600` policy controls, `700` app repos, `800`
  gateway/observability, `900` SSO, and `920` Langfuse where enabled.
- Shared variant facts are expressed through
  [`kubernetes/variants`](../kubernetes/variants/) and workflow metadata in
  [`kubernetes/workflow/options.json`](../kubernetes/workflow/options.json).
- The Kubernetes stack internals are rendered from
  [`terraform/kubernetes`](../terraform/kubernetes/), with GitOps policy/app
  output synchronized to the in-cluster Gitea repository for Argo CD.
- Platform and app inventory is projected from
  [`catalog/platform-apps.json`](../catalog/platform-apps.json), Backstage
  catalog files, Argo CD Applications, route manifests, and Launchpad tiles.
- The app family lives under [`apps`](../apps/). Shared Go packages such as
  `apps/shared/idpauth` and `apps/shared/apphttp` carry common auth and HTTP
  behavior for lightweight apps.
- The developer portal/API surface lives in `apps/idp-core`, `apps/idp-sdk`,
  `apps/platform-mcp`, and `apps/backstage`, with runtime adapters for
  `generic_kubernetes`, `kind`, and `lima`.
- DDD vocabulary and contract boundaries remain in [`docs/ddd`](ddd/); ADRs
  remain in [`docs/adr`](adr/).

## Done

- ADR-era local stack model: cumulative stages and a reference `kind` variant
  are the accepted operator shape.
- Identity provider completion: stage `900` defaults to Keycloak plus
  `oauth2-proxy`; Dex remains a provider-switch compatibility path.
- Stage `900` SSO wiring: Argo CD, Headlamp, Kubernetes API trust, platform
  routes, and app routes consume provider-neutral OIDC locals.
- IDP/portal API runtime adapters: `generic_kubernetes`, `kind`, and
  `lima` are exposed through a deterministic registry.
- Application/catalog projection: app/environment surfaces feed Argo CD apps,
  route hostnames, SSO callbacks, Launchpad tiles, deployment records, secret
  bindings, and scorecards.
- Image catalog deepening: platform/workload image refs and target projections
  are centralized in workflow catalog data and render helpers.
- GitOps render contract: policy repo rendering has golden tests and is split
  from the Gitea push adapter.
- Review environment substrate contract: namespace, registry secret, wildcard
  certificate, runner labels, and branch workflow dispatch are source
  controlled and tested.
- App repo sync and image readiness: sentiment/subnetcalc sync and wait logic
  use shared contracts instead of duplicated local-exec snippets.
- APIM simulator ownership: `apps/apim-simulator` is the repo source; older
  subnetcalc vendoring language is historical only.
- Apps Go architecture pass: `idpauth.BootstrapVerifier`,
  `idpauth.Authenticator.Middleware`, ADR 0009, TUI stage labels, idp-mcp tool
  registry consolidation, and the idp-core runtime adapter registry landed.
- IaC boundary work: Lima stage `100` bootstrap stays outside
  Terraform/Terragrunt, and browser E2E checks are validation concerns rather
  than apply convergence logic.
- JavaScript dependency direction: sample app frontends avoid npm dependency
  sprawl; Backstage is the explicit portal exception.

## Decided

- Custom kind node image: evaluated and declined (2026-07-07). With a warm
  image cache, images and local builds are ~1m26s of a ~10m stage-900 build;
  convergence (Keycloak, Gitea, TLS, Argo, OIDC) dominates and cannot be
  baked. The `hybrid`/`baked` consumer modes remain but no builder will be
  added. Newcomer wait is addressed via preload/registry cache plus a planned
  phase-progress indicator.
- Slicer substrate removed; Lima demoted to best-effort (2026-07-07).

## Open Decisions And Backlog

- Secrets lifecycle / ESO: decide whether to keep apply-driven generated
  Kubernetes Secrets or introduce External Secrets Operator and explicit
  rotation workflows.
- Progressive delivery / Argo Rollouts: decide whether rollout controllers
  belong in the local teaching stack or remain outside the default path.
- CNPG optional stage: decide whether Postgres operators should be an opt-in
  stage/profile for workloads such as Keycloak, Backstage, and Langfuse.
- Scorecard depth: probes and requests/limits checks landed as catalog
  fields (2026-07-07). Remaining candidates, each needing a new data join:
  Backstage-entry presence, observability scrape-config evidence, signed-image
  policy coverage, and per-app runbook links.
- HPA example: add a minimal autoscaling example only if it improves the
  teaching path without increasing stage-900 fragility.
- Lima demotion: decide whether Lima stays a first-class local variant or
  becomes an adapter/fallback path behind `kind`.
- Alertmanager runbook portal surfacing: expose actionable alert/runbook links
  in the portal/status surfaces instead of leaving them only in raw docs.
- Dex lifecycle: keep Dex indefinitely as the compact SSO provider, or retire
  it after Keycloak has enough evidence across local variants.
- App catalog source: keep deriving catalog data from several sources, or make
  one first-class application catalog file authoritative.
- Guided workflow presets: finish the effective-config audit, schema-backed
  presets, override rendering, and deployment read model if operator demand
  justifies the UI complexity.
- App-of-apps migration: decide whether direct Argo CD child ownership remains
  supported or app-of-apps becomes the only fresh-cluster path.
- Portal/API status projection: deepen `/api/v1/status`, deployments, secrets,
  and scorecards without making in-cluster code depend on host scripts.
- `950-local-idp` profile: either promote it as a documented profile alias or
  retire it after the stage/profile model settles.
- APIM simulator rewrite: the Go rewrite remains optional backlog; the current
  Go app path already owns the repo-local simulator source.
- Vanilla JS type checking: continue Deno/Biome `// @ts-check` coverage where
  browser app complexity warrants it.
- Langfuse stage polish: keep stage `920` metadata, route, SSO, policy,
  ingestion, and demo prerequisites aligned across all workflow surfaces.
- Low/speculative app cleanup: revisit `apps/platform-mcp` tool registry only
  after a fourth tool, and add a sentiment store seam only after a second store
  adapter exists.

## Planning Inventory

| Document | Purpose | Class | Disposition |
| --- | --- | --- | --- |
| `plans/archive/apim-simulator-go-rewrite-notes.md` | Optional Go rewrite notes for APIM simulator. | Open/backlog | Current source lives in `apps/apim-simulator`; rewrite is not active. |
| `plans/archive/architecture-deepening-candidates.md` | Architecture review candidates and follow-up ledger. | Mixed | Many items done; remaining speculative items carried forward above. |
| `plans/archive/architecture-review-20260524.md` | Completed apps/ architecture review loops. | Done/landed | Retained as historical review record. |
| `plans/archive/guided-workflow-variant-presets-addendum.md` | Review gaps for guided workflow presets. | Open/backlog | Distilled into guided workflow item. |
| `plans/archive/guided-workflow-variant-presets-plan.md` | Detailed preset/schema/UI roadmap. | Open/backlog | Detailed plan archived. |
| `plans/archive/identity-provider-roadmap.md` | Identity provider completion notes. | Current + open | Current state and open decisions distilled above. |
| `plans/archive/kind-argocd-app-of-apps-migration-plan.md` | Argo CD app-of-apps migration proposal. | Open decision | Carried forward as backlog. |
| `plans/archive/local-idp-gap-analysis.md` | Local IDP parity gap summary. | Mostly done | Portal/status quality carried forward. |
| `plans/archive/local-idp-implementation-roadmap.md` | Early local IDP roadmap. | Done/superseded | Superseded by later implementation notes and current code. |
| `plans/archive/local-idp-mcp-and-tui-plan.md` | Early API/TUI/MCP shape. | Done/superseded | Superseded by current idp-core, SDK, MCP, and TUI code. |
| `plans/archive/local-idp-next-implementation-steps.md` | Chunked local IDP implementation handoff. | Mixed | Many chunks landed; status/profile/proof items carried forward. |
| `plans/archive/local-idp-runtime-portability.md` | Runtime adapter portability note. | Current | Adapters exist for generic Kubernetes, kind, Lima, Slicer. |
| `plans/archive/vanilla-js-type-checking-plan.md` | Browser JS type-checking direction. | Open/backlog | Standing convention for browser app complexity. |
| `plans/archive/variant-capable-kubernetes-workflow-architecture.md` | Variant-capable workflow architecture stress test. | Mostly done | Landed as workflow/variant contract direction. |
| `2026-04-19-kubernetes-iac-boundary-plan.md` | IaC boundary/idempotence execution plan. | Mostly done | Canonical current record is `docs/iac-boundaries.md`. |
| `apps-consistency-handoff.md` | App consistency handoff and next slices. | Mixed | App backlog; not part of archived `plans/` move. |
| `apps-no-npm.md` | Decision record for sample apps without npm sprawl. | Current | Current convention with Backstage exception. |
| `iac-boundaries.md` | Current IaC ownership and runtime evidence. | Current | Still-accurate current state. |
| `langfuse-observations.md` | Stage `920` Langfuse implementation observations. | Current + open | Operational notes plus polish backlog. |

## Link Maintenance

- `docs/plans/` now contains only a pointer README and the historical archive.
- Superseded planning docs were moved unchanged into `docs/plans/archive/`.
- Non-archive inbound references should point to this file for current state or
  to `docs/plans/archive/` for historical review records.
