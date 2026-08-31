# ADR 0014: Browser E2E, not health checks, defines a working cluster

- Status: Accepted
- Recorded: 2026-08-31

## Context

`check-cluster-health.sh` reported `Health check completed` with zero issues on
a cluster that served no platform URL at all. It verifies Argo CD Applications
exist, Deployments are Ready, secrets and certificates are present and policies
validate. **It never fetches a URL through the gateway.**

The gap is not theoretical. A single-node trial passed the health check while
`subnetcalc.dev` returned HTTP 000, because Cilium was denying ingress at a
layer no health assertion inspects (see ADR 0012).

The browser suite has its own failure mode. Playwright stops at the first
failure, so one unreachable target hides every later test. A run reporting
"1 failed, 1 skipped" had in fact executed **one** test out of twenty; the other
eighteen never ran and were silently reported as `-`. Reading the summary line
alone gives the opposite impression to the truth.

Three groups of targets had no gate at all, so any profile that disabled the
corresponding capability failed the suite on a surface it deliberately never
deployed:

- uat targets, once `enable_uat_apps` existed
- `grafana-admin`, `grafana-launchpad` and `hubble-admin`, despite
  `enable_grafana` and `enable_hubble` being long-standing toggles
- the Grafana **dashboard** targets, pushed after the target filter runs and
  gated on `INCLUDE_MCP && INCLUDE_VICTORIA_LOGS` -- the data sources feeding the
  dashboards, never Grafana itself

## Decision

A cluster is "working" when `check-sso-e2e` passes, not when `check-health`
does. Health checks remain useful for diagnosing *why* something is broken; they
do not establish that anything serves.

Every E2E target must be gated on the toggle that decides whether its backend
exists, following the `SSO_E2E_ENABLE_*` pattern already in the suite: derived
in `run.sh` from `tfvar_bool`, passed into the container, defaulting to `true`
so the full stage-900 profile is unchanged.

When reading a Playwright result, count the outcomes. `-` means the test never
ran, and the failure count alone will understate the damage.

## Consequences

- Profile work is not finished at "the pods are Running". `local-8gb` needed
  three new E2E gates before it could be called good.
- `check-gateway-urls` is the cheap intermediate signal: it exercises all 57
  routes and TLS hostnames in seconds without a browser.
- The verification order that actually works is: apply exits 0 -> gateway URLs ->
  browser E2E. Anything earlier is necessary, not sufficient.

## Evidence

On `local-8gb` with stock topology: apply `exit=0`; `check-gateway-urls` 57 OK /
0 FAIL; `check-sso-e2e` **12 passed, 0 failed**, including `subnetcalc-dev: load
and login` and both cross-app sign-out tests that verify logging out of one app
clears the Keycloak session another relies on. Docker memory 6.28 GiB of an
8.72 GiB limit.

Before the gates: the same cluster reported a clean health check while the suite
was blocked at its first target.
