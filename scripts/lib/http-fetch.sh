#!/usr/bin/env bash
# shellcheck shell=bash

http_require_curl() {
  command -v curl >/dev/null 2>&1 || {
    echo "${0##*/}: curl not found in PATH" >&2
    return 1
  }
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
  if [ -n "${HTTP_FETCH_CACHE_DIR:-}" ] && [ -d "${HTTP_FETCH_CACHE_DIR}" ]; then
    printf '%s\n' "${HTTP_FETCH_CACHE_DIR}"
    return 0
  fi

  HTTP_FETCH_CACHE_DIR="$(mktemp -d)"
  printf '%s\n' "${HTTP_FETCH_CACHE_DIR}"
}

http_cache_file_for_key() {
  local prefix="$1"
  local key="$2"
  local cache_dir=""

  cache_dir="$(http_cache_dir_ensure)"
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

  tmp_file="$(mktemp)"
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
