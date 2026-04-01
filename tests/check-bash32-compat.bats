#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/check-bash32-compat.sh"
}

@test "check-bash32-compat passes a Bash 3.2-compatible script" {
  candidate="${BATS_TEST_TMPDIR}/ok.sh"

  cat >"${candidate}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

values=()
values+=("ok")
printf '%s\n' "${values[@]}"
EOF

  run /bin/bash "${SCRIPT}" "${candidate}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   Bash 3.2 compatibility"* ]]
}

@test "check-bash32-compat reports Bash 4-only constructs" {
  candidate="${BATS_TEST_TMPDIR}/bad.sh"

  cat >"${candidate}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

local -A seen=()
mapfile -t values < <(printf '%s\n' one two)
EOF

  run /bin/bash "${SCRIPT}" "${candidate}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL Bash 3.2 compatibility"* ]]
  [[ "${output}" == *"bad.sh:4:local -A seen=()"* ]]
  [[ "${output}" == *"bad.sh:5:mapfile -t values"* ]]
}
