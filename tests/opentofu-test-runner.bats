#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/run-opentofu-tests.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

@test "OpenTofu timeout kills a TERM-resistant child and its grandchild" {
  local module_dir="${BATS_TEST_TMPDIR}/module"
  mkdir -p "${module_dir}"
  cat >"${TEST_BIN}/tofu" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *' init '*) exit 0 ;;
  *' test '*)
    perl -e '
      $SIG{TERM} = "IGNORE";
      my $child = fork(); defined($child) or die "fork: $!";
      if ($child == 0) { open(my $r, ">", $ENV{GRANDCHILD_READY}) or die $!; close($r); sleep 6; open(my $f, ">", $ENV{GRANDCHILD_MARKER}) or die $!; print $f "alive"; exit 0; }
      open(my $r, ">", $ENV{CHILD_READY}) or die $!; close($r);
      sleep 6; open(my $f, ">", $ENV{CHILD_MARKER}) or die $!; print $f "alive"; waitpid($child, 0);
    ' &
    printf '%s\n' "$!" > "$CHILD_PID_FILE"
    wait
    ;;
  *) exit 1 ;;
esac
EOF
  printf '#!/bin/sh\nexit 0\n' >"${TEST_BIN}/pgrep"
  chmod +x "${TEST_BIN}/tofu" "${TEST_BIN}/pgrep"
  export CHILD_MARKER="${BATS_TEST_TMPDIR}/child-alive" GRANDCHILD_MARKER="${BATS_TEST_TMPDIR}/grandchild-alive"
  export CHILD_READY="${BATS_TEST_TMPDIR}/child-ready" GRANDCHILD_READY="${BATS_TEST_TMPDIR}/grandchild-ready"
  export CHILD_PID_FILE="${BATS_TEST_TMPDIR}/child-pid"
  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute \
    --module-dir "${module_dir}" --timeout-seconds 2 --extra-validation off
  [ "${status}" -eq 124 ] || { echo "${output}"; return 1; }
  [ -s "${CHILD_PID_FILE}" ]
  [ -f "${CHILD_READY}" ]
  [ -f "${GRANDCHILD_READY}" ]
  sleep 4
  local leaked=0
  if [ -e "${CHILD_MARKER}" ]; then echo 'TERM-resistant child survived timeout'; leaked=1; fi
  if [ -e "${GRANDCHILD_MARKER}" ]; then echo 'grandchild survived timeout'; leaked=1; fi
  [ "${leaked}" -eq 0 ]
}

@test "OpenTofu runner interruption cleans its owned process group" {
  mkdir -p "${BATS_TEST_TMPDIR}/module"
  cat >"${TEST_BIN}/tofu" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *' init '*) exit 0 ;;
  *' test '*)
    perl -e '$SIG{TERM} = "IGNORE"; open(my $r, ">", $ENV{READY}) or die $!; close($r); sleep 5; open(my $f, ">", $ENV{SURVIVED}) or die $!; print $f "alive"' &
    wait
    ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "${TEST_BIN}/tofu"
  local signal
  for signal in TERM INT; do
    run env PATH="${TEST_BIN}:/usr/bin:/bin" READY="${BATS_TEST_TMPDIR}/ready-${signal}" \
      SURVIVED="${BATS_TEST_TMPDIR}/survived-${signal}" SIGNAL="${signal}" \
      MODULE="${BATS_TEST_TMPDIR}/module" /bin/bash -c '
        perl -MPOSIX=setsid -e '\''setsid() or die $!; $SIG{INT} = "DEFAULT"; exec @ARGV or die $!'\'' \
          /bin/bash "$SCRIPT" --execute --module-dir "$MODULE" --timeout-seconds 30 --extra-validation off &
        runner=$!
        for ((i=0; i<200; i++)); do [ -f "$READY" ] && break; sleep 0.02; done
        [ -f "$READY" ] || { kill "$runner" 2>/dev/null || true; wait "$runner" 2>/dev/null || true; exit 1; }
        kill -s "$SIGNAL" "$runner"
        wait "$runner"; code=$?
        case "$SIGNAL:$code" in TERM:143|INT:130) ;; *) exit 1 ;; esac
        sleep 6
        [ ! -e "$SURVIVED" ]
      '
    [ "${status}" -eq 0 ] || { echo "${signal}: ${output}"; return 1; }
  done
}

@test "OpenTofu runner initializes module and runs optional filtered test with split kubeconfig defaults" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/tofu.log"
  kubeconfig="${BATS_TEST_TMPDIR}/kind-kind-local.yaml"

  cat >"${TEST_BIN}/tofu" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'args:%s\n' "\$*" >>"${log_file}"
printf 'env:KUBECONFIG=%s TF_VAR_kubeconfig_path=%s TF_VAR_kubeconfig_context=%s\n' "\${KUBECONFIG:-}" "\${TF_VAR_kubeconfig_path:-}" "\${TF_VAR_kubeconfig_context:-}" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/tofu"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    KUBECONFIG_PATH="${kubeconfig}" \
    KUBECONFIG_CONTEXT="kind-kind-local" \
    /bin/bash "${SCRIPT}" --execute \
      --module-dir "${module_dir}" \
      --filter "tests/gitops_features.tftest.hcl" \
      --timeout-seconds 9

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"args:-chdir=${module_dir} init -backend=false -input=false"* ]]
  [[ "${output}" == *"args:-chdir=${module_dir} test -filter=tests/gitops_features.tftest.hcl"* ]]
  [[ "${output}" == *"env:KUBECONFIG=${kubeconfig} TF_VAR_kubeconfig_path=${kubeconfig} TF_VAR_kubeconfig_context=kind-kind-local"* ]]
}

@test "OpenTofu runner can use Terraform-compatible CLI binary" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/terraform.log"

  cat >"${TEST_BIN}/terraform" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'terraform:%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/terraform"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute \
    --module-dir "${module_dir}" \
    --binary terraform \
    --timeout-seconds 9

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"terraform:-chdir=${module_dir} init -backend=false -input=false"* ]]
  [[ "${output}" == *"terraform:-chdir=${module_dir} test"* ]]
}

@test "OpenTofu runner adds Terraform 1.15 validation before tests" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/terraform-1-15.log"

  cat >"${TEST_BIN}/terraform" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == "version" ]]; then
  printf 'Terraform v1.15.0\n'
  exit 0
fi
printf 'terraform:%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/terraform"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute \
    --module-dir "${module_dir}" \
    --binary terraform \
    --timeout-seconds 9

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"terraform:-chdir=${module_dir} init -backend=false -input=false"* ]]
  [[ "${output}" == *"terraform:-chdir=${module_dir} validate"* ]]
  [[ "${output}" == *"terraform:-chdir=${module_dir} test"* ]]
}

@test "OpenTofu runner adds OpenTofu 1.12 validation before tests" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/opentofu-1-12.log"

  cat >"${TEST_BIN}/tofu" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == "version" ]]; then
  printf 'OpenTofu v1.12.0-rc1\n'
  exit 0
fi
printf 'tofu:%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/tofu"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute \
    --module-dir "${module_dir}" \
    --timeout-seconds 9

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"tofu:-chdir=${module_dir} init -backend=false -input=false"* ]]
  [[ "${output}" == *"tofu:-chdir=${module_dir} validate"* ]]
  [[ "${output}" == *"tofu:-chdir=${module_dir} test"* ]]
}

@test "OpenTofu runner can capture OpenTofu 1.12 JSON logs without losing human output" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  json_log_dir="${BATS_TEST_TMPDIR}/json-logs"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/opentofu-json.log"

  cat >"${TEST_BIN}/tofu" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == "version" ]]; then
  printf 'OpenTofu v1.12.0-rc1\n'
  exit 0
fi
printf 'tofu:%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/tofu"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute \
    --module-dir "${module_dir}" \
    --json-log-dir "${json_log_dir}" \
    --timeout-seconds 9

  [ "${status}" -eq 0 ]
  [ -d "${json_log_dir}" ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"tofu:-chdir=${module_dir} init -backend=false -input=false -json-into=${json_log_dir}/init.jsonl"* ]]
  [[ "${output}" == *"tofu:-chdir=${module_dir} validate -json-into=${json_log_dir}/validate.jsonl"* ]]
  [[ "${output}" == *"tofu:-chdir=${module_dir} test -json-into=${json_log_dir}/test.jsonl"* ]]
}

@test "OpenTofu runner does not pass OpenTofu JSON log flags to Terraform" {
  module_dir="${BATS_TEST_TMPDIR}/module"
  json_log_dir="${BATS_TEST_TMPDIR}/terraform-json-logs"
  mkdir -p "${module_dir}"
  log_file="${BATS_TEST_TMPDIR}/terraform-json.log"

  cat >"${TEST_BIN}/terraform" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == "version" ]]; then
  printf 'Terraform v1.15.0\n'
  exit 0
fi
printf 'terraform:%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/terraform"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute \
    --module-dir "${module_dir}" \
    --binary terraform \
    --json-log-dir "${json_log_dir}" \
    --timeout-seconds 9

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"terraform:-chdir=${module_dir} validate"* ]]
  [[ "${output}" != *"-json-into="* ]]
}
