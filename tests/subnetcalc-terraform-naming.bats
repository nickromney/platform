#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "terraform and stage inputs use subnetcalc rather than legacy subnet calculator identifiers" {
  run rg -n \
    --glob '!tests/subnetcalc-terraform-naming.bats' \
    'enable_app_repo_subnet_calculator|subnet_calculator_source_dir|subnet_calculator_repo_name|subnet_calculator_content_hash|app_repo_subnet_calculator|sync_gitea_app_repo_subnet_calculator' \
    "${REPO_ROOT}/terraform" \
    "${REPO_ROOT}/kubernetes" \
    "${REPO_ROOT}/docs/iac-boundaries.md"

  [ "${status}" -eq 1 ]
}
