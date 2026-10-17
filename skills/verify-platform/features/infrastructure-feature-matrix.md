# Infrastructure feature matrix

The supported kind stages and optional features must render routes and grants that only refer to enabled optional namespaces. This is an offline infrastructure recipe, separate from Compose browser acceptance.

## Sub-features

- Real stage 800 and 900 boolean settings with Headlamp enabled and disabled.
- Each stage with the current observability group enabled and disabled: Grafana, Prometheus, VictoriaLogs and the OTel gateway.
- Both plain and SSO gateway route trees, plus the Headlamp Argo Application and observability Namespace manifests.
- No residual Headlamp route/grant when disabled; no observability namespace reference when that group is disabled.

## How to get to it (user POV)

An operator chooses a current kind stage and optional feature overrides. Disabled features must not leave the gateway Argo app degraded by trying to create grants in an absent namespace.

## Driving it with control.sh

This recipe uses its own executable helper, not the Compose controller:

```bash
skills/verify-platform/scripts/render-feature-matrix.sh --execute .run/verify-infrastructure/matrix-$(date +%Y%m%d-%H%M%S)
```

Requires local `kubectl`, `jq`, `perl` and `uv`, with the locked repo Python/PyYAML environment prepared. Do not install or download dependencies as part of rendering. The helper copies actual application source, reads the current stage booleans and invokes production `render_gateway_routes_for_cilium`, `prune_argocd_app_manifests` and `prune_gateway_routes_manifests` from `sync-gitea-policies.sh`. It runs local `kubectl kustomize`, then independently parses the resulting YAML. It never calls the full renderer, chart vendoring, Git push, cluster APIs, or Make apply.

Evidence retains eight input records, render logs, copied/pruned application trees, sixteen Kustomize outputs and `matrix-result.json`. A failed assertion exits nonzero and keeps its inputs. A successful matrix must contain sixteen entries; zero cases cannot pass.

To check the assertion itself, append a `ReferenceGrant` with metadata namespace `headlamp` to a disabled case's rendered YAML and run `PYTHONOPTIMIZE=0 uv run --locked --project . python skills/verify-platform/scripts/check-feature-matrix.py MATRIX_DIRECTORY` from the repository root; it must fail. Restore the original output before reporting the positive matrix. Retain the negative result separately.

## Gotchas

The historical SigNoz/stage-850 incident predates the current stage model. Current kind stages are 800 and 900, and current source exposes no SigNoz toggle. The parser rejects SigNoz references in rendered gateway resources; it cannot honestly claim a supported SigNoz-enabled case. Use the current observability group in this matrix.

This drives the real production route/application pruning boundary, not Helm chart rendering or Terraform namespace creation. It does not prove live Argo sync, cluster reset, stage deployment, or browser health. Follow the separate staged-kind recipe for those. The eight retained source copies used about 15 MiB in the 2026-10-16 proof; no containers were started.
