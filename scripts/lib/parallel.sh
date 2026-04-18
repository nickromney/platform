#!/usr/bin/env bash
# shellcheck shell=bash

parallel_default_jobs() {
  printf '%s\n' "${PLATFORM_PARALLEL_JOBS:-4}"
}

parallel_temp_file() {
  local var_name="${1:-}"
  local path=""

  if declare -F platform_mktemp_file >/dev/null 2>&1 && [ -n "${var_name}" ]; then
    platform_mktemp_file "${var_name}"
    return 0
  fi

  path="$(mktemp)"
  if [ -n "${var_name}" ]; then
    printf -v "${var_name}" '%s' "${path}"
    return 0
  fi

  printf '%s\n' "${path}"
}

parallel_wait_all() {
  local overall_status=0
  local pid

  for pid in "$@"; do
    if ! wait "${pid}"; then
      overall_status=1
    fi
  done

  return "${overall_status}"
}

parallel_map_lines() {
  local max_jobs="$1"
  local callback="$2"
  local input_file="$3"
  local output_dir="$4"
  local line outfile idx
  local -a pids=()
  local overall_status=0

  mkdir -p "${output_dir}"
  idx=0

  while IFS= read -r line || [ -n "${line}" ]; do
    idx=$((idx + 1))
    outfile="${output_dir}/${idx}"
    (
      "${callback}" "${line}"
    ) >"${outfile}" &
    pids+=("$!")

    if [ "${#pids[@]}" -ge "${max_jobs}" ]; then
      if ! wait "${pids[0]}"; then
        overall_status=1
      fi
      pids=("${pids[@]:1}")
    fi
  done <"${input_file}"

  while [ "${#pids[@]}" -gt 0 ]; do
    if ! wait "${pids[0]}"; then
      overall_status=1
    fi
    pids=("${pids[@]:1}")
  done

  for idx in $(seq 1 "${idx}"); do
    [ -f "${output_dir}/${idx}" ] || continue
    cat "${output_dir}/${idx}"
  done

  return "${overall_status}"
}

parallel_map_stdin() {
  local max_jobs="$1"
  local callback="$2"
  local output_dir="$3"
  local input_file

  parallel_temp_file input_file
  cat >"${input_file}"
  parallel_map_lines "${max_jobs}" "${callback}" "${input_file}" "${output_dir}"
  rm -f "${input_file}"
}
