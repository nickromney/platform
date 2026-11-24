# ADR 0016: Remove Backstage and keep the IDP as an API

- Status: Accepted
- Recorded: 2026-11-24
- Supersedes: the Backstage exception in [ADR 0008](./0008-default-sample-apps-to-minimal-auditable-runtimes.md)

## Context

Backstage arrived as the "Portal": a developer portal UI over the local
internal developer platform, with a software catalog, TechDocs, a Kubernetes
view, and a scaffolder template that created Gitea repositories wired for
branch review environments. ADR 0008 recorded it as the one deliberate
exception to minimal, dependency-light runtimes.

The repo targets laptops and desktops with 8 to 16 GB of RAM. In practice
Backstage was not part of that shape:

- kind gated it off by default (`KIND_ENABLE_BACKSTAGE ?= off`), and the auto
  mode only enabled it with at least 10 GiB of Docker memory, so on the
  machines the repo is for it usually did not run.
- It carried the largest dependency surface in the repo: a Yarn Berry
  workspace with 81 direct dependencies. Most rows in a version audit were
  Backstage packages, and it needed its own security-advisory bumps and Node
  image pins.
- It was wired through a lot of the stack: Terraform locals, secrets and SSO
  proxies, a gateway route, Cilium policy holes on ports 7007 and 9465, a
  Grafana dashboard, Launchpad tiles, image-build fingerprint lists, a compose
  profile, and an unconditional post-apply restart that waited up to 600
  seconds.
- Almost everything it showed was already available elsewhere. IDP Core serves
  the catalog, runtime, environment, deployment, secret, and scorecard models;
  the SDK and both MCP servers read from IDP Core, not Backstage; Launchpad,
  Headlamp, Grafana, and Argo CD cover browsing and runtime views.

The one capability Backstage provided that nothing else did was the scaffolder:
render a service template and publish it to Gitea.

The 2026-08-14 handoff chose to repair the Backstage lockfile rather than
extract or drop the app. This ADR revisits that choice.

## Decision

Remove Backstage from the repository. The local IDP is an API, not a portal UI.

- Delete `apps/backstage`, its image, compose profile, gateway route, SSO proxy,
  Grafana dashboard, Launchpad tiles, Cilium flows, and the per-app Backstage
  catalog descriptors and TechDocs `mkdocs.yml` files.
- Keep IDP Core, the IDP SDK, IDP MCP, Platform MCP, the
  `catalog/platform-apps.json` catalog, and the review-environment substrate.
- Move the scaffolder's content to `templates/platform-service` and replace the
  scaffolder with `make -C kubernetes/kind scaffold-service NAME=...`. A small
  Go renderer (`tools/platform-helpers/cmd/render-service-template`) expands the
  template's placeholders and environment loops, and
  `terraform/kubernetes/scripts/scaffold-platform-service.sh` creates the Gitea
  repository and pushes the rendered tree.
- Narrow the `idp` namespace Cilium policy to what IDP Core needs: ingress on
  8080 from the SSO proxies and DNS egress.

The vendored APIM simulator keeps its upstream `catalog-info.yaml`, because the
vendoring integrity check compares against upstream.

## Consequences

- Stage 900 no longer has a `portal.` host. The IDP API stays at
  `portal-api.`.
- The version audit, preload lists, and dependency cooldowns no longer carry a
  Yarn workspace, and the dependency checker no longer parses Yarn lockfiles.
- Creating a service is a make target rather than a form. It runs from the
  host against the Gitea NodePort with the platform admin credentials, the
  same credentials the scaffolder used in-cluster.
- There is no browsable software catalog UI. If one becomes worth its cost
  again, it should be a client of IDP Core rather than a second source of
  catalog truth.
