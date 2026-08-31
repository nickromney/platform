# 2026-08-31 Performance pass digest

Third in the trio after mutation testing and cyclomatic complexity. Goal: a
working local cluster, passing browser E2E, under 8 GB of Docker memory.

The version-bump work was the smaller half. The substance was eight latent
defects, every one found by running something rather than reading it.

Related ADRs: [0012](./adr/0012-hardened-cilium-ingress-assumes-cross-node-nodeport.md),
[0013](./adr/0013-resource-profiles-reduce-only.md),
[0014](./adr/0014-browser-e2e-defines-a-working-cluster.md).
Deep dive: [single-node Cilium ingress](./2026-08-31-single-node-cilium-ingress-digest.md).

## Result

| | before | after |
| --- | ---: | ---: |
| pods | 90 | 66 |
| memory requests | 7624 Mi | 4936 Mi (-35%) |
| memory actual | 5919 Mi | 4660 Mi (-21%) |
| CPU requests | 4155m | 3020m (-27%) |
| Docker containers | 6.48 GiB | 6.28 GiB of an 8.72 GiB limit |

Verified on a cluster that serves: apply `exit=0`; `check-gateway-urls` 57 OK /
0 FAIL; `check-sso-e2e` 12 passed / 0 failed; full repo gate 1358 ok / 0 fail.

## Measured baselines worth keeping

- kube-apiserver is the largest single consumer at 1379 MiB RSS, and it is
  dominated by CRD **schema** overhead rather than object volume: 95 CRDs and
  164 API resources hold only 2402 objects, with 85 of 153 tracked resources
  holding none.
- Controlled experiment on a bare kind cluster: installing 22 CRDs moved
  apiserver RSS from 246 MiB to 377 MiB, i.e. **~5.9 MiB per CRD**. External
  Secrets alone was 24 CRDs for 2 objects.
- 13 per-app oauth2-proxy deployments each reserved 64Mi and used ~5Mi.
- `dev` reserved 1216 Mi and used 14; `uat` reserved 1088 Mi and used 14 --
  and most of those pods were in `ImagePullBackOff` on stale `src-<hash>` tags,
  reserving budget while running nothing.
- Requests and actual usage fail differently. Requests stop pods scheduling at
  all on a small Docker Desktop; actual usage is what OOMs. Fixing one does not
  fix the other.

## The eight defects

1. **Inert valkey resource block.** Configured under `master:`, a key the
   vendored subchart does not have, so the chart's `resourcesPreset: nano` won
   silently. The live pod proved it: 100m/128Mi requests and 150m/192Mi limits
   the repo never asked for.
2. **kind's single-node untaint is a no-op here.**
   `kind-node-kubectl-wrapper.sh` is mounted over `/usr/local/bin/kubectl` in
   every node and exits 0 without running kubectl unless passed `--execute`,
   which kind never does. The same gate silently disables kind's
   `installstorage`; the repo compensates elsewhere.
3. **`render-operator-overrides.sh` overrode any profile's `worker_count`,**
   writing it as the last `-var-file`, contradicting the repo's documented
   `source_precedence`.
4. **Preload toggles cross-wired.** `filter_images_by_toggles` takes ten
   positional toggles; `progressive_delivery` read `$6` (external-secrets'
   slot), sso/actions-runner/langfuse were each shifted one early, and `${10}`
   was never read. Langfuse could never be preloaded regardless of configuration.
   Hubble had no image predicate at all.
5. **`kubectl rollout status` leaking onto the stdout of a Terraform
   `data "external"`,** failing stage 900 outright with
   `Result Error: invalid character 'd'`. The best-effort branch three lines
   above already discarded that output.
6. **The operator facts contract was missing a key,** so the resolver fell back
   to the `variables.tf` default and asserted an Application the apply had
   deliberately pruned.
7. **`PLATFORM_TFVARS` never reached the post-OIDC health check.** The script
   already read it; Terraform had no `platform_tfvars_file` variable to supply.
   Every profile-level toggle was invisible there.
8. **Three ungated E2E target groups,** including Grafana dashboards gated on
   their data sources but never on Grafana itself -- which breaks any profile
   with victoria-logs on and grafana off, independently of this work.

## Deployment-time changes

- **Shared terragrunt provider plugin cache.** `make reset` deletes
  `$(STACK_DIR)/.terraform` -- 284MB of lockfile-pinned, content-addressed
  provider binaries. The cache lives at the repo root, outside the runtime scope
  reset removes. Proven across a real reset: `.terraform` deleted, cache intact.
- **Argo CD convergence reads batched.** Every predicate issued its own
  `kubectl get app <name>`, 3-10 round trips per application, ~129 serial reads
  on a 43-app cluster. Measured at 0.101s per read, that is ~13.0s per polling
  pass against 0.19s for one list -- multiplied by every iteration an apply
  spends waiting.
- **Apply retry widened.** The Makefile retried only on
  `certificate signed by unknown authority`. The first `100 apply` after a reset
  can also fail because `locals.tf` picks the provider kubeconfig with
  `fileexists()`, evaluated at plan time; reset deletes the kubeconfig, the
  provider binds the committed empty fallback and dials localhost:80, and kind
  writes the real kubeconfig too late. A re-run succeeds. Note this retry has
  **not** been exercised live -- the race did not recur -- only unit-tested.

The end-to-end ">=20% faster deployment" target was never measured. There is no
before/after on a full apply, only component evidence.

## Held back deliberately

- **Argo CD 10.4.0 and Kyverno 3.9.0.** Both need `dhi.io` `-debian13` hardened
  images whose existence cannot be confirmed from a normal shell. An
  unverifiable tag means ImagePullBackOff on a slow-to-rebuild cluster.
- **Kyverno's `policies.kyverno.io` group** (11 CRDs, 0 objects, ~65 MiB) is
  unreachable at chart 3.8.2: those CRDs come from the separate `kyverno-api`
  dependency chart with unconditional templates, and `helm template` emits all
  22 CRDs with every `crds.groups.policies.*` set to false.
- **The Gateway API bundle** is the experimental channel; ~6-8 CRDs hold zero
  objects (~35-47 MiB), but it is applied unconditionally and trimming it needs
  a throwaway cluster to verify.
- **Backstage npm majors** (react 18->19, react-router 6->8, typescript 5->7).
  Migration work, not hygiene.
- **Single-node.** See ADR 0012.

## Process notes worth repeating

- `check-cluster-health` passing is not an end-to-end result. It reported a
  healthy cluster that served nothing.
- Playwright stops at the first failure and reports the rest as `-`. Count the
  outcomes; the failure count alone understates the damage.
- Run diagnostic experiments with stderr visible. One "experiment" here proved
  nothing because the pod never moved and the errors were redirected away.
- `run-opentofu-tests.sh` defaults to a 180s timeout while the Makefile passes
  600s. Invoking the script directly under contention produces a misleading
  `Plugin did not respond` failure that is really a timeout.
- `tests/validate-app-runtime-surfaces.bats` was outside the CI gate and caught
  image refs the gate missed. It has since been graduated onto the gate.
