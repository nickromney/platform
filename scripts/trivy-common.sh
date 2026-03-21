#!/usr/bin/env bash

trivy_local_version() {
  local version=""

  command -v trivy >/dev/null 2>&1 || return 1

  version="$(
    trivy --version 2>/dev/null | awk '
      /^Version:/ {
        print $2
        found = 1
        exit
      }
      END {
        exit(found ? 0 : 1)
      }
    '
  )" || return 1

  printf '%s\n' "${version#v}"
}

trivy_local_status() {
  local version=""

  if ! command -v trivy >/dev/null 2>&1; then
    printf 'missing\n'
    return 0
  fi

  if ! version="$(trivy_local_version)"; then
    printf 'unparseable\n'
    return 0
  fi

  printf 'available:%s\n' "${version}"
}
