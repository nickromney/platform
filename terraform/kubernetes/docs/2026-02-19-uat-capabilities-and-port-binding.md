# UAT Capability Enforcement and Privileged Port Binding

Date: 2026-02-19

## Summary

`make ... apply` failed in `uat` because Kyverno enforced container hardening (`drop: [ALL]`, `privileged: false`) while multiple web containers still listened on port `80` inside the pod.

With all Linux capabilities dropped, binding to privileged ports (`<1024`) is denied unless `NET_BIND_SERVICE` is explicitly re-added.

## What Happened

Kyverno policy `uat-restrict-capabilities` (`cluster-policies/kyverno/uat/uat-restrict-capabilities.yaml`) denied Deployments in `uat`:

- `sentiment-api`
- `sentiment-auth-ui`
- `sentiment-router`
- `subnetcalc-api`
- `subnetcalc-frontend`
- `subnetcalc-router`

Key denial reasons:

- containers in `uat` must drop `ALL` capabilities
- privileged containers are not allowed

To unblock apply, a temporary patch (`apps/uat/security-context-patches.yaml`) added:

- `privileged: false`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]`
- `capabilities.add: [NET_BIND_SERVICE]` on web tier components still binding `:80`

## Why `NET_BIND_SERVICE` Appeared

The capability was not for network exposure policy. It was a Linux process privilege so nginx-based containers could still bind `:80` after `drop: [ALL]`.

That is a practical compatibility shim, but not the strictest posture.

## Security Goal

For a stricter locked-down model:

1. Containers listen only on non-privileged ports (for example `8080`).
2. Services can still present port `80` externally via `port: 80` and `targetPort: 8080`.
3. Keep `drop: [ALL]` with no `capabilities.add`.
4. Keep Cilium policies aligned with actual pod destination ports.

## Scope of Required Rewrite

The migration to non-privileged listen ports requires coordinated changes in:

- base workload manifests (`apps/workloads/base/all.yaml`)
- frontend image nginx configs (app repos)
- `dev` and `uat` Cilium policies currently allowing/expecting `:80` between app tiers
- UAT security patch to remove `NET_BIND_SERVICE` once pods bind non-privileged ports

## Implemented in This Change

The following was implemented immediately after this write-up:

- Sentiment and SubnetCalc web containers now listen on `8080` (not `80`) in workload manifests and image nginx configs.
- Kubernetes Services for these components remain on `port: 80` with `targetPort: 8080`.
- `dev` and `uat` Cilium policies for router/frontend and sso/router paths were updated to `8080`.
- `apps/uat/security-context-patches.yaml` no longer adds `NET_BIND_SERVICE`; it keeps `drop: [ALL]` and `privileged: false`.

Follow-up hardening after this rollout:

- Azure Function-based containers in local compose stacks were moved from internal `:80` to `:8080`.
- APIM simulator upstream defaults/config now target Function backends on `:8080`.
- C# Azure Function test stack also binds to `:8080` internally.

## Related Observations During Triage

There was a separate Gitea Actions issue earlier where `subnet-calculator` builds timed out pulling `python:3.13-slim` from Docker Hub. That issue is independent from this Kyverno/capability-port binding mismatch but surfaced in the same apply runs.
