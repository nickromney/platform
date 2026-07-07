#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

@test "kind stage and operator tfvars do not redefine top-level attributes" {
  run bash -c '
    set -euo pipefail

    repo_root="${1}"
    file_list="${BATS_TEST_TMPDIR}/tfvars-files.txt"

    {
      find "${repo_root}/kubernetes/kind/stages" -maxdepth 1 -type f -name "*.tfvars" -print
      if [ -d "${repo_root}/kubernetes/kind/variants" ]; then
        find "${repo_root}/kubernetes/kind/variants" -maxdepth 1 -type f -name "*.tfvars" -print
      fi
      find "${repo_root}/kubernetes" \
        \( -path "*/tests/artifacts" -o -path "*/.run" \) -prune -o \
        \( -path "*/profiles/*.tfvars" -o -path "*/operator-profiles/*.tfvars" -o -path "*/operator_profiles/*.tfvars" \) \
        -type f -print
    } | sort -u >"${file_list}"

    test -s "${file_list}"

    status=0
    while IFS= read -r tfvars_file; do
      awk '"'"'
        /^[a-z0-9_]+[[:space:]]*=/ {
          key = $1
          if (++seen[key] == 2) {
            printf "%s: duplicate top-level attribute %s\n", FILENAME, key
            failed = 1
          }
        }
        END { exit failed }
      '"'"' "${tfvars_file}" || status=1
    done <"${file_list}"

    exit "${status}"
  ' bash "${REPO_ROOT}"

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
}
