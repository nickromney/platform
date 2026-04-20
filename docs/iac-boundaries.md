# IaC Boundaries

This ledger records the ownership seam for the local Kubernetes stacks in this
repo. The goal is not to purge shell from the workflow; it is to keep host
bootstrap, cluster state, and operator validation in the layer where they stay
visible and explainable.

## Ownership Rules

Terragrunt owns invocation and configuration layering, not host lifecycle.

Terraform owns durable cluster state and the narrow bootstrap edges that need
to participate in the dependency graph once a target cluster already exists.

Make and shell keep host/runtime/bootstrap and validation concerns.

In practice, that means:

- Terragrunt assembles stack inputs, stage layering, state paths, and the
  shared Terraform entrypoint.
- Terraform manages the Kubernetes and Helm resources that define the platform
  shape inside an existing cluster.
- Make and shell keep the host-specific work inspectable: VM or daemon startup,
  kubeconfig repair or merge, image build and cache sync, localhost forwards or
  proxies, and `check-*` or browser verification steps.

## Explicit Keep-Out Zones

Lima and Slicer stage `100` bootstrap stays outside Terraform and Terragrunt.

That stage is where the host creates or starts the VM, installs k3s with host
tools, writes the split kubeconfig, and enforces runtime-specific preflight
rules. Those are environment-sensitive lifecycle operations, not durable
cluster objects.

Image cache/build/forward/check flows stay in Make/shell, not Terragrunt hooks.

Those flows depend on the host runtime and operator entrypoint surface:
registry/cache management, local image builds, proxy or forward setup, and
post-apply checks all need to stay explicit instead of being hidden behind HCL
hooks.

## Terraform Imperative Surface

The labels below are the working shorthand for the current imperative tail:

- `terraform-bootstrap`: imperative glue that still needs to participate in the
  Terraform dependency graph during cluster convergence
- `operator-bootstrap`: imperative work that is currently invoked from
  Terraform but is better understood as host or runtime bootstrap behavior
- `candidate-provider-native`: imperative work that probably deserves a future
  provider-native replacement if the replacement is simpler and quieter
- `validation-only`: waits or assertions that prove readiness but do not define
  durable cluster state

| Terraform step | Label | Why it lives there today |
| --- | --- | --- |
| `ensure_kind_kubeconfig` | `terraform-bootstrap` | Rewrites or refreshes the repo-managed split kubeconfig after cluster identity exists so later Terraform-managed resources can target the right cluster context. |
| `preload_images` | `operator-bootstrap` | Preloads node images before later resources reconcile; useful bootstrap glue, but it is a runtime preparation step rather than durable cluster state. |
| `kind_restart_containerd_on_registry_config_change` | `operator-bootstrap` | Restarts kind node containerd when registry wiring changes; this is runtime maintenance, not declarative platform state. |
| `kind_storage` | `candidate-provider-native` | Applies the local-path and default storage manifests after kind plus Cilium are up; it affects durable cluster behavior, but it is still a plausible provider-native cleanup candidate. |
| `hubble_ui_service_legacy_cleanup` | `candidate-provider-native` | Cleans up a legacy service shape in-cluster; it is a narrow compatibility patch that would be better expressed without a shell step if a simpler provider-native form exists. |
| `hubble_ui_backend_relay_port_patch` | `candidate-provider-native` | Applies a post-render Hubble UI compatibility patch tied to rendered chart values; it is durable in-cluster state but expressed imperatively today. |
| `cilium_restart_on_config_change` | `candidate-provider-native` | Forces Cilium agents to pick up rendered config changes; the need is real, but the restart edge is still a good candidate for a quieter provider-native expression. |
| `bootstrap_mkcert_ca` | `operator-bootstrap` | Copies the host mkcert CA into the cluster trust path; it depends on host CA state and stays closer to operator bootstrap than durable Terraform state. |
| `wait_for_gateway_bootstrap_crds` | `validation-only` | Waits for Gateway API CRDs to exist before later resources target them; it is ordering and readiness, not durable state. |
| `gitea_unset_must_change_password` | `terraform-bootstrap` | Normalizes first-login Gitea state so later repo automation can proceed deterministically. |
| `gitea_promote_admin` | `terraform-bootstrap` | Promotes declared Gitea users into the expected admin role so bootstrap automation can rely on them. |
| `gitea_org` | `terraform-bootstrap` | Ensures the expected Gitea org exists before repo sync and GitOps bootstrap continue. |
| `sync_gitea_policies_repo` | `terraform-bootstrap` | Seeds the GitOps policies repo that Argo depends on for initial reconciliation. |
| `sync_gitea_app_repo_sentiment` | `terraform-bootstrap` | Pushes the sentiment workload repo into Gitea so cluster-side automation has a source of truth to reconcile from. |
| `sync_gitea_app_repo_subnetcalc` | `terraform-bootstrap` | Pushes the subnet calculator workload repo into Gitea so cluster-side automation has a source of truth to reconcile from. |
| `wait_subnetcalc_images` | `validation-only` | Waits for workload image publication to finish; it is a readiness gate, not durable state. |
| `wait_sentiment_images` | `validation-only` | Waits for workload image publication to finish; it is a readiness gate, not durable state. |
| `argocd_repo_server_restart` | `validation-only` | Forces the repo-server to pick up known-hosts or repo-trust changes; useful in bootstrap, but still a restart side effect rather than durable desired state. |
| `argocd_refresh_gitops_repo_apps` | `validation-only` | Forces an Argo refresh after GitOps repo content changes; it improves convergence visibility but does not itself define durable state. |
| `wait_gitea_actions_runner_ready` | `validation-only` | Waits for the runner namespace, deployment, and rollout so later repo pushes do not race the cluster, but it is still a readiness assertion rather than durable desired state. |
| `wait_headlamp_deployment` | `validation-only` | Waits for Headlamp readiness so later host alias and SSO assumptions are safe to check. |
| `configure_kind_apiserver_oidc` | `terraform-bootstrap` | Applies the kind API server OIDC wiring that later SSO resources assume; this is a bounded bootstrap escape hatch that still belongs in the graph today. |
| `recover_kind_cluster_after_oidc_restart` | `terraform-bootstrap` | Repairs cluster availability after the kind API server OIDC restart path; it remains part of the required bootstrap sequence. |
| `check_kind_cluster_health_after_oidc` | `validation-only` | Verifies the cluster is healthy after the OIDC recovery path; it is a health assertion rather than durable state. |

## Main Shell Entrypoints

This is not every helper script in the repo. It is the set of shell entrypoints
that most clearly define the ownership seam for the local Kubernetes stacks.

| Shell entrypoint | Label | Why it belongs there |
| --- | --- | --- |
| `kubernetes/kind/scripts/ensure-kind-kubeconfig.sh` | `terraform-bootstrap` | Keeps the split kubeconfig aligned with the active kind cluster so provider-backed resources can target the right context. |
| `kubernetes/kind/scripts/check-kind-host-ports.sh` | `operator-bootstrap` | Performs host preflight on bound localhost ports before kind lifecycle work starts. |
| `kubernetes/lima/scripts/bootstrap-k3s-lima.sh` | `operator-bootstrap` | Starts the Lima VM path and bootstraps k3s before Terraform is allowed to manage in-cluster state. |
| `kubernetes/slicer/scripts/bootstrap-k3s-slicer.sh` | `operator-bootstrap` | Starts the Slicer VM path and bootstraps k3s before Terraform is allowed to manage in-cluster state. |
| `kubernetes/slicer/scripts/ensure-host-forwards.sh` | `operator-bootstrap` | Manages host forwards and proxy setup for the VM-backed path; this is runtime plumbing, not Terraform state. |
| `terraform/kubernetes/scripts/preload-images.sh` | `operator-bootstrap` | Prepares node image content ahead of reconciliation and depends on the host runtime rather than a durable cluster object. |
| `terraform/kubernetes/scripts/bootstrap-mkcert-ca.sh` | `operator-bootstrap` | Bridges the host mkcert trust anchor into the cluster, which is an operator environment concern. |
| `terraform/kubernetes/scripts/sync-gitea-policies.sh` | `terraform-bootstrap` | Seeds the GitOps repo content that Argo needs for first convergence. |
| `terraform/kubernetes/scripts/sync-gitea-repo.sh` | `terraform-bootstrap` | Seeds app repos into Gitea so in-cluster automation can build and reconcile them. |
| `terraform/kubernetes/scripts/configure-kind-apiserver-oidc.sh` | `terraform-bootstrap` | Applies the kind API server OIDC bootstrap edge that later SSO state depends on. |
| `terraform/kubernetes/scripts/recover-kind-cluster-after-apiserver-restart.sh` | `terraform-bootstrap` | Repairs the kind cluster after the controlled API server restart required by OIDC wiring. |
| `terraform/kubernetes/scripts/check-cluster-health.sh` | `validation-only` | Verifies cluster health from the outside; it should stay an explicit readiness or smoke check. |
| `terraform/kubernetes/scripts/check-gateway-urls.sh` | `validation-only` | Confirms the HTTPS and ingress entrypoints actually answer after apply. |
| `terraform/kubernetes/scripts/check-sso.sh` | `validation-only` | Confirms the SSO surface behaves as expected after the cluster reaches the target stage. |

## Runtime Evidence

Observed proof matters more than taste arguments.

- 2026-04-19: `make -C kubernetes/kind test-idempotence STAGE=900` passed on the live kind stack after a fresh `reset -> 100 apply -> 900 apply` run.
- The recorded harness result was `second_apply=noop` and `final_plan=noop`.
- The captured artifact lives under `.run/idempotence/kind/stage900/20260419-183508Z`.
- This is enough evidence to preserve the current kind `900` shell/Terraform seam for now and avoid a speculative refactor of the validated bootstrap path.
- 2026-04-19: `make -C kubernetes/lima 900 apply AUTO_APPROVE=1` passed on a fresh runtime rebuild, but `make -C kubernetes/lima test-idempotence STAGE=900` failed on the second apply inside `check-sso-e2e`, after which the host-side kubeconfig path timed out even though in-VM `k3s kubectl` still worked.
- That failure was narrow and pointed at validation ownership, not Terraform drift: removing `check-sso-e2e` from the Lima `900 apply` path restored the expected rerun behavior.
- 2026-04-19: `make -C kubernetes/lima test-idempotence STAGE=900` then passed on the rebuilt Lima stack.
- The recorded Lima harness result is now `second_apply=noop` and `final_plan=noop`.
- The captured artifact lives under `.run/idempotence/lima/stage900/20260419-194930Z`.
- 2026-04-19: `make -C kubernetes/slicer test-idempotence STAGE=900` passed on the live Slicer stack after a fresh `reset -> 100 apply -> 900 apply` run.
- The recorded Slicer harness result was `second_apply=noop` and `final_plan=noop`.
- The captured artifact lives under `.run/idempotence/slicer/stage900/20260419-192659Z`.
- Current conclusion: browser E2E validation is a validation-only concern and should not sit inside the Lima `900 apply` convergence path.

## Review Heuristic

When deciding where new logic belongs, use this rule of thumb:

- If it creates or reconciles durable in-cluster objects, it may belong in
  Terraform.
- If it starts host runtimes, bootstraps VMs, repairs kubeconfig, builds or
  syncs images, sets up forwards, or validates readiness from the outside, it
  belongs in Make or shell.
- If Terragrunt is only being considered as a place to hide host behavior, keep
  that behavior out of Terragrunt and leave it explicit in the operator layer.
