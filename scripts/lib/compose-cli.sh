#!/usr/bin/env bash
# shellcheck shell=bash

compose_cli_have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

compose_cli_backend() {
  if compose_cli_have_cmd docker && docker compose version >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    printf 'docker compose\n'
    return 0
  fi

  if compose_cli_have_cmd nerdctl && nerdctl version >/dev/null 2>&1 && nerdctl info >/dev/null 2>&1; then
    printf 'nerdctl compose\n'
    return 0
  fi

  if compose_cli_have_cmd colima && colima nerdctl info >/dev/null 2>&1; then
    printf 'colima nerdctl compose\n'
    return 0
  fi

  if compose_cli_have_cmd podman && podman compose version >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    printf 'podman compose\n'
    return 0
  fi

  if compose_cli_have_cmd podman-compose && podman info >/dev/null 2>&1; then
    printf 'podman-compose\n'
    return 0
  fi

  return 1
}

compose_cli() {
  local backend
  local -a cmd=()

  if ! backend="$(compose_cli_backend)"; then
    printf '%s\n' \
      'compose-cli: a supported compose backend is required (docker compose, nerdctl compose, colima nerdctl compose, podman compose, or podman-compose)' >&2
    return 1
  fi

  read -r -a cmd <<<"${backend}"
  "${cmd[@]}" "$@"
}
