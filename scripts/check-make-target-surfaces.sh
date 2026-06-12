#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: check-make-target-surfaces.sh --execute

Load every repo-owned Makefile and inspect its make database without running
recipes. This catches broken includes, invalid make syntax, and missing target
definitions across the repository's documented make surfaces.
USAGE
}

if [ "${1:-}" != "--execute" ]; then
  usage
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="${TMPDIR:-/tmp}/platform-make-target-surfaces.$$"
mkdir -p "${tmp_dir}"
trap 'rm -rf "${tmp_dir}"' EXIT

make_known_goals_script="${repo_root}/scripts/make-known-goals.sh"

makefiles="$(
  cd "${repo_root}"
  find . \
    -path './.git' -prune -o \
    -path './.run' -prune -o \
    -path './*/node_modules/*' -prune -o \
    -name Makefile -print | sort
)"

makefiles_checked=0
targets_checked=0
failures=0

while IFS= read -r makefile; do
  [ -n "${makefile}" ] || continue
  dir="${makefile%/Makefile}"
  db_file="${tmp_dir}/$(printf '%s' "${dir}" | tr '/.' '__').mkdb"
  err_file="${db_file}.err"
  goals_file="${db_file}.goals"

  status=0
  "${make_known_goals_script}" \
    --dir "${repo_root}/${dir}" \
    --database-out "${db_file}" \
    --execute >"${goals_file}" 2>"${err_file}" || status=$?

  if [ "${status}" -gt 1 ]; then
    failures=$((failures + 1))
    printf 'make database load failed: %s\n' "${dir}" >&2
    cat "${err_file}" >&2
    continue
  fi

  makefiles_checked=$((makefiles_checked + 1))
  targets="$(
  {
    awk '
      /^\.PHONY:[[:space:]]/ {
        for (i = 2; i <= NF; i++) {
          if ($i !~ /[$()]/ && $i != "\\") {
            print $i
          }
        }
      }
    ' "${db_file}"
    awk '
      {
        for (i = 1; i <= NF; i++) {
          print $i
        }
      }
    ' "${goals_file}"
  } | awk '$0 !~ /[$()]/ && $0 != "\\"' | LC_ALL=C sort -u
  )"

  while IFS= read -r target; do
    [ -n "${target}" ] || continue
    targets_checked=$((targets_checked + 1))
    if ! awk -v target="${target}" 'index($0, target ":") == 1 { found = 1; exit } END { exit found ? 0 : 1 }' "${db_file}"; then
      failures=$((failures + 1))
      printf 'phony target missing from make database: %s %s\n' "${dir}" "${target}" >&2
    fi
  done <<<"${targets}"
done <<<"${makefiles}"

if [ "${failures}" -gt 0 ]; then
  printf 'checked %s targets across %s Makefiles; %s failed\n' "${targets_checked}" "${makefiles_checked}" "${failures}" >&2
  exit 1
fi

printf 'checked %s targets across %s repo-owned Makefiles\n' "${targets_checked}" "${makefiles_checked}"
