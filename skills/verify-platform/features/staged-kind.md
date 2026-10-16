# Staged kind acceptance and reset isolation

Kind has a separate infrastructure lifecycle. A Compose success or local render must never stand in for a stage deployment or reset proof.

## Sub-features

- Resource and runtime conflict preflight before any expensive phase.
- Actual stage-900 deployment followed by live health, gateway and SSO acceptance.
- A separate reset proof retaining unrelated Docker container identities and start times.

## How to get to it (user POV)

The operator deploys the cumulative kind stage, uses its protected application routes and later resets the kind target while preserving unrelated workloads.

## Driving it with control.sh

Use the supported workflow preview rather than `make -n`, whose recursive recipes can mutate state:

```bash
scripts/platform-workflow.sh preview --execute --variant kind --stage 900 --action plan
scripts/platform-workflow.sh preview --execute --variant kind --stage 900 --action reset
kubernetes/kind/scripts/check-memory-preflight.sh --execute
```

The memory checker is read-only: its defaults require 8 GiB Docker memory, warn below 4 GiB available host memory, fail below 2 GiB, and flag competing VM RSS above 2 GiB. Those are prerequisites, not a hard bound on stage-900 consumption. A run restricted to 512 MiB cannot deploy this stack. Retain checker output and exit status, resource estimates and the decision before proceeding. Recheck before apply, image build/preload and reset/rebuild phases; a failing preflight stops progress.

A later authorized full run uses the established supported lifecycle:

```bash
make -C kubernetes/kind prereqs
make -C kubernetes/kind check-lima-stopped
skills/verify-platform/scripts/runtime-snapshot.sh --execute capture .run/kind-unrelated.before.txt
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind check-health
make -C kubernetes/kind check-gateway-urls
make -C kubernetes/kind check-sso-e2e
```

Capture each command, exit code and output under a unique evidence directory outside disposable state. Record the rendered feature settings and use the feature-matrix recipe before deployment. Only after the live checks pass may the run claim stage-900 acceptance. The apply runs against the shared `kind-local` target; do not adopt or reset another operator's instance.

For a distinct, authorized reset proof after capturing live acceptance:

```bash
make -C kubernetes/kind reset AUTO_APPROVE=1
skills/verify-platform/scripts/runtime-snapshot.sh --execute assert .run/kind-unrelated.before.txt
```

The baseline must be captured before the run creates its kind node, otherwise that owned node will be incorrectly classified as unrelated. Independently confirm the owned kind node ID is absent, preserve the unrelated-container assertion output, and keep evidence through cleanup. A failed reset or isolation check is a failed proof, even if some workloads disappeared.

## Gotchas

A workflow preview only proves command selection. A successful memory check only proves the current prerequisite thresholds. Neither executes reset, proves isolation, nor deploys stage 900. The bounded October 2026 remediation used disposable Docker workloads and offline source rendering; live kind deployment/reset remains pending. Do not reset existing clusters merely to make this recipe convenient.
