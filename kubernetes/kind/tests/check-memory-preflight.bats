#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/check-memory-preflight.sh"
}

fake_darwin_memory() {
  local available_pages="${1:-2411725}"

  cat >"${TEST_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' Darwin
EOF
  chmod +x "${TEST_BIN}/uname"

  cat >"${TEST_BIN}/sysctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${*}" == "-n hw.memsize" ]]; then
  printf '%s\n' 17179869184
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/sysctl"

  cat >"${TEST_BIN}/vm_stat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<VMSTAT
Mach Virtual Memory Statistics: (page size of 4096 bytes)
Pages free:                             AVAILABLE_PAGES.
Pages inactive:                         0.
Pages purgeable:                        0.
VMSTAT
EOF
  sed -i.bak "s/AVAILABLE_PAGES/${available_pages}/" "${TEST_BIN}/vm_stat"
  rm -f "${TEST_BIN}/vm_stat.bak"
  chmod +x "${TEST_BIN}/vm_stat"
}

fake_docker_mem() {
  local mem_bytes="$1"

  cat >"${TEST_BIN}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "info" && "\${2:-}" == "--format" ]]; then
  printf '%s\n' "${mem_bytes}"
  exit 0
fi
if [[ "\${1:-}" == "info" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker"
}

fake_ps_docker_vm() {
  cat >"${TEST_BIN}/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-axo" ]]; then
  cat <<'PS'
  101 1024
  202 3774873
PS
  exit 0
fi
if [[ "${1:-}" == "-p" && "${3:-}" == "-o" && "${4:-}" == "comm=" ]]; then
  case "${2:-}" in
    202) printf '%s\n' "/Library/Application Support/com.apple.Virtualization.VirtualMachine" ;;
    *) printf '%s\n' "/usr/bin/login" ;;
  esac
  exit 0
fi
if [[ "${1:-}" == "-p" && "${3:-}" == "-o" && "${4:-}" == "command=" ]]; then
  case "${2:-}" in
    202) printf '%s\n' "/Library/Application Support/com.apple.Virtualization.VirtualMachine" ;;
    *) printf '%s\n' "login" ;;
  esac
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/ps"
}

fake_ps_slicer_vm() {
  cat >"${TEST_BIN}/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-axo" ]]; then
  cat <<'PS'
  301 3145728
PS
  exit 0
fi
if [[ "${1:-}" == "-p" && "${3:-}" == "-o" && "${4:-}" == "comm=" ]]; then
  printf '%s\n' "/Library/Application Support/com.apple.Virtualization.VirtualMachine"
  exit 0
fi
if [[ "${1:-}" == "-p" && "${3:-}" == "-o" && "${4:-}" == "command=" ]]; then
  printf '%s\n' "/Library/Application Support/com.apple.Virtualization.VirtualMachine"
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/ps"
}

fake_lsof_docker_owner() {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != "-b -n -P -p 202" ]]; then
  printf 'unexpected lsof args: %s\n' "$*" >&2
  exit 2
fi
cat <<'LSOF'
COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
Virtual  202 nick  txt    REG    1,4        0    1 /Applications/Docker.app/Contents/MacOS/com.docker.backend
Virtual  202 nick   12u  unix    0x0        0    0 /Users/nick/Library/Containers/com.docker.docker/docker.sock
LSOF
EOF
  chmod +x "${TEST_BIN}/lsof"
}

fake_lsof_docker_owner_large_output() {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != "-b -n -P -p 202" ]]; then
  printf 'unexpected lsof args: %s\n' "$*" >&2
  exit 2
fi
# Docker marker on an early line, then >64KB of filler: under pipefail,
# `printf output | grep -q` false-negatives because grep exits at the first
# match and printf takes SIGPIPE on the unread remainder. The here-string
# classification must still identify Docker.
printf 'COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME\n'
printf 'Virtual  202 nick   12u  unix    0x0        0    0 /Users/nick/Library/Containers/com.docker.docker/docker.sock\n'
for i in $(seq 1 900); do
  printf 'Virtual  202 nick  %3su   REG    1,4        0    1 /System/Library/Frameworks/Virtualization.framework/Versions/A/Resources/filler-line-%s-padding-padding-padding\n' "$i" "$i"
done
EOF
  chmod +x "${TEST_BIN}/lsof"
}

fake_lsof_slicer_owner() {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != "-b -n -P -p 301" ]]; then
  printf 'unexpected lsof args: %s\n' "$*" >&2
  exit 2
fi
cat <<'LSOF'
COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
Virtual  301 nick  txt    REG    1,4        0    1 /Users/nick/slicer-mac/slicer-mac
Virtual  301 nick   12u  unix    0x0        0    0 /Users/nick/slicer-mac/slicer.sock
LSOF
EOF
  chmod +x "${TEST_BIN}/lsof"
}

fake_lsof_unavailable() {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "-b -n -P -p "*) ;;
  *)
    printf 'unexpected lsof args: %s\n' "$*" >&2
    exit 2
    ;;
esac
exit 127
EOF
  chmod +x "${TEST_BIN}/lsof"
}

fake_lsof_timeout_then_docker_owner() {
  local state_file="${BATS_TEST_TMPDIR}/lsof-attempts"

  cat >"${TEST_BIN}/lsof" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" != "-b -n -P -p 202" ]]; then
  printf 'unexpected lsof args: %s\n' "\$*" >&2
  exit 2
fi
state_file="${state_file}"
attempt=0
if [[ -f "\${state_file}" ]]; then
  attempt="\$(cat "\${state_file}")"
fi
attempt=\$((attempt + 1))
printf '%s\n' "\${attempt}" >"\${state_file}"
if [[ "\${attempt}" -eq 1 ]]; then
  sleep 4
fi
cat <<'LSOF'
COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
Virtual  202 nick  txt    REG    1,4        0    1 /Applications/Docker.app/Contents/MacOS/com.docker.backend
Virtual  202 nick   12u  unix    0x0        0    0 /Users/nick/Library/Containers/com.docker.docker/docker.sock
LSOF
EOF
  chmod +x "${TEST_BIN}/lsof"
}

@test "passes and prints figures when all thresholds are met" {
  fake_darwin_memory
  fake_docker_mem 12562779340
  fake_ps_docker_vm
  fake_lsof_docker_owner

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   host memory: 16.0GiB total, 9.2GiB available"* ]]
  [[ "${output}" == *"OK   Docker VM budget: 11.7GiB"* ]]
  [[ "${output}" == *"OK   no competing hypervisor VMs detected"* ]]
}

@test "fails loudly when docker VM budget is below threshold" {
  fake_darwin_memory
  fake_docker_mem 6442450944
  fake_ps_docker_vm
  fake_lsof_docker_owner

  run "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL Docker VM budget: 6.0GiB found; threshold is 8GiB (8 via KIND_PREFLIGHT_MIN_DOCKER_MEM_GB); remediation: increase Docker Desktop memory to at least 8GiB"* ]]
  [[ "${output}" == *"OK   host memory: 16.0GiB total, 9.2GiB available"* ]]
}

@test "warns but exits zero when host memory is below warn threshold and above fail threshold" {
  fake_darwin_memory 786432
  fake_docker_mem 12562779340
  fake_ps_docker_vm
  fake_lsof_docker_owner

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARN host memory: 16.0GiB total, 3.0GiB available; warn threshold is 4GiB (4 via KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB); fail threshold is 2GiB (2 via KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB); remediation: close memory-hungry applications or stop other local VMs"* ]]
  [[ "${output}" == *"OK   Docker VM budget: 11.7GiB"* ]]
}

@test "fails when host memory is below the fail threshold" {
  fake_darwin_memory 262144
  fake_docker_mem 12562779340
  fake_ps_docker_vm
  fake_lsof_docker_owner

  run "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL host memory: 1.0GiB available out of 16.0GiB total; fail threshold is 2GiB (2 via KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB); warn threshold is 4GiB (4 via KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB); remediation: close memory-hungry applications or stop other local VMs"* ]]
}

@test "fails clearly when host fail threshold is greater than warn threshold" {
  run env KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB=5 KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB=4 "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL host memory threshold config error: KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB=5GiB is greater than KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB=4GiB; remediation: set KIND_PREFLIGHT_FAIL_HOST_AVAILABLE_GB less than or equal to KIND_PREFLIGHT_MIN_HOST_AVAILABLE_GB"* ]]
}

@test "fails when a Slicer-owned competing VM process exceeds the RSS threshold and includes remediation" {
  fake_darwin_memory
  fake_docker_mem 12562779340
  fake_ps_slicer_vm
  fake_lsof_slicer_owner

  run "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL competing hypervisor VM detected: com.apple.Virtualization.VirtualMachine owner=Slicer pid=301 RSS=3.0GiB; threshold is 2GiB (2 via KIND_PREFLIGHT_COMPETING_VM_RSS_GB); remediation: stop the Slicer VM (Slicer is no longer a supported substrate)"* ]]
}

@test "fails loudly with unknown owner wording when lsof is unavailable" {
  fake_darwin_memory
  fake_docker_mem 12562779340
  fake_ps_slicer_vm
  fake_lsof_unavailable

  run "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL competing hypervisor VM detected: com.apple.Virtualization.VirtualMachine owner=unknown VM owner pid=301 RSS=3.0GiB; threshold is 2GiB (2 via KIND_PREFLIGHT_COMPETING_VM_RSS_GB); remediation: stop the owning VM application (inspect with: lsof -b -n -P -p 301)"* ]]
}

@test "retries once when lsof classification times out and accepts a later Docker owner result" {
  fake_darwin_memory
  fake_docker_mem 12562779340
  fake_ps_docker_vm
  fake_lsof_timeout_then_docker_owner

  run env KIND_PREFLIGHT_LSOF_TIMEOUT_SECONDS=3 "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   no competing hypervisor VMs detected"* ]]
  [ "$(cat "${BATS_TEST_TMPDIR}/lsof-attempts")" = "2" ]
}

@test "fails with timeout wording when lsof classification times out twice" {
  fake_darwin_memory
  fake_docker_mem 12562779340
  fake_ps_slicer_vm
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != "-b -n -P -p 301" ]]; then
  printf 'unexpected lsof args: %s\n' "$*" >&2
  exit 2
fi
sleep 2
EOF
  chmod +x "${TEST_BIN}/lsof"

  run env KIND_PREFLIGHT_LSOF_TIMEOUT_SECONDS=1 "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"owner=classification timed out"* ]]
  [[ "${output}" == *"KIND_PREFLIGHT_LSOF_TIMEOUT_SECONDS"* ]]
  [[ "${output}" != *"owner=unknown VM owner"* ]]
}

@test "KIND_SKIP_MEMORY_PREFLIGHT=1 warns and exits zero" {
  run env KIND_SKIP_MEMORY_PREFLIGHT=1 "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARN memory preflight skipped because KIND_SKIP_MEMORY_PREFLIGHT=1"* ]]
}

@test "threshold env overrides are respected" {
  fake_darwin_memory
  fake_docker_mem 12562779340
  fake_ps_slicer_vm
  fake_lsof_slicer_owner

  run env KIND_PREFLIGHT_COMPETING_VM_RSS_GB=3.5 "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   no competing hypervisor VMs detected"* ]]

  run env KIND_PREFLIGHT_MIN_DOCKER_MEM_GB=12.5 "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"threshold is 12.5GiB (12.5 via KIND_PREFLIGHT_MIN_DOCKER_MEM_GB)"* ]]
}

@test "docker-owned VM with lsof output larger than the pipe buffer is not flagged" {
  fake_darwin_memory
  fake_docker_mem 12562779340
  fake_ps_docker_vm
  fake_lsof_docker_owner_large_output

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   no competing hypervisor VMs detected"* ]]
}
