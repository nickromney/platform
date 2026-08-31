# ADR 0013: Resource profiles reduce only, and every toggle carries a consumer tail

- Status: Accepted
- Recorded: 2026-08-31

## Context

`kubernetes/workflow/options.json` carries `resource_profile` presets whose
`overlay` is layered over the stage tfvars. Adding `local-8gb` for constrained
Docker Desktop hosts exposed two distinct traps.

**Affirmations break stage invariants.** A profile is layered over *every*
stage, not just 900. The first `local-8gb` draft asserted
`enable_victoria_logs = true` and `enable_otel_gateway = true` to signal "keep
the logging path". That forced both on at stage 100, where `enable_argocd` is
still false, and tripped the `enable_victoria_logs_requires_argocd` and
`enable_otel_gateway_requires_enable_argocd` check blocks on a real apply. Both
were redundant anyway: stage 900 already enables victoria-logs, and
`enable_otel_gateway_effective` in `locals.tf` ORs otel with the effective
prometheus, grafana and victoria-logs values.

**Reductions have dependencies too.** Turning prometheus off while stage 900
still enabled alertmanager tripped `enable_alertmanager_requires_prometheus`.

**And a toggle is never consumed in one place.** `enable_uat_apps`, added to
drop the uat workload sync while keeping the uat workspace, needed teaching to
seven consumers, found one failed apply at a time:

1. the prune step in `sync-gitea-policies.sh`
2. the expected-apps list in `check-cluster-health.sh`
3. a second, hardcoded `for app in dev uat` loop further down the same file
4. the Terraform-emitted operator facts contract (`operator-facts.tf`), which
   takes priority over tfvars -- a key missing there makes the resolver fall
   back to the `variables.tf` default, which was `true`
5. `PLATFORM_TFVARS` never reaching the post-OIDC health check at all: the
   script already read it, but Terraform had no `platform_tfvars_file` variable
   to supply, so *every* profile toggle was invisible there
6. the SSO E2E target list
7. the E2E runner's env derivation in `tests/kubernetes/sso/run.sh`

## Decision

A resource profile **may only reduce**. Turning something off is safe at any
stage; turning something on is not. Capabilities a profile keeps must come from
the stage tfvars or from an effective-value OR, never from the overlay.

When a reduction removes something another enabled component depends on, the
overlay must disable the dependent too.

A new feature toggle is not done when the Terraform path honours it. It is done
when the GitOps render, the operator facts contract, both health-check surfaces
and the E2E target list honour it.

## Consequences

- `tests/platform-workflow.bats` asserts `local-8gb` contains no `enable_*: true`.
- The dependency `check` blocks in `variables.tf` are the real safety net for
  reductions, so a new profile should be exercised with `100 plan` **and**
  `900 plan`, not just at the stage it targets.
- `var.platform_tfvars_file` now carries the profile path into local-exec
  health checks, which fixes this class of blindness for every future toggle.

## Evidence

`make -C kubernetes/kind 100 plan` reported 2 check-block assertion failures
before the affirmations were removed and 0 after. The uat health failure
reproduced on every apply until all four non-E2E consumers were fixed; the E2E
consumers then failed separately. `local-8gb` measured 7624 Mi -> 4936 Mi of
requests and 90 -> 66 pods on a cluster whose browser E2E passes.
