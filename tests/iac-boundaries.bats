#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export BOUNDARY_DOC="${REPO_ROOT}/docs/iac-boundaries.md"
}

@test "iac boundaries doc exists and records the ownership seam" {
  [ -f "${BOUNDARY_DOC}" ]

  run grep -Fn 'Terragrunt owns invocation and configuration layering, not host lifecycle.' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'Make and shell keep host/runtime/bootstrap and validation concerns.' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]
}

@test "iac boundaries doc records the accepted keep-out-of-terragrunt seams" {
  [ -f "${BOUNDARY_DOC}" ]

  run grep -Fn 'Lima and Slicer stage `100` bootstrap stays outside Terraform and Terragrunt.' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'Image cache/build/forward/check flows stay in Make/shell, not Terragrunt hooks.' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]
}

@test "iac boundaries doc classifies the current terraform imperative surface" {
  [ -f "${BOUNDARY_DOC}" ]

  run grep -Fn '| `ensure_kind_kubeconfig` | `terraform-bootstrap` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '| `kind_storage` | `candidate-provider-native` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '| `wait_gitea_actions_runner_ready` | `validation-only` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '| `configure_kind_apiserver_oidc` | `terraform-bootstrap` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '| `preload_images` | `operator-bootstrap` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '| `bootstrap_mkcert_ca` | `operator-bootstrap` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '| `argocd_repo_server_restart` | `validation-only` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '| `cilium_restart_on_config_change` | `candidate-provider-native` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]
}

@test "iac boundaries doc classifies the main shell entrypoints that define the seam" {
  [ -f "${BOUNDARY_DOC}" ]

  run grep -Fn '## Main Shell Entrypoints' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '| `kubernetes/lima/scripts/bootstrap-k3s-lima.sh` | `operator-bootstrap` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '| `kubernetes/slicer/scripts/bootstrap-k3s-slicer.sh` | `operator-bootstrap` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '| `terraform/kubernetes/scripts/check-cluster-health.sh` | `validation-only` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '| `terraform/kubernetes/scripts/sync-gitea-policies.sh` | `terraform-bootstrap` |' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]
}

@test "iac boundaries doc records the observed kind stage 900 runtime proof" {
  [ -f "${BOUNDARY_DOC}" ]

  run grep -Fn '## Runtime Evidence' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '2026-04-19: `make -C kubernetes/kind test-idempotence STAGE=900`' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '`second_apply=noop` and `final_plan=noop`' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]

  run grep -Fn '.run/idempotence/kind/stage900/20260419-183508Z' "${BOUNDARY_DOC}"

  [ "${status}" -eq 0 ]
}
