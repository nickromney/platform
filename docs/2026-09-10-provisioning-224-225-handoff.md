# Provisioning speed and issues #224 / #225: implementation handoff

Reviewed 2026-09-10 at `2dc7030d`. This is an investigation and execution plan,
not evidence of a new live provisioning run. No cluster was reset or changed.
Read `skills/use-platform/SKILL.md` and run root `make` before implementation.

Both issue descriptions lag this checkout: candidate fixes already exist.
Finish and validate them instead of implementing the original proposals again.

<!-- markdownlint-disable MD013 -->

| Work | Current conclusion | Next action |
| --- | --- | --- |
| Provisioning | Cache wiring and resource starvation have the strongest recorded timing evidence | Benchmark with identical profiles and cache state; preserve existing fixes |
| [#225](https://github.com/nickromney/platform/issues/225) | Push diagnostics and a registry-copy fallback exist; successful mirroring is not established by current tests | Reproduce the four images, classify actual errors, prove cached images can be pulled |
| [#224](https://github.com/nickromney/platform/issues/224) | DONE 2026-09-11: probe classification fixed, enforcement matrix added, live allow/deny proven | See `docs/2026-09-01-cilium-gateway-cutover.md` (admin IP allowlist) |

<!-- markdownlint-enable MD013 -->

## 1. Provisioning: what is known

Historical measurements come from `docs/2026-09-06-profile-aware-provisioning-handoff.md`
and `docs/2026-08-31-performance-pass-digest.md`. They are not fresh benchmarks.
There is no `.run/profiles` directory in this checkout to independently inspect.

<!-- markdownlint-disable MD013 -->

| Finding | Evidence | Resolution / remaining work |
| --- | --- | --- |
| Missing containerd mirror wiring | Same small profile: 632s healthy with local-cache preset; 2331s and Hubble timeout without | Pass `--preset image-distribution=local-cache` from cluster creation onward. A preview warning already exists. This comparison includes a failed run, so do not market it as a controlled speedup percentage. |
| Grafana CPU starvation | Recorded 16GB-profile stage 900 fell from 1204s to 643s after correcting a 75m CPU ceiling | Preserve the correction; inspect throttling and restart evidence before reducing resource limits again. |
| Disabled capabilities still built/deployed/checked | Prior missing toggle propagation caused bootstrap deadlocks and crashloops | Existing image-selection and render-contract fixes must remain aligned with effective feature state. |
| Repeated Kubernetes API reads | Previous Argo polling used about 129 reads / 13s per pass versus a 0.19s list | Batching is already implemented. Do not redo it or count its historical savings as a new result. |
| Repeated provider downloads and unrelated image rebuilds | Shared provider cache and input fingerprints already implemented | Preserve caches across resets and source-based build reuse. |
| Image mirroring serializes misses before Terraform | `kubernetes/kind/Makefile` runs cache sync, platform builds, workload builds, then Terraform; sync has a serial loop | Instrument per-image time first. Consider bounded concurrency only if measured cache misses dominate. |
| Backstage restarts on successful apply | Makefile restarts enabled externally built Backstage after every successful apply, then waits up to 600s | Candidate warm-apply optimization: prove content-tag rollout handles changed input before removing the unconditional restart. It is gated off on many small profiles. |

<!-- markdownlint-enable MD013 -->

Concrete files for speed work:

- `kubernetes/kind/Makefile`: apply recipe around lines 710–865; profiler starts
  after several prerequisites, so step timings omit some end-to-end cost.
- `terraform/kubernetes/scripts/profile-lib.sh`: writes `steps.tsv` and step logs.
- `kubernetes/workflow/image-selection-lib.sh` and `image-build-lib.sh`:
  profile resolution and source fingerprints.
- `kubernetes/scripts/sync-local-image-cache.sh`: serial cache scan/copy.
- `terraform/kubernetes/operator-facts.tf` and `locals.tf`:
  health and GitOps render-contract consumers of effective toggles.

Benchmark procedure for the implementing model:

1. Record commit, Docker memory/CPU/store, architecture, selected profile,
   distribution settings, and existing cache state. Run subtree `prereqs`.
2. Preview the exact workflow before running it. Example for the small profile:

   ```bash
   scripts/platform-workflow.sh preview --execute \
     --variant kind --stage 900 --action apply \
     --preset resource-profile=local-8gb \
     --preset image-distribution=local-cache --auto-approve
   ```

3. For an authorized benchmark run, replace `preview` with `apply`, export
   `PLATFORM_PROFILE_MODE=on`, and wrap the whole command in `/usr/bin/time -p`.
   Capture combined output as well as `.run/profiles/*/steps.tsv`.
4. Separate warm reapply, fresh cluster with warm registry, and cold registry.
   A reset does not imply a cold image cache. Reset requires authorization;
   never delete the user's registry volume merely to manufacture a baseline.
5. Compare at least three matched successful runs per configuration when
   practical. Report median total time and phases, cache hits/failures, retries,
   memory pressure, and final health/gateway/SSO outcomes.
6. Fix #225 before adding concurrency. If copying dominates, add a configurable
   worker cap (default 1 initially; compare 2 and 4), deterministic per-image
   results, and joined child statuses. Preserve credentials and upstream fallback.
   Do not parallelize dependent Terraform/Gitea/SSO stages or remove verification.

## 2. Issue #225: finish the cache fix

Implementation exists in `kubernetes/scripts/sync-local-image-cache.sh`, function
`mirror_remote_image`. It captures errors from both `docker push` and
`docker buildx imagetools create --prefer-index=false`, and corrects the obsolete
Docker Desktop classic-store comment. `kubernetes/tests/sync-local-image-cache.bats`
tests diagnostic failure but has no successful fallback test.

Important correction: `--prefer-index=false` avoids creating an index when the
single source is not already an index. It does not flatten an existing index or
repair missing content. The code comment claiming cert-manager compatibility is
not sufficient proof. See [Docker's command contract](https://docs.docker.com/reference/cli/docker/buildx/imagetools/create/).

Implement in this order:

1. Add a successful-fallback unit test: push fails, buildx succeeds; assert exact
   arguments, no final failure warning, and success. Add cache-hit/no-copy and
   pull-failure diagnostics tests. Preserve optional-cache semantics.
2. Prepare a four-line image list using `quay.io/jetstack/` and the names
   `cert-manager-controller`, `cert-manager-webhook`, `cert-manager-cainjector`,
   `cert-manager-startupapicheck`, all tagged `v1.21.1` (the issue reproduction
   versions, even if current pins change).
3. Run the shared helper with `IMAGE_LIST_FILE` pointing to that list and
   `CACHE_PUSH_HOST=127.0.0.1:5002`. Preserve source registry credentials. Use a
   separate disposable registry if tags already exist; a cache-hit run cannot
   reproduce the failed push. Do not delete existing cached images.
4. Record Docker/server/buildx versions, store type and architecture. Save both
   errors and source/target manifest descriptors. Do not suppress pull stderr;
   currently that earlier failure still loses its diagnostic.
5. Choose the fix from the actual error:
   - HTTP/HTTPS mismatch: fix the copying client's transport for this local
     registry; a Docker daemon setting may not configure buildx's registry client.
   - Missing platform content: use a verified registry-to-registry copy, or an
     explicitly selected runnable platform manifest if only that platform is
     required. Verify client support first; do not silently change a digest pin.
   - Index/attestation incompatibility: inspect descriptors and identify the
     unsupported object. Preserve multi-architecture content when required;
     do not globally strip attestations on a guess.
   - Authentication/network error: fix that path rather than changing manifests.
6. Pull each target from an independent consumer with no pre-existing image.
   Verify the runnable platform manifest digest and required blobs, not just
   `/tags/list`. For a deliberately platform-filtered copy, compare the selected
   manifest digest, not its parent's index digest.
7. Run sync again: all four should be cache hits. Verify a fresh node can use the
   mirror without an upstream pull. Capture registry access evidence.

Done means all four images really survive in the cache and pull successfully,
or an explicit documented unsupported case with visible diagnostics remains.
Warn-only continuation alone is not a performance fix. No speed benefit can be
quantified from the issue's warnings alone.

Useful regression command:

```bash
bats kubernetes/tests/sync-local-image-cache.bats \
  tests/kubernetes-sync-image-cache-adapter.bats
```

## 3. Issue #224: prove enforcement before declaring support

Current candidate: `render_cilium_admin_allowlist_policy` in
`terraform/kubernetes/scripts/sync-gitea-policies.sh`, around line 1889.
It selects `reserved:ingress`, combines source CIDRs and admin HTTP host regexes,
and adds public-host rules. It runs before NGF filter removal. The issue's old
hard refusal is therefore no longer the normal path in this checkout.

The concrete validation defect is in
`terraform/kubernetes/scripts/check-gateway-urls.sh`, around line 290:
when any allowlist is configured, **any probed URL returning 403 is accepted**
as allowlist success. It does not establish that the route is administrative
or that this client should be denied. Later checks verify selector and CIDR
presence only. An ineffective policy returning normal 2xx/3xx also passes.

[Cilium's Gateway documentation](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
describes the ingress identity and source-IP handling. It does not prove this
specific CIDR/L7 policy works on the repo's host-network TLS listener. Use docs
for the pinned Cilium version during implementation; do not upgrade to match the
moving stable documentation. Read ADR 0015 before drawing conclusions from drops.

Implement in this order:

1. Fix probe semantics and add regressions in
   `kubernetes/kind/tests/check-gateway-urls.bats`. Distinguish admin/public route
   and expected allowed/denied client. A public 403 must not pass merely because
   an allowlist exists. Preserve explicit machine-endpoint auth expectations.
2. Add an enforcement test mode with required allowed and denied probe origins.
   Missing origins must produce an explicit not-verified result, not a green
   enforcement claim. Ordinary availability checks can remain separate.
3. Validate the candidate on an isolated, authorized test cluster. Inspect
   selected endpoints, accepted policy, other policies selecting ingress, actual
   client source identity/IP, and Envoy policy attachment. Do not assume a rule
   targeting port 443 inspects decrypted HTTP without checking live behavior.
4. Use two genuinely distinct observed source addresses. Spoofing
   `X-Forwarded-For` is not a substitute. Docker Desktop port forwarding may
   collapse origins to one address; if so, test separate origins at the node
   network boundary and explicitly report the host-path limitation.
5. For each admin hostname, require an allowed source to reach its normal
   response and a denied source to be rejected. Require public hostnames to
   remain reachable from both. Test forged forwarding headers, Host/SNI
   mismatch, explicit `:443` authority, IPv4/IPv6 where available, and empty
   allowlist behavior. A timeout alone could mean a broken gateway.
6. Correlate denials with Cilium/Envoy policy evidence. L7 rejection need not
   produce an L3 drop; use equivalent HTTP policy/access-log observation if
   `cilium-dbg monitor --type drop` is silent. Observe the node where enforcement
   occurs, including the backend node when diagnosing backend drops.
7. If the candidate fails, preserve or restore fail-closed rendering for this
   unsupported configuration. Do not patch Cilium's generated CEC, put original
   client CIDRs on backends that see ingress identity, or broaden policies until
   the test passes accidentally. A separate admin listener/proxy is an
   architectural follow-up requiring a reviewed design, not a small-model guess.
8. Persist the working solution through Terraform/Gitea: run `gitea-sync`, wait
   for Argo reconciliation, and repeat the enforcement matrix. Live kubectl
   patches alone are not the deliverable.

Extend `kubernetes/kind/tests/sync-gitea-policies.bats` with parsed-YAML/regex
behavior assertions, multiple CIDRs, public/admin host separation, missing
route directories, and empty-list cleanup. Existing string assertions prove
rendering only; they cannot prove Cilium enforcement.

## 4. Delivery order and verification

Work as separate changes: #225 completion; #224 probe correction and live proof;
then any measured speed optimization. Each change should state the exact
before/after behavior, commands, environment and unresolved limitations.

Before pushing implementation, run `make lint && make test-ci`, plus
`make test-ci-linux` for shell/platform-sensitive changes. Track new shell/Bats
files before trusting tracked-file discovery. For Go changes also run formatting
and module `go test -race ./...`. PR CI does not supply this gate.

Investigation checks: the existing allowlist rendering test passed (1/1). The
image cache and adapter suite passed (4/4).
These are hermetic tests, not live Cilium or Docker registry proof. Do not close
either issue based solely on them.
