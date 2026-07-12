#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/snapshot-tfstate.sh"
}

snapshot_count() {
  find "$1" -type f -name 'terraform.tfstate.*.snapshot' -print 2>/dev/null | wc -l | tr -d ' '
}

@test "snapshot creates a timestamped sibling and prunes older snapshots to keep count" {
  state_dir="${BATS_TEST_TMPDIR}/state"
  snapshot_dir="${state_dir}/snapshots"
  state_file="${state_dir}/terraform.tfstate"
  mkdir -p "${snapshot_dir}"
  printf '{"version":4,"serial":99}\n' >"${state_file}"
  printf 'old-1\n' >"${snapshot_dir}/terraform.tfstate.20260101T000001Z.1.snapshot"
  printf 'old-2\n' >"${snapshot_dir}/terraform.tfstate.20260101T000002Z.2.snapshot"
  printf 'old-3\n' >"${snapshot_dir}/terraform.tfstate.20260101T000003Z.3.snapshot"

  run "${SCRIPT}" --execute --state-file "${state_file}" --keep 2

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   Terraform/OpenTofu state snapshot: ${snapshot_dir}/terraform.tfstate."* ]]
  [ "$(snapshot_count "${snapshot_dir}")" -eq 2 ]
  [ ! -e "${snapshot_dir}/terraform.tfstate.20260101T000001Z.1.snapshot" ]
  run grep -R '"serial":99' "${snapshot_dir}"
  [ "${status}" -eq 0 ]
}

@test "zero-byte live state warns and fails closed without changing state" {
  state_dir="${BATS_TEST_TMPDIR}/state"
  snapshot_dir="${state_dir}/snapshots"
  state_file="${state_dir}/terraform.tfstate"
  mkdir -p "${snapshot_dir}"
  : >"${state_file}"
  printf '{"version":4}\n' >"${snapshot_dir}/terraform.tfstate.20260101T000001Z.1.snapshot"

  run "${SCRIPT}" --execute --state-file "${state_file}" --restore-command "make -C kubernetes/kind state-restore AUTO_APPROVE=1"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"WARN live Terraform/OpenTofu state is zero bytes: ${state_file}"* ]]
  [[ "${output}" == *"WARN newest non-empty snapshot: ${snapshot_dir}/terraform.tfstate.20260101T000001Z.1.snapshot"* ]]
  [[ "${output}" == *"WARN restore explicitly with: make -C kubernetes/kind state-restore AUTO_APPROVE=1"* ]]
  [ ! -s "${state_file}" ]
}

@test "restore refuses when live state is non-empty" {
  state_dir="${BATS_TEST_TMPDIR}/state"
  snapshot_dir="${state_dir}/snapshots"
  state_file="${state_dir}/terraform.tfstate"
  mkdir -p "${snapshot_dir}"
  printf '{"version":4,"serial":1}\n' >"${state_file}"
  printf '{"version":4,"serial":2}\n' >"${snapshot_dir}/terraform.tfstate.20260101T000001Z.1.snapshot"

  run "${SCRIPT}" --restore --execute --state-file "${state_file}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL Refusing to restore because live Terraform/OpenTofu state is non-empty: ${state_file}"* ]]
  run grep -F '"serial":1' "${state_file}"
  [ "${status}" -eq 0 ]
}

@test "restore preview shows the newest snapshot without modifying zero-byte live state" {
  state_dir="${BATS_TEST_TMPDIR}/state"
  snapshot_dir="${state_dir}/snapshots"
  state_file="${state_dir}/terraform.tfstate"
  mkdir -p "${snapshot_dir}"
  : >"${state_file}"
  printf '{"version":4,"serial":3}\n' >"${snapshot_dir}/terraform.tfstate.20260101T000003Z.3.snapshot"

  run "${SCRIPT}" --restore --dry-run --state-file "${state_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Restore candidate:"* ]]
  [[ "${output}" == *"live:     ${state_file}"* ]]
  [[ "${output}" == *"snapshot: ${snapshot_dir}/terraform.tfstate.20260101T000003Z.3.snapshot"* ]]
  [ ! -s "${state_file}" ]
}

@test "restore executes from the newest non-empty snapshot when live state is zero bytes" {
  state_dir="${BATS_TEST_TMPDIR}/state"
  snapshot_dir="${state_dir}/snapshots"
  state_file="${state_dir}/terraform.tfstate"
  mkdir -p "${snapshot_dir}"
  : >"${state_file}"
  printf '{"version":4,"serial":1}\n' >"${snapshot_dir}/terraform.tfstate.20260101T000001Z.1.snapshot"
  printf '{"version":4,"serial":2}\n' >"${snapshot_dir}/terraform.tfstate.20260101T000002Z.2.snapshot"

  run "${SCRIPT}" --restore --execute --state-file "${state_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Restore candidate:"* ]]
  [[ "${output}" == *"snapshot: ${snapshot_dir}/terraform.tfstate.20260101T000002Z.2.snapshot"* ]]
  [[ "${output}" == *"OK   Restored Terraform/OpenTofu state from ${snapshot_dir}/terraform.tfstate.20260101T000002Z.2.snapshot"* ]]
  run grep -F '"serial":2' "${state_file}"
  [ "${status}" -eq 0 ]
}
