# Profile-aware provisioning and the conditional-config sweep: handoff

Date: 2026-09-06. Branch `chore/20260905-astra-review`, 25 commits, none pushed,
no PR opened. Written so this work can be picked up without the session history.

## Objective

This began as a review request: find efficiencies in provisioning speed, memory
on an 8GB M1 or 16GB M4, and readability. It became a debugging campaign once
the first real runs failed. The standing instruction by the end was concrete:
get stage `900` to `health passed` on the 8GB profile, the 16GB profile, and
Lima.

That objective is met. Everything below explains what was changed to get there
and what is still uncertain.

## The one pattern behind most of this

Nearly every bug found was the same shape: a toggle declared in
`terraform/kubernetes/variables.tf` that some consumer never receives, so the
consumer falls back to a default of `true` and behaves as if the feature is on.

`enable_subnetcalc_apim_gateway` alone was missing from four consumers, and the
symptoms never looked like a missing variable:

- a GitOps bootstrap deadlock
- crashlooping nginx routers in `dev` and `uat`
- malformed policy YAML from a rewrite that had never once executed
- Launchpad tiles asserting components the profile deliberately does not deploy

Two publication paths matter and are easy to forget. A toggle must reach both:

- `terraform/kubernetes/operator-facts.tf`, which the health check reads
- the `gitops_render_contract` map in `terraform/kubernetes/locals.tf`, near the
  `enable_apim_simulator` entry, which `sync-gitea-policies.sh` reads

The rendered results are useful for diagnosis and are machine-local:
`terraform/kubernetes/.run/<variant>/operator-facts.json` and
`.run/kind/gitops-render-contract.json`.

Effective-state locals in `locals.tf` (`enable_mcp_effective`,
`enable_apim_simulator_effective`, around lines 584 to 590) are the intended
source of truth. A consumer keying off a raw repository flag instead is the same
bug wearing a different hat, which is what `sso.tf` was doing for the MCP
console proxy.

## Verified state

All three from a clean reset, on a Mac with a 9.36 GB Docker VM:

| Target | Stage 900 | Health | Peak container memory |
| --- | --- | --- | --- |
| `local-8gb` | 632s | passed | 6.25 GiB |
| `local-idp-16gb` | 643s | passed | 6.45 GiB |
| Lima | 513s | passed | not sampled |

`make lint` and `make test-ci` both pass at HEAD (`c754a321`).

The 8GB trim was confirmed on a live cluster, not only in render tests: `dev`
held the three sentiment workloads, and no `apim`, `mcp` or `agentgateway`
namespace existed.

## Work completed

Read `git log --oneline main..HEAD` for the list. The commit messages carry the
reasoning and are the best per-change reference. Grouped by theme:

**Profiles and image selection.** `kubernetes/workflow/image-selection-lib.sh`
is new: it resolves the effective toggles once from the apply workflow's tfvars
so builds follow the selected profile. `image-build-lib.sh` gained an input
fingerprint, so an unrelated commit reuses an image rather than rebuilding it.
`local-8gb` now deploys one sample app and no gateway demos; `local-idp-16gb`
got its visibility stack back.

**The Gitea bootstrap deadlock.** `kubernetes_network_policy_v1.gitea_argocd_bootstrap`
in `terraform/kubernetes/namespaces.tf`. Read the comment above it before
touching it: the rule names no source deliberately, and it carries egress for
kube-dns and Postgres. Both details are the result of getting it wrong twice.

**Lima's Cilium cutover.** Three separate fixes, each hidden behind the last.
`kubernetes/lima/README.md` "Operational truths" has the durable version.

**Grafana.** A 75m CPU ceiling was throttling startup past the liveness probe.
Raising it nearly halved 16GB stage 900, from 1204s to 643s.

**The workload bundle split.** `apps/workloads/base/all.yaml` became
`sentiment.yaml` and `subnetcalc.yaml`, each pruned on its own repository flag,
with the `uat` security-context patches split the same way.

## Decisions and constraints worth knowing

- **Resource profiles layer over every stage, not just 900.** A profile that
  affirms `enable_x = true` forces it on at stage 100, where its dependencies do
  not exist. `local-8gb` must therefore only ever reduce, which a test in
  `tests/platform-workflow.bats` asserts. `local-idp-16gb` is exempt in practice
  because it is a stage-900 selection, which is also why applying it at stage
  100 fails.
- **Grafana is not separable from Prometheus.** `enable_grafana` requires
  `enable_prometheus` through a check block in `variables.tf`. An early attempt
  to keep dashboards without metrics was invalid.
- **`--preset image-distribution=local-cache` is effectively mandatory** for a
  timely run, and belongs on stage 100 as well as 900, because the containerd
  mirror is written when the cluster is created. Measured: 632s and healthy with
  it, 2331s and failed without. Nothing in the code enforces this.
- **Two definitions exist for each observability app**, selected by
  `enable_app_of_apps`, and they had drifted.
  `tests/observability-config-drift.bats` now holds the Prometheus server sizing
  and retention equal across both.

## Failed approaches, so they are not retried

- **Trimming `local-8gb` before the bundle split crashlooped the routers.** The
  apps shared one manifest and the router referenced the APIM service by name.
  The split was the prerequisite, and it is now done.
- **An argocd-only ingress rule for Gitea sealed it off.** A NetworkPolicy that
  selects a pod turns on ingress isolation for it, so that rule became Gitea's
  entire policy whenever Kyverno's default-deny was absent, cutting off the
  NodePort Terraform uses to create the org. The apply then sat on an
  unreachable API for 1h48m.
- **Ingress alone was not enough either.** Gitea needs egress to answer an SSH
  key lookup; without it, a correct deploy key reports `permission denied`.
- **Regenerating the policy-render golden trees outside the bats harness does
  not work.** It pulls real charts and the trees diverge everywhere. Update the
  expected trees under `kubernetes/kind/tests/fixtures/policy-render/`
  surgically instead.

## Open and uncertain

- **The locale test flake is not fixed.** `source fingerprinting is stable
  across locales` in `tests/locale-independence.bats` failed three times under
  the full parallel gate and never in isolation. The shared-PID cache theory was
  checked and disproved: parallel bats tests get distinct PIDs. A diagnostic now
  prints the helper's output on failure, but three gate runs since have been
  clean, so the cause is still unknown. Those clean runs are not evidence of a
  fix.
- **Nothing guards the cache-preset omission** that produced the misleading
  2331s run. It is documented in the kind README only.
- **`docker system df` takes 47s on this machine.** That is what surfaced the
  `docker_read` defect in `kubernetes/kind/scripts/docker-safe-clean.sh`. The
  slowness itself was not investigated.
- **The branch is local only.** Not pushed, no PR.

## Machine-local state

These paths are specific to the machine the session ran on and are ephemeral.

- Run logs, timings and memory samples from every attempt live under the session
  scratchpad at
  `/private/tmp/claude-501/-Users-nickromney-Developer-personal-platform/`.
  The runs that passed are `8gb-cache`, `16gb-split2` and `lima-v5`.
- A kind cluster from the last 8GB run may still be up, along with the
  `platform-local-image-cache` registry container, which holds 64 repositories
  and was never reset at any point.
- The Lima VM `k3s-node-1` was stopped at the end of the Lima work.
- Two stray containers from an old bats run, `exciting_morse` and
  `hopeful_diffie`, were stopped early in the session and never removed. A test
  leaked them; that was not chased down.

## Reading order

1. `git log --oneline main..HEAD`, then individual commit messages.
2. `kubernetes/kind/README.md`: the "8GB Local Profile" and "16GB Local IDP
   Profile" sections, and the stage 500 Gitea note.
3. `kubernetes/lima/README.md`: "Operational truths" for the Cilium substrate.
4. `docs/STATUS.md`: the newest entry under "Done".

## Plausible next steps

The branch is complete and green as it stands, so the natural continuation is to
push it and open a PR, noting the locale flake as a known pre-existing issue
rather than something this branch introduced.

If the flake should be settled first instead, it needs to be caught with the new
diagnostic in place, which means running the full gate repeatedly under load
rather than running the file alone.
