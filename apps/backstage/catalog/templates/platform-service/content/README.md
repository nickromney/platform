# ${{ values.name }}

${{ values.description }}

This repository was created by the local platform Backstage template. It contains:

- `apps/frontend`: static frontend served by a hardened DHI nginx image.
- `apps/backend`: dependency-free Node backend served by a hardened DHI Node image.
- `kubernetes/base`: starter deployments and services with platform labels.
- `kubernetes/policies`: starter Kyverno and Cilium policies.
- `observability/grafana-dashboard.json`: a golden-signals dashboard seed.

Owner: `${{ values.owner }}`
