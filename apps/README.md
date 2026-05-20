# Apps

This directory contains the source applications that feed the local platform demos.

## Layout

- [`subnetcalc/`](subnetcalc/) contains the subnet calculator app, implemented
  as a small Go service with embedded HTML/CSS/JavaScript and a two-service
  local compose workflow.
- [`sentiment/`](sentiment/) contains the sentiment demo and its local compose-based workflows.
  Local compose architecture: [`sentiment/docs/COMPOSE-ARCHITECTURE.md`](sentiment/docs/COMPOSE-ARCHITECTURE.md)
  Test runbook: [`sentiment/docs/TEST-RUNBOOK.md`](sentiment/docs/TEST-RUNBOOK.md)
- [`apim-simulator/`](apim-simulator/) contains the local Azure API Management simulator used by the Kubernetes APIM gateway demo and by app-local compose workflows.
  It keeps its own standalone Docker Compose entrypoints, for example `make -C apps/apim-simulator up` and `make -C apps/apim-simulator smoke-hello`.
- [`idp-core/`](idp-core/) contains the Portal API as a Go single-binary app
  under `idp-core/app`.
- [`idp-mcp/`](idp-mcp/) contains a small dependency-free stdlib MCP adapter for
  the Portal API.
- [`idp-sdk/`](idp-sdk/) contains a dependency-free browser `fetch` wrapper for
  Portal clients.
- [`platform-mcp/`](platform-mcp/) contains the production MCP service. It keeps
  the MCP SDK as an intentional protocol dependency.
- [`backstage/`](backstage/) contains Portal. It is an intentional Backstage
  exception to the lightweight app rule and remains resource-gated in the local
  Kubernetes profiles.

## Relationship To The Kubernetes Demos

The kind stack uses Kubernetes manifests under [`terraform/kubernetes/apps/`](../terraform/kubernetes/apps/), but those manifests are there to deploy the demos into the cluster.

This repo-root `apps/` directory is the better place to start if you want to understand the application source trees themselves.

For the higher-level Kubernetes-side walkthrough, including Mermaid diagrams of the sample app flows, see [sample-apps.md](../kubernetes/kind/docs/sample-apps.md).

## Security Scanning

If you already have a local `trivy` binary and want to use it, run the
rerunnable app scan workflow from this directory:

```bash
make -C apps trivy-scan
```

That scans the local `apps/` source trees plus the canonical workload images
built by the Kubernetes demos, and writes JSON reports under
`.run/apps-security/trivy/`.

`trivy` is optional in this repo. The default app workflow does not install it,
and `make -C apps prereqs` intentionally avoids checking for it. Use the
explicit Trivy entrypoints when you want scanning:

```bash
make -C apps trivy-prereqs
make -C apps trivy-scan
make -C apps trivy-scan-all
```

The in-cluster Gitea mirrors are intentionally opt-in because they usually mirror the same content already scanned from disk:

```bash
make -C apps trivy-scan-all
```

## JavaScript Tooling

The lightweight sample apps avoid JavaScript package managers in their default
runtime paths. Portal is the exception: `apps/backstage` uses Backstage's
Yarn-based toolchain because the framework owns that dependency model. Keep it
out of lightweight app defaults and minimal profiles rather than trying to make
Backstage dependency free.

- Use package-manager installs only in explicit legacy or product surfaces such
  as Backstage, deprecated Vite examples, or one-shot API client tooling.
- JavaScript package roots ship local `bunfig.toml` or `.npmrc` cooldown
  defaults, and Python app roots set `[tool.uv].exclude-newer = "7 days"`, so
  copied app directories and compose/Docker builds keep the same dependency age
  gate.
- Use one-shot package execution only for explicit tooling such as Bruno or
  Newman collections.
- Use `make -C apps compose-smoke` for the light compose wiring checks.
