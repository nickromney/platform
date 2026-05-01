# ${{ values.name }}

${{ values.description }}

This repository was created by the local platform Backstage template. It contains:

- `apps/frontend`: static frontend served by a hardened DHI nginx image.
- `apps/backend`: dependency-free Node backend served by a hardened DHI Node image.
- `kubernetes/base`: starter deployments and services with platform labels.
- `kubernetes/policies`: starter Kyverno and Cilium policies.
- `observability/grafana-dashboard.json`: a golden-signals dashboard seed.
- `.gitea/workflows/review-environment.yaml`: branch preview environments and
  branch-deletion cleanup in the platform-managed `review` namespace.

Gitea workflows target the in-cluster runner labels. The review workflow uses
`self-hosted`, `in-cluster`, and `review-env`; the image build workflow uses
`self-hosted` and `in-cluster`. In Kind, branch previews require a
runner-capable image distribution mode such as `load` or `baked`.

Review environments are created on non-`main` branch pushes after the platform
has provisioned the `review` namespace, registry pull secret, wildcard review
TLS certificate, and an enabled in-cluster Gitea Actions runner.

Owner: `${{ values.owner }}`
