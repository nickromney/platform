#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/check-version.sh"
  export FIXTURE_ROOT="${BATS_TEST_TMPDIR}/repo"
  export GITHUB_FIXTURES="${BATS_TEST_TMPDIR}/github"

  mkdir -p "${FIXTURE_ROOT}/.github/workflows"
  mkdir -p "${FIXTURE_ROOT}/apps/demo"

  cat >"${FIXTURE_ROOT}/.github/workflows/release.yml" <<'EOF'
name: Release
jobs:
  semantic-release:
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
      - uses: actions/setup-node@53b83947a5a98c8d113130e565377fae1a50d02f # v6
EOF

  cat >"${FIXTURE_ROOT}/apps/demo/.npmrc" <<'EOF'
min-release-age=7
EOF

  cat >"${FIXTURE_ROOT}/apps/demo/bunfig.toml" <<'EOF'
[install]
minimumReleaseAge = 604800
EOF

  cat >"${FIXTURE_ROOT}/apps/demo/pyproject.toml" <<'EOF'
[project]
name = "demo"
version = "0.1.0"

[tool.uv]
exclude-newer = "7 days"
EOF

  mkdir -p "${GITHUB_FIXTURES}/repos/actions/checkout/commits"
  mkdir -p "${GITHUB_FIXTURES}/repos/actions/setup-node/commits"
  printf '{"sha":"de0fac2e4500dabe0009e67214ff5f5447ce83dd"}\n' >"${GITHUB_FIXTURES}/repos/actions/checkout/commits/v6.0.2"
  printf '{"sha":"53b83947a5a98c8d113130e565377fae1a50d02f"}\n' >"${GITHUB_FIXTURES}/repos/actions/setup-node/commits/v6"
}

@test "check-version passes with matching workflow pins and dependency age gates" {
  run env \
    CHECK_VERSION_REPO_ROOT="${FIXTURE_ROOT}" \
    CHECK_VERSION_WORKFLOW_FILE="${FIXTURE_ROOT}/.github/workflows/release.yml" \
    CHECK_VERSION_GITHUB_API_BASE="file://${GITHUB_FIXTURES}" \
    "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"actions/checkout v6.0.2 resolves to the pinned SHA"* ]]
  [[ "${output}" == *"All .npmrc files set min-release-age=7"* ]]
  [[ "${output}" == *"All bunfig.toml files set minimumReleaseAge=604800"* ]]
  [[ "${output}" == *"All uv-managed pyproject.toml files set exclude-newer='7 days'"* ]]
  [[ "${output}" == *"All version checks passed."* ]]
}

@test "check-version fails when a dependency age gate drifts" {
  cat >"${FIXTURE_ROOT}/apps/demo/.npmrc" <<'EOF'
min-release-age=3
EOF

  run env \
    CHECK_VERSION_REPO_ROOT="${FIXTURE_ROOT}" \
    CHECK_VERSION_WORKFLOW_FILE="${FIXTURE_ROOT}/.github/workflows/release.yml" \
    CHECK_VERSION_GITHUB_API_BASE="file://${GITHUB_FIXTURES}" \
    "${SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *".npmrc min-release-age gates are not synchronized"* ]]
  [[ "${output}" == *"version check(s) failed."* ]]
}
