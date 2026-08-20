#!/usr/bin/env bash
# shellcheck shell=bash
#
# Dotted numeric version comparison without GNU `sort -V`, which is absent from
# BSD sort on macOS. A leading `v` is ignored. Missing dotted fields compare as
# zero, so 1.2 and 1.2.0 are equal.

semver_sort_key() {
  awk -v version="${1:-}" '
    BEGIN {
      s = version
      sub(/^v/, "", s)
      n = split(s, parts, ".")
      out = ""
      for (i = 1; i <= 6; i++) {
        out = out sprintf("%020d", (i <= n) ? parts[i] + 0 : 0)
      }
      print out
    }
  '
}

sort_semver() {
  awk '{
    key = $0
    sub(/^v/, "", key)
    n = split(key, parts, ".")
    printf "%020d%020d%020d%020d%020d%020d\t%s\n", parts[1]+0, parts[2]+0, parts[3]+0, parts[4]+0, parts[5]+0, parts[6]+0, $0
  }' | LC_ALL=C sort | cut -f2-
}

version_lt() {
  local left="$1"
  local right="$2"
  local left_key right_key

  left_key="$(semver_sort_key "${left}")"
  right_key="$(semver_sort_key "${right}")"
  [ "${left_key}" \< "${right_key}" ]
}

version_lte() {
  version_lt "$1" "$2" || [ "$(semver_sort_key "$1")" = "$(semver_sort_key "$2")" ]
}

version_gt() {
  version_lt "$2" "$1"
}

version_gte() {
  version_gt "$1" "$2" || [ "$(semver_sort_key "$1")" = "$(semver_sort_key "$2")" ]
}
