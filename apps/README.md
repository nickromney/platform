# Apps

This directory contains the source applications that feed the local platform demos.

## Layout

- [`subnet-calculator/`](subnet-calculator/) contains the subnet calculator app and its local compose-based workflows.
  Local compose architecture: [`subnet-calculator/docs/COMPOSE-ARCHITECTURE.md`](subnet-calculator/docs/COMPOSE-ARCHITECTURE.md)
  Test runbook: [`subnet-calculator/docs/TEST-RUNBOOK.md`](subnet-calculator/docs/TEST-RUNBOOK.md)
- [`sentiment/`](sentiment/) contains the sentiment demo and its local compose-based workflows.
  Local compose architecture: [`sentiment/docs/COMPOSE-ARCHITECTURE.md`](sentiment/docs/COMPOSE-ARCHITECTURE.md)
  Test runbook: [`sentiment/docs/TEST-RUNBOOK.md`](sentiment/docs/TEST-RUNBOOK.md)

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

The canonical JavaScript package manager in this repo is `bun`.

- Use `bun install` and `bun run ...` in app directories.
- JavaScript package roots ship local `bunfig.toml` and `.npmrc` cooldown defaults, and Python app roots set `[tool.uv].exclude-newer = "7 days"`, so copied app directories and compose/Docker builds keep the same dependency age gate.
- Use `bun x ...` for one-shot CLI tools such as Playwright or Bruno.
- Default frontend Playwright suites are kept runnable in isolation; SWA-specific and other environment-coupled suites remain explicit opt-in commands rather than being folded into the default `test` target.
- Use `make -C apps compose-smoke` for the light compose wiring checks.
