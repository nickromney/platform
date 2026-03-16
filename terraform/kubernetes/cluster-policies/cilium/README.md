# Cilium Policy Layout

This directory is organized by policy scope and composed through Kustomize.

- `shared/`: true clusterwide guardrails and shared/shared-platform namespace policies.
- `projects/`: reusable namespaced `CiliumNetworkPolicy` bundles for application stacks.
- `dev/`, `uat/`, and `sit/`: namespace overlays that apply the reusable project bundles into concrete application namespaces.
- `*/overrides/`: namespace-local exceptions owned by the namespace overlay, such as the dev-only Cloudflare live fetch.

Top-level `kustomization.yaml` composes `shared`, `dev`, `uat`, and `sit`.

See:

- [../AUDIT.md](../AUDIT.md) for the current policy-by-policy audit and posture summary.
- [../COMPOSITION.md](../COMPOSITION.md) for the rendered composition of `shared/`, `dev/`, `uat/`, and `sit`.
- [../../docs/apps-c4.md](../../docs/apps-c4.md) for the Mermaid native C4 application and policy control model.

## Design notes

- `dev`, `uat`, and `sit` are currently the namespaces labeled `platform.publiccloudexperiments.net/namespace-role=application`; serving-path and runtime shared-service namespaces such as `apim`, `sso`, `observability`, `platform-gateway`, and `gateway-routes` are labeled `platform.publiccloudexperiments.net/namespace-role=shared`; operator, control, and delivery namespaces such as `argocd`, `cert-manager`, `kyverno`, `nginx-gateway`, `gitea`, `gitea-runner`, `headlamp`, and `policy-reporter` are labeled `platform.publiccloudexperiments.net/namespace-role=platform`.
- That namespace-role split is the intended extension point. `sit` is currently empty and proves the namespace-level Kyverno inheritance path; additional end-user namespaces such as `pat` can follow the same label model and the same reusable project bundles through a thin namespace overlay, rather than copying another full set of app-flow policy files.
- The same namespaces can also carry `platform.publiccloudexperiments.net/environment`, which is a better long-term selector for env-specific Cilium generation than encoding environment into the namespace name.
- Where namespace-level data handling matters, the repo now uses `platform.publiccloudexperiments.net/sensitivity=private|confidential|restricted` following the [SISA Infosec data classification model](https://www.sisainfosec.com/blogs/data-classification-levels/).
- `shared/` holds dedicated baselines for both shared and platform namespaces such as `argocd`, `sso`, `observability`, `gitea`, `platform-gateway`, and `headlamp`, plus the clusterwide application guardrails keyed off `platform.publiccloudexperiments.net/namespace-role=application`.
- Shared bridge workloads now also have reusable clusterwide policies keyed off `platform.publiccloudexperiments.net/namespace-role=shared` plus workload labels such as `app.kubernetes.io/component=authentication-proxy` and `app.kubernetes.io/name=dex`, so app-to-auth, gateway-to-auth, and auth-to-external-identity paths do not depend on the literal `sso` namespace name.
- `argocd-hardened.yaml` now keeps namespace-wide Argo CD egress tight and limits repo-server public Helm access to `dl.gitea.io:443` only.
- Non-Gitea chart-based apps are now rendered from vendored charts in the Gitea-backed `platform/policies` repo, so the old multi-host Helm allowlist is no longer needed.
- `projects/sentiment/` and `projects/subnetcalc/` now hold the reusable namespaced app-flow policies. They are rendered as `CiliumNetworkPolicy`, not `CiliumClusterwideNetworkPolicy`, so the same files can be inherited into `dev`, `uat`, and `sit` without duplicating the namespace name inside each selector.
- `dev/`, `uat/`, and `sit/` are now thin overlays that set the target namespace and compose those reusable project bundles.
- The dev-only Cloudflare live-fetch exception now lives in `dev/overrides/`, is exact-host scoped to `www.cloudflare.com:443`, and uses a DNS L7 rule so Cilium can enforce the FQDN pin. `uat` and `sit` have no such override and therefore rely on the app fallback path if subnetcalc is deployed there.
- Shared-service policies such as `apim-baseline.yaml`, `sso-hardened.yaml`, and `observability-hardened.yaml` now key off `namespace-role=application` where that is the real intent, so future application namespaces can inherit the same ceilings without new copies of those policies.
- Any policy in this tree that uses `toFQDNs` now also carries a DNS proxy rule in the same file, so hostname-based egress does not silently depend on unrelated policy layering.
- Cilium itself still runs in `kube-system`, which remains intentionally outside this namespace taxonomy for now.
