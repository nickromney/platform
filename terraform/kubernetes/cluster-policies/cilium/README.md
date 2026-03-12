# Cilium Policy Layout

This directory is organized by policy scope and composed through Kustomize.

- `shared/`: policies that apply clusterwide or to both `dev` and `uat`.
- `dev/`: policies that only target the `dev` namespace.
- `uat/`: policies that only target the `uat` namespace.

Top-level `kustomization.yaml` composes `shared`, `dev`, and `uat` only.

See:

- [../AUDIT.md](../AUDIT.md) for the current policy-by-policy audit and posture summary.
- [../COMPOSITION.md](../COMPOSITION.md) for the rendered composition of `shared/`, `dev/`, and `uat/`.
- [../../docs/apps-c4.md](../../docs/apps-c4.md) for the Mermaid native C4 application and policy control model.

## Design notes

- `dev`, `uat`, and `sit` are currently the namespaces labeled `platform.publiccloudexperiments.net/namespace-role=application`; serving-path and runtime shared-service namespaces such as `apim`, `sso`, `observability`, `platform-gateway`, and `gateway-routes` are labeled `platform.publiccloudexperiments.net/namespace-role=shared`; operator, control, and delivery namespaces such as `argocd`, `cert-manager`, `kyverno`, `nginx-gateway`, `gitea`, `gitea-runner`, `headlamp`, and `policy-reporter` are labeled `platform.publiccloudexperiments.net/namespace-role=platform`.
- That namespace-role split is the intended extension point. `sit` is currently empty and proves the namespace-level Kyverno inheritance path; additional end-user namespaces such as `pat` can follow the same label model. The Cilium application-flow policies are still rendered explicitly for `dev` and `uat`, so future application namespaces do not yet inherit the full traffic posture automatically.
- The same namespaces can also carry `platform.publiccloudexperiments.net/environment`, which is a better long-term selector for env-specific Cilium generation than encoding environment into the namespace name.
- Where namespace-level data handling matters, the repo now uses `platform.publiccloudexperiments.net/sensitivity=private|confidential|restricted` following the [SISA Infosec data classification model](https://www.sisainfosec.com/blogs/data-classification-levels/).
- `shared/` holds dedicated baselines for both shared and platform namespaces such as `argocd`, `sso`, `observability`, `gitea`, `platform-gateway`, and `headlamp`.
- `argocd-hardened.yaml` now keeps namespace-wide Argo CD egress tight and limits repo-server public Helm access to `dl.gitea.io:443` only.
- Non-Gitea chart-based apps are now rendered from vendored charts in the Gitea-backed `platform/policies` repo, so the old multi-host Helm allowlist is no longer needed.
- `dev/` and `uat/` layer namespace baselines, project-isolation deny rules, and application flow policies for the `sentiment` and `subnetcalc` stacks.
- The Cloudflare live-fetch exception for `subnetcalc-api` now lives only in `dev/`, is exact-host scoped to `www.cloudflare.com:443`, and uses a DNS L7 rule so Cilium can enforce the FQDN pin. `uat` has no such exception and therefore relies on the app fallback.
- The `*-mtls-*` files now contain workload-scoped policies rather than project-scoped unions, so router, API, frontend, and LLM access are separated explicitly.
- Router-specific L7 policies still carry the request-path restrictions on top of those narrower L4 boundaries.
- Any policy in this tree that uses `toFQDNs` now also carries a DNS proxy rule in the same file, so hostname-based egress does not silently depend on unrelated policy layering.
- Cilium itself still runs in `kube-system`, which remains intentionally outside this namespace taxonomy for now.
