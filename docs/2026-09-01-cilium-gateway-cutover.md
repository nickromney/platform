# Cilium Gateway API cutover: validated

Date: 2026-09-01. Two-node kind cluster, profile `.run/operator/cgw.tfvars`
(`cilium_gateway_api = true`, `cilium_kube_proxy_replacement = true`).

## Result

NGINX Gateway Fabric is gone. Cilium's Envoy serves every route.

```
NAME               CLASS    ADDRESS      PROGRAMMED
platform-gateway   cilium   172.18.0.2   True

make -C kubernetes/kind 900 apply   exit 0 in 6m32s
  Apply complete! Resources: 8 added, 0 changed, 5 destroyed.
  146 OK / 0 FAIL in-apply verification

check-sso-e2e        14 passed / 0 failed
memory               2.21 GiB + 3.95 GiB = 6.17 GiB of 8.72 GiB
```

A single `900 apply` now builds this from the profile in one command. Attempts 1
through 4 each found a real defect, all fixed here; attempt 5 was lost to Docker
Desktop wedging its image-pull path, which `docker builder prune` cleared.

All five admin routes pass the browser login flow on Cilium: `gitea-admin`,
`argocd-admin`, `hubble-admin`, `kyverno-admin`, `apim-admin`. The last of those
had no E2E coverage before this work -- it was the one admin hostname the suite
never exercised.

## What the cutover actually required

The GatewayClass was the easy part. Six of the seven resources in the
platform-gateway app were NGF-coupled, and the harder problems were all in the
seams around it.

| Area | What broke | Why |
| --- | --- | --- |
| CRDs | GatewayClass stuck `Accepted=Unknown` | Cilium 1.20 needs tlsroutes and referencegrants at `v1`; no Gateway API <= v1.4.1 serves them there. Now on v1.6.1 experimental. The check runs once at operator startup, so the operator must be restarted after the CRDs land. |
| Policy | Every backend 503 | Cilium's Envoy presents `reserved:ingress`, not `host`. |
| Policy | Hubble NodePort 000 | Adding an allow rule to an unselected endpoint flips it to default-deny and *removes* access. |
| Routes | Security headers silently gone | The NGF CRDs stay installed, so the ExtensionRef still resolves and Cilium ignores a filter it does not implement. Nothing reports an error. |
| Recovery | Apply failed after Kyverno | The post-OIDC recovery restarts the NGF control plane, which does not exist. |
| Checks | Failures on a healthy cluster | Three separate diagnostic seams assembled their own inputs and each missed one. |

## The seam bug, three times

The same defect appeared in three places, and it is worth naming because it will
appear again. A script that runs outside the Makefile builds its own view of
which features are enabled, and misses a source:

- `check-cluster-health-after-oidc.sh` omitted `KIND_PROFILE_TFVARS`, so it
  failed the apply on `enable_headlamp=true` when the profile said false.
- `operator-facts.sh` documents `OPERATOR_FACTS_FILE` as its first source, but
  nothing set it, so every checker fell back to whatever tfvars the caller
  passed. `make check-gateway-urls` without the profile flag asserted NGINX
  against a Cilium cluster.
- `gitea-sync` passes only the stage tfvars, so a manual sync re-rendered at
  stage defaults and published routes for backends the profile had disabled.

All three now prefer the operator facts contract, which the last apply writes.

## Capability changes

Preserved by translation into core Gateway API `ResponseHeaderModifier`:
HSTS, `X-Content-Type-Options`, `X-Frame-Options` (DENY, SAMEORIGIN for the
Keycloak admin console), `Referrer-Policy`. These now apply per route rather
than through one Gateway-scoped policy, and cover every route rather than only
the twelve that happened to carry a filter.

Genuinely lost, and not worked around:

- **TLS cipher and session-ticket control.** `tls-hardening.yaml` set
  `ssl_conf_command Ciphersuites`, `ssl_ecdh_curve`, `ssl_prefer_server_ciphers`
  and `ssl_session_tickets`. There is no core Gateway API equivalent.
- **Admin IP allowlist.** No core equivalent either. Rather than render admin
  routes without the restriction they are configured to have, a non-empty
  `ADMIN_ROUTE_ALLOWLIST_CIDRS` is a hard failure in this mode. The local
  default is unset, which matches the permissive behaviour NGF produced.

## Still open

- Single-node remains unvalidated in this mode.

## One transient failure worth expecting

The first `check-sso-e2e` immediately after the apply failed on `keycloak` with
a `toHaveURL` mismatch, then passed on a straight re-run with no intervention.
All pods were ready and Keycloak answered 302 in 33ms throughout, so this is the
OIDC apiserver restart still settling rather than a defect -- the same class of
transient the operator notes already describe for gateway pods. Treat the second
run as the signal.
