# 2026-07-09 Kind Reset Proof Digest

Context: validation run for the kind `reset -> 100 apply -> 900 apply` confidence path, including clean-local-state, Docker cleanup, individual tests, E2E, Grafana dashboard navigation, and traces/metrics/logs data checks.

## Final Pass Additions

- `.devcontainer/toolchain-versions.sh`
  - Bumped mature tool pins that were behind after the reset proof, including Bun `1.3.14`, Kyverno CLI `1.18.1`, Cilium CLI `0.19.5`, Helm `4.2.2`, Hubble `1.19.4`, jq `1.8.2`, kind `0.32.0`, kubectl `1.36.2`, kubie `0.28.0`, OpenTofu `1.12.3`, starship `1.26.0`, step `0.30.6`, and Terragrunt `1.1.0`.
  - Left cooldown-blocked updates out of the applied set: arkade until 2026-07-14, lefthook until 2026-07-15, and Lima until 2026-07-10.

- `terraform/kubernetes/apps/argocd-apps/*.application.yaml`, `terraform/kubernetes/variables.tf`, and `terraform/kubernetes/.terraform.lock.hcl`
  - Bumped GitOps chart/provider pins that were mature: Argo CD chart `10.1.2`, cert-manager `v1.21.0`, OpenTelemetry Collector chart `0.164.1` with collector image `0.155.0`, policy-reporter `3.8.1`, Prometheus chart `29.14.0` with Prometheus `v3.13.0`, and `hashicorp/kubernetes` provider `3.2.1`.

- `scripts/update-versions.sh` and `tests/update-versions.bats`
  - Fixed `http_get` so `curl` reads from `/dev/null` and cannot drain a caller's TSV loop.
  - Fixed the devcontainer latest-base jq resolver.
  - Added a fake-curl stdin-drain regression and an exact-output test using `[ "${output}" = "${expected}" ]`.

- `terraform/kubernetes/scripts/preload-images.sh` and `kubernetes/kind/tests/preload-images.bats`
  - Preserved explicit `@sha256:` refs when refreshing the preload lock.
  - Taught tag pinning to handle explicit digest refs without retagging digest targets.
  - Refreshed `terraform/kubernetes/scripts/preload-images.linux-arm64.lock`.

- `terraform/kubernetes/scripts/check-component-version.sh` and `kubernetes/kind/tests/check-version.bats`
  - Treated Gitea `-rootless` deployment tags as equivalent to the base upstream application version when the base version matches.

- `terraform/kubernetes/scripts/sync-gitea-policies.sh` and `kubernetes/kind/tests/sync-gitea-policies.bats`
  - Hardened vendored chart validation so poisoned or incomplete Helm chart archives must include `Chart.yaml`, `values.yaml`, renderable content under `templates/`, `crds/`, or `charts/`, and at least four non-directory files.
  - Isolated Helm cache/home during chart fetches so a broken global Helm content cache cannot seed incomplete GitOps chart output.

- `terraform/kubernetes/apps/argocd-apps/96-otel-collector-prometheus.application.yaml`
  - Removed the collector file-storage checkpoint dependency for the deployment collector by setting `presets.logsCollection.storeCheckpoints: false`.
  - This fixed the `file_storage` lock crash while preserving normal RollingUpdate behavior.

- `scripts/platform-workflow.sh` and `tests/platform-workflow-matrix.bats`
  - Fixed Bash 3.2 / `set -u` empty-array expansion in default workflow preview rendering.
  - Guarded the empty `CUSTOM_OVERRIDES` loops in `render_custom_overrides`, `warnings_json`, `render_tfvars`, and `build_workflow_script_args`.

- `terraform/kubernetes/apps/mcp/all.yaml` and `tests/kubernetes-mcp-manifests.bats`
  - Corrected `OTEL_EXPORTER_OTLP_ENDPOINT` from the stale `otel-collector-prometheus` service name to `http://otel-collector.observability.svc.cluster.local:4318`.
  - Added a manifest test for that exact endpoint.

- `terraform/kubernetes/observability.tf` and `terraform/kubernetes/apps/argocd-apps/95-grafana.application.yaml`
  - Aligned the checked-in Grafana app overview dashboard with the Terraform-rendered dashboard.
  - Replaced stale `http_server_requests_seconds_*` panels with OTel span-metrics queries over `traces_span_metrics_calls_total` and `traces_span_metrics_duration_milliseconds_bucket`.
  - Kept explicit zero fallbacks for sparse app signals.

- `kubernetes/kind/preload-images.txt`, `kubernetes/lima/preload-images.txt`, `kubernetes/docker-desktop/preload-images.txt`, and `terraform/kubernetes/scripts/preload-images.linux-arm64.lock`
  - Added and locked `mcr.microsoft.com/playwright:v1.58.2-noble` as a managed local-cluster cache input.
  - Final local Docker cache digest: `mcr.microsoft.com/playwright@sha256:68f1c3dca663d0e8331e8af4681b0b315eca7de1bd7fa934aac0accbeb9f8323`.

## But-for-real Follow-up

- `terraform/kubernetes/observability.tf`, `terraform/kubernetes/apps/argocd-apps/95-grafana.application.yaml`, and `tests/grafana-dashboard-quality.bats`
  - Found that the Grafana app overview LLM latency panel still assumed a dimensionless OTLP histogram export (`llm_inference_latency_ms_bucket`).
  - Natural OTLP metrics with unit `ms` export through Prometheus as `llm_inference_latency_ms_milliseconds_bucket`.
  - Updated the dashboard query to accept both metric-family spellings, retained the explicit zero fallback, and added a static assertion for the `_milliseconds` family in both dashboard sources.

- `terraform/kubernetes/scripts/preload-images.sh` and `kubernetes/kind/tests/preload-images.bats`
  - Found that digest-pinned explicit image refs could be pulled successfully but skipped during `kind load` if Docker only had the pinned `repo@sha256:...` ref locally, not the original `repo:tag@sha256:...` spelling.
  - Added a load-time fallback to use the pinned digest ref for `docker save`/`kind load` while preserving the original image label in user-facing output.
  - Added a regression test for the explicit-digest pull/load path.

- `terraform/kubernetes/scripts/sync-gitea-policies.sh`
  - Tightened the isolated Helm fetch failure path so both the temporary chart fetch directory and temporary Helm home/cache are removed when `helm repo add`, `helm repo update`, or `helm pull` fails.

- `kubernetes/kind/tests/check-memory-preflight.bats`
  - Found a shard-only flake in the `lsof` timeout retry fixture: a one-second timeout could kill the second, otherwise instant fake `lsof` under seven-way shard load.
  - Widened that fixture's timeout while keeping the first fake attempt longer than the timeout, so the test still proves the retry behavior without depending on a one-second scheduler window.

- `kubernetes/kind/cp`
  - Removed an accidental empty untracked file left in the kind tree.

## Fixes Made So Far

- `kubernetes/scripts/render-launchpad.sh`
  - Fixed Bash 3.2 `set -u` empty-array expansion by using the repo's guarded array expansion pattern for optional `--target` forwarding.

- `kubernetes/kind/scripts/run-bats-shards.sh`
  - Reworked indexed array subscripts to avoid ShellCheck `SC2004` while staying Bash 3.2-compatible.

- `terraform/kubernetes/scripts/hubble-observe-cilium-policies.sh`
  - Restored the missing namespace worker launch before recording `$!`; the script was otherwise waiting on the shared Hubble port-forward and hanging.
  - Restored Hubble candidate policy annotations in generated manifests.
  - Added the same Hubble candidate annotation facts to the `--contract` JSON.

- `kubernetes/kind/tests/check-version.bats`
  - Updated the external-image audit fixture to include a real `dhi.io` row before asserting the `vendor-managed mirror` status.

- `kubernetes/kind/tests/render-kind-apiserver-oidc-manifest.bats`
  - Wrapped an orphan test body in a named `@test`; it was executing during Bats test discovery with `BATS_TEST_TMPDIR` unset and trying to write `/kube-apiserver.yaml`.
  - Updated legacy helper invocations to pass the current seven-argument renderer contract.

- `tools/platform-helpers/cmd/render-kind-apiserver-oidc-manifest/main.go`
  - Allowed empty existing `hostAliases:` blocks to be replaced by the managed OIDC host alias instead of being treated as unrelated aliases.

- `kubernetes/kind/tests/sync-gitea.bats`
  - Restored missing `run` commands in two Terraform-default fallback tests.
  - Replaced stale hard-coded `agentgateway_chart_version` expectations with the live `tf_default_from_variables` value.

- `terraform/kubernetes/scripts/sync-gitea.sh`
  - Exported `SSO_PUBLIC_URL` so the policies renderer receives the Headlamp OIDC issuer input alongside the Headlamp host, client secret, and TLS-skip flag.

- `terraform/kubernetes/scripts/check-component-version.sh`
  - Restored the Gitea Argo CD Application image-tag extractor's resource-pattern match.
  - Restored the pyproject `[project].dependencies` parser's array fragment capture so it reads project dependencies and ignores optional/dev dependency groups.

- `kubernetes/kind/tests/makefile.bats`
  - Restored the missing `run make -n ... check-app` invocation in the ordered tfvars forwarding test.

- `kubernetes/lima/tests/makefile.bats`
  - Restored the same missing `run make -n ... check-app` invocation in the Lima ordered tfvars forwarding test.

- `kubernetes/lima/Makefile` and `kubernetes/lima/tests/makefile.bats`
  - Aligned Lima's OpenTofu test timeout with kind by defaulting `TOFU_TEST_TIMEOUT_SECONDS` to 600 and forwarding it to `run-opentofu-tests.sh`; the previous 180-second helper default interrupted the full module suite mid-run.

- `terraform/kubernetes/locals.tf`
  - Resolved the provider fallback kubeconfig template through the real repo root instead of `local.stack_dir`, so tests and Terragrunt-style runs that use a synthetic stack dir still read the committed `templates/empty-kubeconfig.yaml`.

- `terraform/kubernetes/policies.tf`
  - Restored Kyverno chart image overrides to the hardened image registry path (`dhi.io` by default) for the admission, init, background, cleanup, and reports controller images.

- `terraform/kubernetes/apps/argocd-apps/20-kyverno.application.yaml`
  - Kept the GitOps app-of-apps seed manifest aligned with the hardened Kyverno image overrides used by the Terraform-managed direct Application.

- `kubernetes/kind/preload-images.txt` and `kubernetes/lima/preload-images.txt`
  - Updated the Kyverno preload image list to match the hardened image refs now rendered into the cluster.

- `terraform/kubernetes/tests/gitops_features.tftest.hcl`
  - Updated the observability-agent test to exercise the app-of-apps delivery path instead of a removed direct `argocd_app_otel_collector_agent` resource.
  - Restored the Alertmanager local-kind resource-bound contract by matching the Terraform-rendered Prometheus Application to the test's tighter requests/limits.

- `terraform/kubernetes/observability.tf` and `terraform/kubernetes/scripts/sync-gitea-policies.sh`
  - Restored Alertmanager's local-kind resource requests/limits to `10m/32Mi` requests and `40m/96Mi` limits in both direct Terraform output and GitOps-rendered output.

- `terraform/kubernetes/tests/resource_bounds.tftest.hcl`
  - Made Gitea credentials explicit in tests that enable Gitea, removing dependence on ambient `TF_VAR_*` state.
  - Adjusted the application namespace resource-bounds fixture to satisfy the current app-repo validation contract by enabling Gitea Actions with explicit credentials.

- `terraform/kubernetes/tests/sso_oidc.tftest.hcl`
  - Updated redirect URI coverage to include the current map-backed OAuth2 proxy app sets.
  - Replaced a stale `argocd_app_dex` dependency string check with the current Keycloak service dependency sequence.
  - Updated the ChatGPT simulator skip-auth regex assertion to match the current static asset allowlist.

- `terraform/kubernetes/cluster.tf`
  - Collapsed duplicated image-preload trigger and environment map entries into one explicit set that includes the progressive-delivery preload toggle.

- `kubernetes/kind/tests/sync-gitea-policies.bats`
  - Updated the Prometheus renderer assertion to match the restored Alertmanager `10m/32Mi` request and `40m/96Mi` limit contract.

- `kubernetes/kind/tests/check-version.bats`
  - Replaced a brittle wall-clock assertion in the parallel line mapper test with an observed max-active-worker assertion, so the test proves bounded concurrency without depending on host scheduler timing.

- `apps/chatgpt-sim/app/internal/app/web/index.html`
  - Removed invalid `aria-label` and `tabindex` attributes from non-interactive `<pre>` output panels so Biome accessibility checks pass.

- `apps/sentiment/app/internal/app/web/index.html` and `apps/sentiment/app/internal/app/server_test.go`
  - Replaced a sample-button `<div aria-label=...>` with a semantic `fieldset`/`legend`, and updated the frontend parity test accordingly.

- `apps/subnetcalc/app/internal/app/web/index.html`
  - Replaced the examples `<div aria-label=...>` with a semantic `fieldset`/`legend` so the app passes current Biome accessibility checks.

- `tests/backstage-compose.bats`
  - Replaced the stale Backstage compose browser assertion for `"Hello Platform"` with the current visible `"Sentiment"` content.

- `sites/docs/content/concepts/platform-pathways.mdx`
  - Added a meaningful warning callout so the docs content lint has the expected semantic warning block on the page.

- `sites/docs/public/diagrams/**`
  - Regenerated D2 SVG outputs with the repo media pipeline after docs tests reported stale generated diagrams.

- `terraform/kubernetes/sso.tf`
  - Updated all GitOps-managed OAuth2 proxy Applications from `dhi.io/oauth2-proxy:7.15.2-debian13` to `7.15.3-debian13`. The full Docker clean removed stale local state, and the live kind run proved only `7.15.3-debian13` was present in the local registry/cache.

- `kubernetes/workflow/image-catalog.json`, `kubernetes/kind/targets/kind.tfvars`, `kubernetes/lima/targets/lima.tfvars`, `terraform/kubernetes/tests/validations.tftest.hcl`, `tests/artifacts/perf/20260605T224406Z-image-catalog-pass3/operator-overrides-golden.tfvars`, `kubernetes/kind/tests/check-version.bats`, and `kubernetes/kind/tests/sync-gitea-policies.bats`
  - Updated the Grafana VictoriaLogs platform image reference from `12.3.1-v0.28.0` to `12.3.1-v0.29.0`. The clean stage-900 apply built and published `12.3.1-v0.29.0`, but manifests still requested the removed `12.3.1-v0.28.0` tag.

- `tests/kubernetes/sso/run.sh`, `tests/kubernetes/sso/README.md`, and `tests/kubernetes-sso-runner.bats`
  - Made the SSO Playwright runner default to Docker mode, using `mcr.microsoft.com/playwright:v<playwright-core>-noble`, so reset proofs do not depend on host Playwright browser caches removed by `clean-local-state`.
  - Kept native host-browser mode explicit via `PLATFORM_PLAYWRIGHT_MODE=native`; no Chrome/Safari auto-detection is used.

- `kubernetes/kind/preload-images.txt`, `kubernetes/lima/preload-images.txt`, `kubernetes/docker-desktop/preload-images.txt`, `terraform/kubernetes/scripts/preload-images.linux-arm64.lock`, `kubernetes/workflow/image-catalog.json`, `terraform/kubernetes/scripts/check-component-version.sh`, `tests/app_contracts.py`, `tests/validate-app-runtime-surfaces.bats`, `kubernetes/kind/Makefile`, and `kubernetes/kind/tests/makefile.bats`
  - Added `mcr.microsoft.com/playwright:v1.58.2-noble` to the managed local-cluster cache inputs and locked the pulled arm64 digest as `mcr.microsoft.com/playwright@sha256:68f1c3dca663d0e8331e8af4681b0b315eca7de1bd7fa934aac0accbeb9f8323`.
  - Added a preload-alignment catalog rule that checks the Playwright image tag against `tests/kubernetes/sso/bun.lock`, so bumping Playwright also requires bumping the cached Docker runtime image.
  - Updated kind prereqs to report the default Playwright Docker image cache status while preserving the native browser-cache probe only for explicit native mode.

- `terraform/kubernetes/scripts/render-platform-launchpad.sh`, `terraform/kubernetes/observability.tf`, `terraform/kubernetes/apps/argocd-apps/95-grafana.application.yaml`, `tests/app_contracts.py`, and `tests/kubernetes/sso/tests/sso-smoke.spec.ts`
  - Gave the Grafana Prometheus datasource the stable `prometheus` UID and rendered launchpad targets against that explicit datasource object, avoiding unresolved datasource placeholders in the generated JSON.
  - Removed the stale launchpad datasource variable contract and added tests that require the stable datasource UID.
  - Changed the launchpad browser proof to authenticate to Grafana, read the dashboard definition through Grafana's dashboard API, and navigate every linked stat tile target in the browser context. This validates the live dashboard JSON and target URLs without depending on Grafana's scene loader finishing its client-side render.

## Verification Notes

- Confirmed `/bin/bash` is GNU Bash `3.2.57`, and syntax checks are being run against `/bin/bash`.
- `bats tests/kubernetes-launchpad-render.bats`: passed after the launchpad fix.
- Isolated check-version external-image audit test: passed after fixture correction.
- Isolated Hubble observation contract test: passed after contract annotation fix.
- `timeout 240 bats kubernetes/kind/tests/hubble-observe-cilium-policies.bats`: passed all 19 tests after restoring the namespace worker launch and annotations.
- `go test ./...` from `tools/platform-helpers`: passed after the manifest-renderer fix.
- `bats kubernetes/kind/tests/render-kind-apiserver-oidc-manifest.bats`: passed all 4 tests.
- `bats kubernetes/kind/tests/sync-gitea.bats`: passed all 11 tests.
- Focused `check-version` Gitea image override test: passed after restoring the extractor.
- Focused `check-version` pyproject dependency parser test: passed after restoring fragment capture.
- Focused kind `check-app` Makefile forwarding test: passed after restoring the missing `run` invocation.
- Focused Lima `check-app` Makefile forwarding test: passed after restoring the missing `run` invocation.
- Focused Lima OpenTofu timeout contract test: passed after aligning the Lima test target with kind's 600-second default.
- `terraform/kubernetes/scripts/run-opentofu-tests.sh --filter tests/validations.tftest.hcl --timeout-seconds 600`: passed all 16 validation tests after the provider fallback path fix.
- `terraform/kubernetes/scripts/run-opentofu-tests.sh --filter tests/gitops_features.tftest.hcl`: passed all 14 tests after Kyverno, observability-agent, and Alertmanager fixes.
- `terraform/kubernetes/scripts/run-opentofu-tests.sh --filter tests/resource_bounds.tftest.hcl`: passed all 3 tests after making Gitea inputs explicit.
- `terraform/kubernetes/scripts/run-opentofu-tests.sh --filter tests/sso_oidc.tftest.hcl`: passed all 4 tests after refreshing redirect, dependency, and cookie assertions.
- Focused `sync-gitea-policies` Prometheus renderer test: passed after updating the Alertmanager resource assertion.
- Focused `check-version` parallel line mapper test: passed after replacing wall-clock timing with observed concurrency.
- `make -C kubernetes/kind test`: passed after the final fixes:
  - stage monotonicity: passed
  - Bash 3.2 compatibility: passed across 198 scripts
  - shell audit: passed across 117 scripts and 96 executable entrypoints
  - Kind Bats shards: 407 passed, 0 failed
  - OpenTofu validation: passed
  - OpenTofu tests: 72 passed, 0 failed
- `make -C apps/chatgpt-sim test`: passed after the output-panel markup fix.
- `make -C apps/sentiment test`: passed after the semantic sample group fix.
- `make -C apps/subnetcalc test`: passed after the semantic examples group fix.
- `make -C apps test`: passed after the app accessibility fixes; aggregate covered shared app tests and all app wrapper test targets.
- `make -C docker/compose test`: passed after refreshing the Backstage browser smoke assertion.
- `make -C sites/docs test`: passed after adding the warning callout and regenerating stale D2 diagrams.
- `make -C kubernetes/lima test`: passed after the Lima timeout and provider fallback fixes:
  - stage monotonicity: passed
  - Bash 3.2 compatibility: passed across 198 scripts
  - shell audit: passed across 109 scripts and 88 executable entrypoints
  - Lima Bats: 55 passed, 0 failed
  - OpenTofu validation: passed
  - OpenTofu tests: 72 passed, 0 failed
- `make clean-local-state DRY_RUN=1 INCLUDE_HOST_CACHES=1 INCLUDE_KUBECONFIGS=1 INCLUDE_DOCKER=1`: completed and previewed 1.36 GiB of repo-generated state, 5.07 GiB of selected host paths, and a 37.31 GB Docker prune sequence estimate.
- `make clean-local-state INCLUDE_HOST_CACHES=1 INCLUDE_KUBECONFIGS=1 INCLUDE_DOCKER=1`: completed; removed repo-generated state, host caches, and `~/.kube/kind-kind-local.yaml`; Docker builder prune reclaimed 30.52 GB and Docker system prune reclaimed 20.91 GB.
- `make docker-safe-clean AUTO_APPROVE=1`: completed after the broader cleanup; preserved the two running `kind-local` containers and reclaimed 0 B because no unused non-protected Docker resources remained.
- `make -C kubernetes/kind reset AUTO_APPROVE=1`: completed; deleted the `kind-local` cluster, confirmed the split kubeconfig was absent, removed any default kubeconfig entries, and cleaned kind stack state/caches.
- `make -C kubernetes/kind 100 apply AUTO_APPROVE=1`: completed from the cleaned state; recreated the kind cluster, wrote `/Users/nickromney/.kube/kind-kind-local.yaml`, restarted containerd on both nodes, and added 11 OpenTofu resources.
- First `make -C kubernetes/kind 900 apply AUTO_APPROVE=1` reached the post-OIDC health check and exposed live image drift:
  - OAuth2 proxy pods were `ImagePullBackOff` for `dhi.io/oauth2-proxy:7.15.2-debian13`; the registry contained `7.15.3-debian13`.
  - Grafana was `Init:ImagePullBackOff` for `host.docker.internal:5002/platform/grafana-victorialogs:12.3.1-v0.28.0`; the registry contained `12.3.1-v0.29.0`.
  - NGINX Gateway initially crash-looped during the kube-apiserver OIDC restart window with transient in-cluster API connection refusals, then the recovery helper restarted it and confirmed service endpoints and Gateway reprogramming.
- Interrupted the known-bad health wait after the image drift was isolated. That left a stale OpenTofu lock and a zero-byte live state file:
  - Verified no `tofu` or `terragrunt` process was active.
  - Removed only the generated stale lock file.
  - Restored the Makefile-selected non-empty state snapshot.
  - Retrying against the live partially-applied cluster then failed with expected `AlreadyExists` conflicts because the restored snapshot predated live stage-900 resources. The clean recovery path is another kind reset and fresh `100 apply`/`900 apply` with the corrected tags.
- Focused checks after the image tag fixes:
  - `bats --filter 'check-version reads image version-check policies from image catalog' kubernetes/kind/tests/check-version.bats`: passed.
  - `bats --filter 'check-version drives preload alignment from image catalog projection' kubernetes/kind/tests/check-version.bats`: passed.
  - `bats --filter 'render_grafana_application_manifest injects Grafana image and plugin values' kubernetes/kind/tests/sync-gitea-policies.bats`: passed.
  - `terraform/kubernetes/scripts/run-opentofu-tests.sh --execute --filter tests/validations.tftest.hcl --timeout-seconds 600`: passed all 16 validation tests.
- Pulled and cached `mcr.microsoft.com/playwright:v1.58.2-noble`; Docker resolved it to arm64 digest `sha256:68f1c3dca663d0e8331e8af4681b0b315eca7de1bd7fa934aac0accbeb9f8323`.
- Focused checks after making Playwright Docker mode the default:
  - `bats tests/kubernetes-sso-runner.bats`: passed all 4 tests.
  - `bats --filter 'kind prereqs checks Playwright cache status|kind exposes a playwright-install target' kubernetes/kind/tests/makefile.bats`: passed both tests.
  - `bats --filter 'check-version drives preload alignment from image catalog projection' kubernetes/kind/tests/check-version.bats`: passed.
  - `bats --filter 'preload image artifacts track the current external runtime bump set' tests/validate-app-runtime-surfaces.bats`: passed.
- Focused checks after the launchpad datasource and e2e change:
  - `terraform/kubernetes/scripts/run-opentofu-tests.sh --execute --filter tests/validations.tftest.hcl --timeout-seconds 600`: passed all 16 validation tests.
  - `bats --filter 'Platform Launchpad rendered dashboard avoids unknown placeholders and tile drift' tests/application-surface-projection.bats`: passed.
  - `bats tests/kubernetes-launchpad-render.bats`: passed.
  - `make -C kubernetes/kind check-sso-e2e STAGE=900 SSO_E2E_TEST_GREP=grafana-launchpad`: passed 1 browser test.
  - `make -C kubernetes/kind check-sso-e2e STAGE=900`: passed 22 browser tests, skipped 1 compose-only test.
- Final `make -C kubernetes/kind 900 apply AUTO_APPROVE=1`: exited 0 after the Playwright and launchpad fixes.
  - Prereqs reported `mcr.microsoft.com/playwright:v1.58.2-noble cached`.
  - Local registry cache reported `OK cached 127.0.0.1:5002/playwright:v1.58.2-noble`.
  - OpenTofu applied with `0 added, 1 changed, 0 destroyed`; the only change was removal of Argo CD tracking/sync-wave annotations from the Terraform-owned `argo-rollouts` namespace.
  - Health passed with all Argo CD Applications Synced/Healthy, policy checks clean, gateway/TLS checks clean, and `Health check completed`.
  - The launchpad gate evaluated 21 selected tiles; each tile had a healthy expression and a reachable URL.
  - Gateway URL checks passed for the expected local HTTPS endpoints.
  - Docker-mode SSO E2E passed 22 browser tests and skipped 1 compose-only test in 1.1 minutes. This included `grafana-launchpad`, `grafana-admin`, `grafana-platform-namespace-health`, `grafana-mcp-observability`, and `grafana-backstage-observability`.

### But-for-real Verification

- `/bin/bash -n terraform/kubernetes/scripts/preload-images.sh`: passed after splitting the explicit-digest predicate out of a `[[ ... ]]` expression.
- `/bin/bash -n terraform/kubernetes/scripts/sync-gitea-policies.sh`: passed.
- `git diff --check`: passed before the digest update.
- `bats kubernetes/kind/tests/preload-images.bats`: passed all 8 tests.
- `bats kubernetes/kind/tests/sync-gitea-policies.bats`: passed all 45 tests.
- Follow-up `make -C kubernetes/kind 900 apply AUTO_APPROVE=1`: exited 0.
  - OpenTofu applied with `4 added, 1 changed, 4 destroyed`.
  - Health checks completed.
  - All 21 Grafana launchpad tiles selected by the gate had healthy expressions and reachable URLs.
  - Docker-mode SSO E2E passed 22 browser tests and skipped 1 compose-only test.
- Posted fresh OTLP trace and metric batches with natural `unit: "ms"` histograms; collector returned `200` for both `/v1/traces` and `/v1/metrics`.
- `bats tests/grafana-dashboard-quality.bats`: passed all 4 tests against the live cluster after the fresh OTLP data.
- `make test-ci`: passed all 318 tests.
- `bats kubernetes/kind/tests/check-memory-preflight.bats`: passed all 12 tests after hardening the shard-sensitive timeout fixture.
- Final rerun of `make -C kubernetes/kind test`: passed.
  - stage monotonicity: passed
  - Bash 3.2 compatibility: passed across 198 scripts
  - shell audit: passed across 117 scripts and 96 executable entrypoints
  - Kind Bats shards: 407 passed, 0 failed
  - OpenTofu validation: passed
  - OpenTofu tests: 72 passed, 0 failed

## Observability Data Proof

- Metrics:
  - `sum(up)` from in-cluster Prometheus returned `34`.
  - Request-related metric families were present, including `http_request_duration_seconds_count`, `argocd_app_k8s_request_total`, `hubble_http_requests_total`, `apiserver_request_total`, and `prometheus_http_requests_total`.
- Logs:
  - VictoriaLogs returned live records through `/select/logsql/query?query=*&limit=5`.
  - Sample records included `backstage`, `oauth2-proxy-sentiment-uat`, `chatgpt-sim`, and `subnetcalc-apim-simulator` streams with Kubernetes metadata and 2026-07-09 timestamps.
- Traces:
  - The APIM simulator management API returned `trace_count=100` after the final browser/API traffic.
  - Route/status breakdown:
    - `platform-mcp`: 3 traces, status `200`
    - `platform-mcp-oauth-metadata`: 11 traces, status `200`
    - `sentiment-api-dev`: 22 traces, status `200`
    - `sentiment-api-uat`: 22 traces, status `200`
    - `subnetcalc-api-dev`: 22 traces, status `200`
    - `subnetcalc-api-uat`: 20 traces, status `200`
  - Latest sample records included `subnetcalc-api-dev GET /api/v1/health`, `platform-mcp POST /mcp`, and `platform-mcp-oauth-metadata GET /.well-known/oauth-protected-resource/mcp`.
  - OTel spanmetric counters were empty in Prometheus during this earlier run; the final pass below fixed the MCP endpoint and Grafana query alignment, then proved the OTLP collector-to-Prometheus path explicitly.

## Final Verification Summary

- Final `make -C kubernetes/kind 900 apply AUTO_APPROVE=1` after the MCP and Grafana fixes exited 0.
  - OpenTofu applied GitOps updates with `4 added, 1 changed, 4 destroyed`.
  - Health passed with the kind cluster at stage 900.
  - All expected Argo CD Applications were present; child apps were Synced/Healthy, with only `app-of-apps` tolerated as Healthy/OutOfSync.
  - The launchpad gate evaluated 21 selected Grafana tiles; every tile expression was healthy and every target URL was reachable.
  - Gateway and TLS checks passed for the expected local HTTPS endpoints.
  - Docker-mode SSO E2E passed 22 browser tests and skipped the 1 compose-only test. Covered pages included Grafana admin, Grafana launchpad, namespace health dashboard, MCP observability dashboard, and Backstage observability dashboard.

- Final live configuration checks:
  - MCP deployment now has `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability.svc.cluster.local:4318`.
  - Live Grafana `platform-overview` dashboard now uses `traces_span_metrics_calls_total`, `traces_span_metrics_duration_milliseconds_bucket`, `sentiment_comments_created_total`, and `llm_inference_latency_ms_bucket`.
  - Docker has `mcr.microsoft.com/playwright:v1.58.2-noble` cached at `sha256:68f1c3dca663d0e8331e8af4681b0b315eca7de1bd7fa934aac0accbeb9f8323`.

- Final traces/metrics proof:
  - Sent a bounded synthetic OTLP probe to the live collector on `127.0.0.1:4318`.
  - The collector accepted `/v1/traces` and `/v1/metrics` with HTTP 200.
  - Prometheus returned data for the exact Grafana app overview queries:
    - request rate: 4 series
    - error rate: 4 series
    - latency p95: 4 series
    - sentiment comments: 2 series
    - LLM inference p95: 2 series
    - collector scrape availability: 1 series
  - This proves the collector-to-Prometheus-to-Grafana data path. It is a pipeline proof using synthetic OTLP app signals; native sentiment/subnetcalc app instrumentation for those exact OTel metrics is still a separate product gap.

- Final log proof:
  - `PLATFORM_LIVE_CHECKS=1 bats tests/observability-log-quality.bats`: 3 passed.
  - A direct VictoriaLogs positive query for `*` returned 5 rows.
  - Sample returned live MCP request logs with Kubernetes metadata and 2026-07-09 timestamps.

- Final dashboard tests:
  - `bats tests/grafana-dashboard-quality.bats`: 4 passed.
  - This covered static dashboard contracts plus live Prometheus queries for namespace health and app overview panels.

- Final version checks:
  - `make check-version`: passed.
  - `make -C kubernetes/kind check-version`: passed.
  - Kind audit note: the Argo CD chart still reports deployed chart appVersion `v3.4.3` versus code tag `v3.4.4`, but the audit confirms the configured image override is active at `dhi.io/argocd:3.4.4-debian13`.

- Final test suites:
  - `make test-ci`: 318 passed.
  - `make -C kubernetes/kind test`: passed.
    - stage monotonicity: passed
    - Bash 3.2 compatibility: 198 scripts scanned, passed
    - shell audit: 117 scripts scanned, passed
    - Kind Bats shards: 406 passed, 0 failed
    - OpenTofu validation: passed
    - OpenTofu tests: 72 passed, 0 failed
