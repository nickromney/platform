#!/usr/bin/env bash
# shellcheck shell=bash

http_require_curl() {
  command -v curl >/dev/null 2>&1 || {
    echo "${0##*/}: curl not found in PATH" >&2
    return 1
  }
}

http_temp_file() {
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

http_temp_dir() {
  local var_name="${1:-}"
  local path=""

  if declare -F platform_mktemp_dir >/dev/null 2>&1 && [ -n "${var_name}" ]; then
    platform_mktemp_dir "${var_name}"
    return 0
  fi

  path="$(mktemp -d)"
  if [ -n "${var_name}" ]; then
    printf -v "${var_name}" '%s' "${path}"
    return 0
  fi

  printf '%s\n' "${path}"
}

http_fetch() {
  local max_time="${HTTP_FETCH_MAX_TIME_SECONDS:-15}"
  local connect_timeout="${HTTP_FETCH_CONNECT_TIMEOUT_SECONDS:-5}"

  curl \
    --connect-timeout "${connect_timeout}" \
    --max-time "${max_time}" \
    --retry 0 \
    "$@"
}

http_cache_dir_ensure() {
  local var_name="${1:-}"

  if [ -n "${HTTP_FETCH_CACHE_DIR:-}" ] && [ -d "${HTTP_FETCH_CACHE_DIR}" ]; then
    if [ -n "${var_name}" ]; then
      printf -v "${var_name}" '%s' "${HTTP_FETCH_CACHE_DIR}"
      return 0
    fi

    printf '%s\n' "${HTTP_FETCH_CACHE_DIR}"
    return 0
  fi

  http_temp_dir HTTP_FETCH_CACHE_DIR
  if [ -n "${var_name}" ]; then
    printf -v "${var_name}" '%s' "${HTTP_FETCH_CACHE_DIR}"
    return 0
  fi

  printf '%s\n' "${HTTP_FETCH_CACHE_DIR}"
}

http_cache_file_for_key() {
  local prefix="$1"
  local key="$2"
  local cache_dir=""

  http_cache_dir_ensure cache_dir
  printf "%s/%s\n" "${cache_dir}" "$(printf '%s__%s' "${prefix}" "${key}" | tr '/:@?&=%' '_')"
}

http_cached_output() {
  local prefix="$1"
  local key="$2"
  local cache_file tmp_file
  shift 2

  cache_file="$(http_cache_file_for_key "${prefix}" "${key}")"
  if [ -f "${cache_file}" ]; then
    cat "${cache_file}"
    return 0
  fi

  http_temp_file tmp_file
  if "$@" >"${tmp_file}"; then
    mv "${tmp_file}" "${cache_file}"
    cat "${cache_file}"
    return 0
  fi

  rm -f "${tmp_file}"
  return 1
}

http_json_get() {
  http_fetch -fsSL "$@"
}

http_status_code() {
  local url="$1"
  shift || true

  http_fetch -sS -o /dev/null -w "%{http_code}" "$@" "${url}"
}
