# Cilium Gateway API cutover: validated

Date: 2026-09-01. Two-node kind cluster, profile `.run/operator/cgw.tfvars`
(`cilium_gateway_api = true`, `cilium_kube_proxy_replacement = true`).

## Result

NGINX Gateway Fabric is gone. Cilium's Envoy serves every route.

```text
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

## Rebuilt from an empty Docker

Two rebuilds, because the first one did not test what it claimed.

`docker system prune -af --volumes` reclaimed 44.51 GB and took images from 127
to 1, and the rebuild after it ran in 13m36s. But that prune does not stop
running containers, and `--volumes` prunes only *anonymous* volumes -- so
`platform-local-image-cache` was still up with all 62 repositories, and the
rebuild pulled from it rather than from upstream.

Removing the registry container and its volume, then `docker volume prune -a`,
left Docker genuinely empty: 0 images, 0 containers, 0 volumes, 0 build cache.
Single-node, from that:

```text
100 apply + 900 apply   exit 0 in 20m07s
  Apply complete! Resources: 12 added   (stage 100)
  Apply complete! Resources: 118 added  (stage 900)
  0 FAIL

check-sso-e2e   14 passed / 0 failed in 27.4s
memory          5.47 GiB of 8.72 GiB
```

| build | time |
| --- | --- |
| fully warm | 13m20s |
| Docker images pruned, registry cache intact | 13m36s |
| genuinely empty Docker | 20m07s |

So the local registry cache is worth about six and a half minutes on a rebuild.
That is the number to quote; the sixteen seconds between the first two rows
measures almost nothing, because both had the cache.

## The image cache, and what it says about tagging

The cache is a plain registry you push to, not a pull-through cache
(`REGISTRY_PROXY_REMOTEURL`). That is the right choice here even though it looks
like more work: a pull-through cache proxies exactly one upstream, and this
stack pulls from docker.io, quay.io, ghcr.io and registry.k8s.io.

It does cache the kind node image -- `127.0.0.1:5002/kindest/node:v1.36.4` --
which is why a cluster comes up before anything reaches Docker Hub.

`docker images` shows a second `kindest/node` row with `<none>` for its tag.
That is not a stray layer. It is the same image ID, referenced by digest,
because `variables.tf` pins the node image as
`kindest/node:v1.36.4@sha256:099e0493...`. Docker renders a digest-only
reference with an empty tag column.

The `platform/*` images do carry a `latest` tag, but nothing deploys from it.
Each image has four references -- a semantic version, `latest`, the commit SHA,
and a `src-<fingerprint>` content hash -- and nine of the ten platform
Deployments reference the `src-` tag:

```text
dev  sentiment-api        sentiment-api:src-e6683805a7c851d42961
dev  subnetcalc-frontend  subnetcalc-frontend:src-140b5dd72b2fef4f7c47
idp  idp-core             idp-core:src-62b36c87238dc6ce985d
sso  keycloak             keycloak:26.6.4
```

That is what makes rollouts correct: a source change moves the tag, so the
Deployment template changes and Kubernetes actually restarts the pod. Images
sharing a fingerprint -- `sentiment-api` and `sentiment-auth-ui`, or the
subnetcalc pair -- are built from one source tree and are the same image serving
two roles, not duplicates.

### The registry's log output

`level=error` lines from this registry are not faults. A single successful push
and pull of one image produces three of them -- two `blob unknown` and one
`manifest unknown` -- because the client asks whether the registry already holds
each blob and manifest before uploading, and registry:2 logs every miss at error
severity. A cold build produced 514, all of them cache misses against an empty
cache.

The one genuine warning, `No HTTP secret provided`, is now fixed: the container
runs with a deterministic `REGISTRY_HTTP_SECRET` and a named volume
(`platform-local-image-cache-data`) instead of an anonymous one.

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

**TLS versions and ciphers are not lost.** I said they were; that was wrong.
Cilium has no declarative knob -- `CiliumGatewayClassConfig` exposes only
`serverHeaderTransformation`, `httpOptions`, `service` and `telemetry` -- but the
posture Envoy produces already matches what the NGINX config asked for. Measured
against the live gateway:

| probe | result |
| --- | --- |
| TLS 1.0, TLS 1.1 | refused |
| TLS 1.2, TLS 1.3 | both available, 1.3 negotiated by default |
| `TLS_AES_128_GCM_SHA256`, `TLS_AES_256_GCM_SHA384`, `TLS_CHACHA20_POLY1305_SHA256` | all available |
| RC4-SHA, DES-CBC3-SHA, AES128-SHA, NULL-SHA | all refused |

Those are the same three suites `ssl_conf_command Ciphersuites` pinned, and the
same versions `nginx.org/ssl-protocols: TLSv1.2 TLSv1.3` allowed.

What is genuinely missing is *enforcement*, not the outcome. A default is not a
setting: a Cilium or Envoy bump could move it with nothing to notice. So
`check-gateway-urls` now asserts the posture directly -- eleven probes covering
refused versions, available versions, the pinned suites, and four weak ciphers.
That is arguably stronger than the NGINX snippet was, because it verifies the
negotiated result rather than declaring an intent, and it runs against the NGINX
path too.

`ssl_session_tickets off` and `ssl_ecdh_curve` have no equivalent and are not
asserted.

Genuinely lost:

- **Admin IP allowlist.** No core Gateway API equivalent. Rather than render
  admin routes without the restriction they are configured to have, a non-empty
  `ADMIN_ROUTE_ALLOWLIST_CIDRS` is a hard failure in this mode. The local
  default is unset, which matches the permissive behaviour NGF produced. For a
  teaching cluster on loopback that is acceptable, but it should be called out
  rather than discovered. Tracked in
  [#224](https://github.com/nickromney/platform/issues/224).

## Single-node also works, and is the better shape

Validated the same day, `KIND_WORKER_COUNT=0`, built from a full reset:

```text
reset + 100 apply + 900 apply   exit 0 in 13m20s
  Apply complete! Resources: 118 added, 0 changed, 1 destroyed.
  148 OK / 0 FAIL in-apply verification

check-sso-e2e   14 passed / 0 failed in 20.0s
memory          5.44 GiB of 8.72 GiB
```

Compared with the two-node cluster: 5.44 GiB against 6.17, and the browser
suite finishes in 20 seconds against 3.9 minutes. Single node is not a
compromise here, it is the faster and smaller configuration.

The failure that made single-node unusable under NGINX Gateway Fabric is gone.
That failure was a TLS handshake reset on host 443 -- `client closed connection
while SSL handshaking` -- and it is absent from this build; the only matches for
"handshake" in the log are Gateway API CRD description text. The reason is
structural rather than a fix: NGF terminated on a pod reached through a
NodePort, so on one node the request never took the cross-node hop the hardened
policies assumed. Cilium's Envoy binds :443 directly in the node's host network,
so there is no NodePort hop to get wrong.

`cilium_mtu` was wired earlier on the theory that Docker Desktop's jumbo MTU
caused that reset. It was never needed and is left at its default. The MTU was
not the cause.

The control-plane untaint via `kind_control_plane_kubeadm_config_patches` is
what makes workloads schedulable on a single node, and it applied cleanly --
the node came up with no taints.

Spot-checked on this cluster: the Hubble NodePort returns 200 (the path the
default-deny regression broke), and a route that never carried a SnippetsFilter
serves all four security headers.

## One transient failure worth expecting

The first `check-sso-e2e` immediately after the apply failed on `keycloak` with
a `toHaveURL` mismatch, then passed on a straight re-run with no intervention.
All pods were ready and Keycloak answered 302 in 33ms throughout, so this is the
OIDC apiserver restart still settling rather than a defect -- the same class of
transient the operator notes already describe for gateway pods. Treat the second
run as the signal.
