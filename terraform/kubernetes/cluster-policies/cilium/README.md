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

- `dev` and `uat` are currently the namespaces labeled `role=application`; shared service namespaces such as `apim`, `sso`, `observability`, `gitea`, and `headlamp` are labeled `role=shared`.
- That namespace-role split is the intended extension point. Additional end-user namespaces such as `sit` or `pat` should be labeled `role=application` so the shared Kyverno admission policy applies without introducing new hardcoded namespace names.
- `shared/` holds dedicated baselines for platform namespaces such as `argocd`, `sso`, `observability`, `gitea`, `platform-gateway`, and `headlamp`.
- `argocd-hardened.yaml` now keeps namespace-wide Argo CD egress tight and limits repo-server public Helm access to `dl.gitea.io:443` only.
- Non-Gitea chart-based apps are now rendered from vendored charts in the Gitea-backed `platform/policies` repo, so the old multi-host Helm allowlist is no longer needed.
- `dev/` and `uat/` layer namespace baselines, project-isolation deny rules, and application flow policies for the `sentiment` and `subnetcalc` stacks.
- The Cloudflare live-fetch exception for `subnetcalc-api` now lives only in `dev/`, is exact-host scoped to `www.cloudflare.com:443`, and uses a DNS L7 rule so Cilium can enforce the FQDN pin. `uat` has no such exception and therefore relies on the app fallback.
- The `*-mtls-*` files now contain workload-scoped policies rather than project-scoped unions, so router, API, frontend, and LLM access are separated explicitly.
- Router-specific L7 policies still carry the request-path restrictions on top of those narrower L4 boundaries.
- Any policy in this tree that uses `toFQDNs` now also carries a DNS proxy rule in the same file, so hostname-based egress does not silently depend on unrelated policy layering.
