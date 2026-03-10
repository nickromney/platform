Policies synchronized via Argo CD from the local Gitea repository (created by Terraform). This directory is staged under `cluster-policies/` in the `policies` repo and represents the cluster-wide controls.

- `cilium/` enforces ingress/egress controls via Kustomize composition by scope:
  - `cilium/shared/` for cross-environment and clusterwide policies.
  - `cilium/dev/` for dev-specific policies.
  - `cilium/uat/` for uat-specific policies.
- `kyverno/` provides default-deny scaffolding; customize via labels to allow intended paths.

App-specific manifests and policies reside under `apps/<app>/` in the same repo. Publish changes here to the in-cluster `policies` repo via `terraform/kubernetes/scripts/sync-gitea.sh`.
