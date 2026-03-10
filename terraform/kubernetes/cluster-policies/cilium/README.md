# Cilium Policy Layout

This directory is organized by policy scope and composed through Kustomize.

- `shared/`: policies that apply clusterwide or to both `dev` and `uat`.
- `dev/`: policies that only target the `dev` namespace.
- `uat/`: policies that only target the `uat` namespace.
- `examples/`: non-applied reference manifests.

Top-level `kustomization.yaml` composes `shared`, `dev`, and `uat` only.
