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

- Namespaces labeled `role=application` are the end-user workload namespaces that inherit the shared Kyverno label policy.
- Namespaces labeled `role=shared` are the supporting service namespaces such as `apim`, `sso`, `observability`, `gitea`, and `headlamp`.
- Today `dev` and `uat` are the only application namespaces, but the policy model is no longer coupled to those names. A future `sit` or `pat` namespace will inherit the same Kyverno contract as soon as it is labeled `role=application`.

## Current audit summary

- The overall model is good: default-deny scaffolding, explicit Cilium allowlists, and selective L7 rules.
- The app-flow Cilium policies are now workload-scoped instead of project-scoped, which fixes the main over-permissioning issue from the initial audit pass.
- Namespace-level intent is now explicit: `dev` and `uat` are labeled `role=application`, while shared service namespaces are labeled `role=shared`, so admission policy can target application namespaces generically.
- Non-Gitea Helm charts are now vendored into the in-cluster `platform/policies` Git repository, which lets Argo CD render those charts from Gitea Git and keeps the repo-server external exception down to `dl.gitea.io:443`.
- The dev-only Cloudflare live-fetch path is now exact-host scoped to `www.cloudflare.com:443`, while `uat` intentionally falls back to the API's bundled ranges.
- Cilium FQDN policies now include DNS proxy rules so those hostname pins are actually enforceable.
- `terraform/kubernetes/scripts/check-version.sh` now understands this Git-backed chart flow and reads deployed chart versions for Argo-managed apps from live `helm.sh/chart` labels.
- The biggest remaining gaps are the audit-only Kyverno rules, the remaining shared outbound internet exceptions, the Gitea bootstrap dependency on `dl.gitea.io`, and the observability allowance for host TCP `10255`.

App-specific manifests and policies reside under `apps/<app>/` in the same repo. Publish changes here to the in-cluster `policies` repo via `terraform/kubernetes/scripts/sync-gitea.sh`.
