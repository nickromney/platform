#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/memory-report.sh"
}

@test "kind memory-report make target delegates to the read-only script mode" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" memory-report

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/memory-report.sh" --execute'* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/kind" memory-report DRY_RUN=1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'memory-report.sh" --dry-run'* ]]
}

@test "memory-report summarizes docker and kubectl metrics without mutating state" {
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  log_file="${BATS_TEST_TMPDIR}/calls.log"
  mkdir -p "${bin_dir}"

  cat >"${bin_dir}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker:%s\n' "$*" >>"${MEMORY_REPORT_LOG}"
case "$1" in
  info)
    if [[ "${2:-}" == "--format" && "${3:-}" == "{{.MemTotal}}" ]]; then
      printf '17179869184\n'
    elif [[ "${2:-}" == "--format" && "${3:-}" == "{{.OperatingSystem}}" ]]; then
      printf 'Docker Desktop\n'
    fi
    ;;
  ps)
    printf 'kind-local-control-plane\nkind-local-worker\n'
    ;;
  stats)
    printf 'NAME\tMEM USAGE / LIMIT\tMEM %%\tCPU %%\n'
    printf 'kind-local-control-plane\t1.25GiB / 16GiB\t7.81%%\t12.00%%\n'
    printf 'kind-local-worker\t2.00GiB / 16GiB\t12.50%%\t18.00%%\n'
    ;;
  *)
    printf 'unexpected docker command: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${bin_dir}/docker"

  cat >"${bin_dir}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'kubectl:%s KUBECONFIG=%s\n' "$*" "${KUBECONFIG:-}" >>"${MEMORY_REPORT_LOG}"
printf 'NAMESPACE\tNAME\tCPU(cores)\tMEMORY(bytes)\n'
printf 'dev\tsentiment-api-abc\t20m\t820Mi\n'
EOF
  chmod +x "${bin_dir}/kubectl"

  run env \
    PATH="${bin_dir}:/usr/bin:/bin" \
    MEMORY_REPORT_LOG="${log_file}" \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/kind.yaml" \
    KUBECONFIG_CONTEXT="kind-kind-local" \
    /bin/bash "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Local platform memory report"* ]]
  [[ "${output}" == *"Memory budget: 16.00GiB (17179869184 bytes)"* ]]
  [[ "${output}" == *"kind-local-control-plane"* ]]
  [[ "${output}" == *"dev"*"sentiment-api-abc"*"820Mi"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"docker:info"* ]]
  [[ "${output}" == *"docker:stats --no-stream --format table {{.Name}}"* ]]
  [[ "${output}" == *"kubectl:--context kind-kind-local top pods -A KUBECONFIG=${BATS_TEST_TMPDIR}/kind.yaml"* ]]
}

@test "memory-report degrades gracefully when kubectl top is unavailable" {
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${bin_dir}"

  cat >"${bin_dir}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  info)
    if [[ "${2:-}" == "--format" && "${3:-}" == "{{.MemTotal}}" ]]; then
      printf '8589934592\n'
    fi
    ;;
  ps)
    ;;
  *)
    ;;
esac
EOF
  chmod +x "${bin_dir}/docker"

  cat >"${bin_dir}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'error: Metrics API not available\n' >&2
exit 1
EOF
  chmod +x "${bin_dir}/kubectl"

  run env PATH="${bin_dir}:/usr/bin:/bin" /bin/bash "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Memory budget: 8.00GiB (8589934592 bytes)"* ]]
  [[ "${output}" == *"No running kind-local node containers found."* ]]
  [[ "${output}" == *"WARN kubectl top pods -A unavailable; metrics-server may not be ready"* ]]
}
