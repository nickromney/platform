#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "tracked host-side code avoids bare python references outside approved exceptions" {
  run bash -c '
    set -euo pipefail
    allowed_files=(
      ".devcontainer/Dockerfile"
      ".devcontainer/check-toolchain-surface.sh"
      "kubernetes/kind/tests/check-version.bats"
      "scripts/audit-shell-scripts.sh"
      "tests/audit-shell-scripts.bats"
    )
    allowed_prefixes=(
      "apps/apim-simulator/"
      "apps/backstage/"
      "docs/"
      "kubernetes/workflow/"
      "tests/local-idp-contracts.bats"
      "tests/sso-e2e-app-toggles.bats"
      "tests/validate-kyverno-policies.bats"
      "tools/platform-workflow-ui/"
    )
    unexpected=()
    while IFS= read -r raw_line; do
      relative_path="${raw_line%%:*}"
      allowed=0
      for file in "${allowed_files[@]}"; do
        if [[ "${relative_path}" == "${file}" ]]; then
          allowed=1
          break
        fi
      done
      if [[ "${allowed}" == "0" ]]; then
        for prefix in "${allowed_prefixes[@]}"; do
          if [[ "${relative_path}" == "${prefix}"* ]]; then
            allowed=1
            break
          fi
        done
      fi
      if [[ "${allowed}" == "0" ]]; then
        unexpected+=("${raw_line}")
      fi
    done < <(git -C "${REPO_ROOT}" grep -n "python3" -- . || true)
    if [[ "${#unexpected[@]}" -gt 0 ]]; then
      printf "%s\n" "${unexpected[@]}" >&2
      exit 1
    fi
    printf "validated %s approved bare-python reference file(s)\n" "${#allowed_files[@]}"
  '

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 5 approved bare-python reference file(s)"* ]]
}
