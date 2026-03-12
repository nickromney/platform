Policies synchronized via Argo CD from the local Gitea repository (created by Terraform). This directory is staged under `cluster-policies/` in the `policies` repo and represents the cluster-wide controls.

Detailed reasoning aids live here:

- [AUDIT.md](./AUDIT.md) for the policy-by-policy audit and current posture.
- [COMPOSITION.md](./COMPOSITION.md) for the rendered shared/dev/uat and shared/uat composition view.
- [apps-c4.md](../docs/apps-c4.md) for the Mermaid native C4 application and policy control model.

Regenerate the composition view with:

```bash
terraform/kubernetes/scripts/show-policy-composition.sh --target all --format markdown > terraform/kubernetes/cluster-policies/COMPOSITION.md
```

## Layout

- `cilium/` contains clusterwide network policy overlays:
  - `shared/` for shared platform controls and shared app egress restrictions.
  - `dev/` for dev-specific namespace baselines, project isolation, and app flow policies.
  - `uat/` for uat-specific namespace baselines, project isolation, and app flow policies.
- `kyverno/` contains admission policies:
  - `shared/` for generated default-deny scaffolding, application-namespace label checks, and image-source checks.
  - `uat/` for uat-only pod hardening checks.

Namespace intent is now explicit:

- Namespaces labeled `platform.publiccloudexperiments.net/namespace-role=application` are the end-user workload namespaces that inherit the shared Kyverno label policy.
- Namespaces labeled `platform.publiccloudexperiments.net/namespace-role=shared` are the serving-path and runtime shared-service namespaces such as `apim`, `sso`, `observability`, `platform-gateway`, and `gateway-routes`.
- Namespaces labeled `platform.publiccloudexperiments.net/namespace-role=platform` are the operator, control, and delivery namespaces such as `argocd`, `cert-manager`, `kyverno`, `nginx-gateway`, `gitea`, `gitea-runner`, `headlamp`, and `policy-reporter`.
- Today `dev` and `uat` are the only application namespaces, but the policy model is no longer coupled to those names. A future `sit` or `pat` namespace will inherit the same Kyverno contract as soon as it is labeled `platform.publiccloudexperiments.net/namespace-role=application`.
- `dev` and `uat` also carry `platform.publiccloudexperiments.net/environment=dev|uat` so later Cilium or policy generators can distinguish environment from namespace purpose.
- Where a namespace needs a data-handling tag, it now uses `platform.publiccloudexperiments.net/sensitivity=private|confidential|restricted` following the [SISA Infosec data classification model](https://www.sisainfosec.com/blogs/data-classification-levels/).

## Current audit summary

- The overall model is good: default-deny scaffolding, explicit Cilium allowlists, and selective L7 rules.
- The app-flow Cilium policies are now workload-scoped instead of project-scoped, which fixes the main over-permissioning issue from the initial audit pass.
- Namespace-level intent is now explicit: `dev` and `uat` are labeled `platform.publiccloudexperiments.net/namespace-role=application`, serving-path and runtime shared-service namespaces are labeled `platform.publiccloudexperiments.net/namespace-role=shared`, and operator/control/delivery namespaces are labeled `platform.publiccloudexperiments.net/namespace-role=platform`, so admission policy can target application namespaces generically without overloading pod-level `role` labels.
- Non-Gitea Helm charts are now vendored into the in-cluster `platform/policies` Git repository, which lets Argo CD render those charts from Gitea Git and keeps the repo-server external exception down to `dl.gitea.io:443`.
- The dev-only Cloudflare live-fetch path is now exact-host scoped to `www.cloudflare.com:443`, while `uat` intentionally falls back to the API's bundled ranges.
- Cilium FQDN policies now include DNS proxy rules so those hostname pins are actually enforceable.
- `terraform/kubernetes/scripts/check-version.sh` now understands this Git-backed chart flow and reads deployed chart versions for Argo-managed apps from live `helm.sh/chart` labels.
- The platform gateway TLS hardening path is now proven both declaratively and at runtime: [`../apps/platform-gateway/tls-hardening.yaml`](../apps/platform-gateway/tls-hardening.yaml) declares the NGINX directives, [`../apps/nginx-gateway-fabric/deploy.yaml`](../apps/nginx-gateway-fabric/deploy.yaml) enables `SnippetsPolicy` support in the controller, and [`../scripts/check-security.sh`](../scripts/check-security.sh) verifies the live rendered config and on-the-wire TLS behavior.
- The biggest remaining gaps are the audit-only Kyverno rules, the remaining shared outbound internet exceptions, the Gitea bootstrap dependency on `dl.gitea.io`, and the observability allowance for host TCP `10255`.

App-specific manifests and policies reside under `apps/<app>/` in the same repo. Publish changes here to the in-cluster `policies` repo via `terraform/kubernetes/scripts/sync-gitea.sh`.
