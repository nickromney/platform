#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

TESTS_DIR="${TESTS_DIR:-${REPO_ROOT}/kubernetes/kind/tests}"
BATS_BIN="${BATS:-bats}"
BATS_SHARDS="${BATS_SHARDS:-7}"
BATS_FLAGS="${BATS_FLAGS:---timing}"
BATS_PROGRESS_SECONDS="${BATS_PROGRESS_SECONDS:-15}"
PLAN_ONLY=0

usage() {
  cat <<'EOF'
Usage: run-bats-shards.sh [--tests-dir DIR] [--shards N] [--plan]

Split Kind Bats test cases into balanced shards and run those shards in
parallel. Each shard groups tests by file and invokes Bats with generated
`--filter` expressions, so oversized files do not dominate one shard.

Environment:
  BATS          Bats binary to run (default: bats)
  BATS_FLAGS    Flags passed to each bats shard (default: --timing)
  BATS_SHARDS   Number of parallel shards (default: 7)
  BATS_PROGRESS_SECONDS
                Seconds between progress updates (default: 15)

Options:
  --tests-dir DIR  Directory containing .bats files
  --shards N       Number of shards
  --plan           Print the shard plan without running tests
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tests-dir)
      TESTS_DIR="${2:?--tests-dir requires a value}"
      shift 2
      ;;
    --shards)
      BATS_SHARDS="${2:?--shards requires a value}"
      shift 2
      ;;
    --plan)
      PLAN_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "${BATS_SHARDS}" in
  ''|*[!0-9]*)
    echo "BATS_SHARDS must be a positive integer" >&2
    exit 2
    ;;
esac

if [[ "${BATS_SHARDS}" -lt 1 ]]; then
  echo "BATS_SHARDS must be at least 1" >&2
  exit 2
fi

case "${BATS_PROGRESS_SECONDS}" in
  ''|*[!0-9]*)
    echo "BATS_PROGRESS_SECONDS must be a non-negative integer" >&2
    exit 2
    ;;
esac

if [[ ! -d "${TESTS_DIR}" ]]; then
  echo "Bats tests directory not found: ${TESTS_DIR}" >&2
  exit 2
fi

RUN_DIR="${REPO_ROOT}/.run/bats-shards/kind"
rm -rf "${RUN_DIR}"
mkdir -p "${RUN_DIR}"

TESTS_FILE="${RUN_DIR}/tests.tsv"
find "${TESTS_DIR}" -maxdepth 1 -type f -name '*.bats' -print | sort | while IFS= read -r file; do
  sed -n 's/^@test "\([^"]*\)" {.*/\1/p' "${file}" | while IFS= read -r test_name; do
    printf '%s\t%s\n' "${file}" "${test_name}"
  done
done > "${TESTS_FILE}"

declare -a shard_loads=()
declare -a shard_files=()
declare -a shard_counts=()

i=0
while [[ "${i}" -lt "${BATS_SHARDS}" ]]; do
  shard_loads[i]=0
  shard_counts[i]=0
  shard_files[i]="${RUN_DIR}/shard-$((i + 1)).txt"
  : > "${shard_files[i]}"
  i=$((i + 1))
done

while IFS=$'\t' read -r file test_name; do
  min_index=0
  min_load="${shard_loads[0]}"
  i=1
  while [[ "${i}" -lt "${BATS_SHARDS}" ]]; do
    if [[ "${shard_loads[i]}" -lt "${min_load}" ]]; then
      min_index="${i}"
      min_load="${shard_loads[i]}"
    fi
    i=$((i + 1))
  done

  printf '%s\t%s\n' "${file}" "${test_name}" >> "${shard_files[min_index]}"
  shard_loads[min_index]=$((shard_loads[min_index] + 1))
done < "${TESTS_FILE}"

i=0
while [[ "${i}" -lt "${BATS_SHARDS}" ]]; do
  if [[ -s "${shard_files[i]}" ]]; then
    shard_counts[i]="$(cut -f1 "${shard_files[i]}" | sort -u | wc -l | tr -d ' ')"
  fi
  i=$((i + 1))
done

total_tests=0
total_files=0
i=0
while [[ "${i}" -lt "${BATS_SHARDS}" ]]; do
  total_tests=$((total_tests + shard_loads[i]))
  total_files=$((total_files + shard_counts[i]))
  printf 'shard %d: %d tests across %d file groups\n' "$((i + 1))" "${shard_loads[i]}" "${shard_counts[i]}"
  if [[ "${PLAN_ONLY}" -eq 1 ]]; then
    sed "s#^${REPO_ROOT}/#  #" "${shard_files[i]}"
  fi
  i=$((i + 1))
done
printf 'total: %d tests across %d shard file groups\n' "${total_tests}" "${total_files}"

if [[ "${PLAN_ONLY}" -eq 1 ]]; then
  exit 0
fi

declare -a pids=()
declare -a logs=()
declare -a shard_done=()
declare -a shard_exit=()
declare -a shard_started_at=()
declare -a shard_finished_at=()

now_epoch() {
  date +%s
}

now_stamp() {
  date '+%Y-%m-%d %H:%M:%S %Z'
}

format_duration() {
  local seconds="$1"
  local minutes=0
  local remaining=0

  minutes=$((seconds / 60))
  remaining=$((seconds % 60))
  if [[ "${minutes}" -gt 0 ]]; then
    printf '%dm%02ds' "${minutes}" "${remaining}"
  else
    printf '%ds' "${remaining}"
  fi
}

latest_log_line() {
  local log="$1"

  if [[ ! -s "${log}" ]]; then
    printf '%s\n' 'starting'
    return 0
  fi

  awk '
    NF && $0 !~ /^1\.\.[0-9]+$/ && $0 !~ /^#/ {
      line=$0
    }
    END {
      if (line != "") {
        print line
      } else {
        print "running"
      }
    }
  ' "${log}"
}

count_completed_tests() {
  local log="$1"

  [[ -s "${log}" ]] || {
    printf '0\n'
    return 0
  }

  awk '/^(ok|not ok) [0-9]+ / { count++ } END { print count + 0 }' "${log}"
}

count_failed_tests() {
  local log="$1"

  [[ -s "${log}" ]] || {
    printf '0\n'
    return 0
  }

  awk '/^not ok [0-9]+ / { count++ } END { print count + 0 }' "${log}"
}

print_progress() {
  local completed=0
  local failed=0
  local running=0
  local tests_done=0
  local shard_tests_done=0
  local shard_failed_tests=0
  local failed_tests=0
  local elapsed=0
  local percent=0
  local line=""

  i=0
  while [[ "${i}" -lt "${BATS_SHARDS}" ]]; do
    if [[ "${shard_counts[i]}" -eq 0 ]]; then
      i=$((i + 1))
      continue
    fi
    if [[ "${shard_done[i]:-0}" -eq 1 ]]; then
      completed=$((completed + 1))
      if [[ "${shard_exit[i]:-0}" -ne 0 ]]; then
        failed=$((failed + 1))
      fi
    else
      running=$((running + 1))
    fi
    shard_tests_done="$(count_completed_tests "${logs[i]}")"
    if [[ "${shard_tests_done}" -gt "${shard_loads[i]}" ]]; then
      shard_tests_done="${shard_loads[i]}"
    fi
    tests_done=$((tests_done + shard_tests_done))
    shard_failed_tests="$(count_failed_tests "${logs[i]}")"
    failed_tests=$((failed_tests + shard_failed_tests))
    i=$((i + 1))
  done

  elapsed=$(($(now_epoch) - START_EPOCH))
  if [[ "${total_tests}" -gt 0 ]]; then
    percent=$((tests_done * 100 / total_tests))
  fi

  printf 'progress: %s elapsed, %d/%d shards complete, %d/%d tests complete (%d%%), %d running, %d failed shards, %d failed tests\n' \
    "$(format_duration "${elapsed}")" "${completed}" "${active_shards}" \
    "${tests_done}" "${total_tests}" "${percent}" "${running}" "${failed}" "${failed_tests}"

  i=0
  while [[ "${i}" -lt "${BATS_SHARDS}" ]]; do
    if [[ "${shard_counts[i]}" -eq 0 || "${shard_done[i]:-0}" -eq 1 ]]; then
      i=$((i + 1))
      continue
    fi
    shard_tests_done="$(count_completed_tests "${logs[i]}")"
    if [[ "${shard_tests_done}" -gt "${shard_loads[i]}" ]]; then
      shard_tests_done="${shard_loads[i]}"
    fi
    line="$(latest_log_line "${logs[i]}")"
    printf '  shard %d/%d: %d/%d tests, pid %s, latest: %s\n' \
      "$((i + 1))" "${BATS_SHARDS}" "${shard_tests_done}" "${shard_loads[i]}" "${pids[i]}" "${line}"
    i=$((i + 1))
  done
}

i=0
active_shards=0
while [[ "${i}" -lt "${BATS_SHARDS}" ]]; do
  if [[ "${shard_counts[i]}" -eq 0 ]]; then
    i=$((i + 1))
    continue
  fi

  log="${RUN_DIR}/shard-$((i + 1)).log"
  logs[i]="${log}"
  shard_done[i]=0
  shard_exit[i]=0
  shard_started_at[i]="$(now_epoch)"
  (
    current_file=""
    regex=""
    run_file_group() {
      [[ -n "${current_file}" ]] || return 0
      # shellcheck disable=SC2086
      "${BATS_BIN}" ${BATS_FLAGS} --filter "^(${regex})$" "${current_file}"
    }
    regex_escape() {
      sed 's/[][(){}.^$*+?|\\]/\\&/g'
    }
    while IFS=$'\t' read -r file test_name; do
      escaped_name="$(printf '%s' "${test_name}" | regex_escape)"
      if [[ "${file}" != "${current_file}" ]]; then
        run_file_group
        current_file="${file}"
        regex="${escaped_name}"
      else
        regex="${regex}|${escaped_name}"
      fi
    done < <(sort "${shard_files[i]}")
    run_file_group
  ) > "${log}" 2>&1 &
  pids[i]=$!
  active_shards=$((active_shards + 1))
  printf 'started shard %d/%d: %d tests, %d file groups, pid %s, log %s\n' \
    "$((i + 1))" "${BATS_SHARDS}" "${shard_loads[i]}" "${shard_counts[i]}" "${pids[i]}" "${log}"
  i=$((i + 1))
done

START_EPOCH="$(now_epoch)"
printf 'started Kind Bats shards at %s (%d shards, %d tests, logs: %s)\n' \
  "$(now_stamp)" "${active_shards}" "${total_tests}" "${RUN_DIR}"

status=0
remaining="${active_shards}"
while [[ "${remaining}" -gt 0 ]]; do
  i=0
  while [[ "${i}" -lt "${BATS_SHARDS}" ]]; do
    if [[ -n "${pids[i]:-}" && "${shard_done[i]:-0}" -eq 0 ]]; then
      if kill -0 "${pids[i]}" 2>/dev/null; then
        :
      else
        if wait "${pids[i]}"; then
          shard_exit[i]=0
        else
          shard_exit[i]=$?
          status="${shard_exit[i]}"
        fi
        shard_done[i]=1
        shard_finished_at[i]="$(now_epoch)"
        remaining=$((remaining - 1))

        if [[ "${shard_exit[i]}" -eq 0 ]]; then
          printf 'ok shard %d (%d tests) in %s: %s\n' \
            "$((i + 1))" "${shard_loads[i]}" \
            "$(format_duration "$((shard_finished_at[i] - shard_started_at[i]))")" \
            "${logs[i]}"
        else
          printf 'not ok shard %d (%d tests) in %s: %s\n' \
            "$((i + 1))" "${shard_loads[i]}" \
            "$(format_duration "$((shard_finished_at[i] - shard_started_at[i]))")" \
            "${logs[i]}" >&2
          sed -n '1,220p' "${logs[i]}" >&2
        fi
      fi
    fi
    i=$((i + 1))
  done

  if [[ "${remaining}" -gt 0 ]]; then
    print_progress
    sleep "${BATS_PROGRESS_SECONDS}"
  fi
done

print_progress
printf 'finished Kind Bats shards at %s after %s\n' \
  "$(now_stamp)" "$(format_duration "$(($(now_epoch) - START_EPOCH))")"

if [[ "${status}" -ne 0 ]]; then
  echo "Shard logs are under ${RUN_DIR}" >&2
fi

exit "${status}"
