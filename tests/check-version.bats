#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/check-repo-version.sh"
  export FIXTURE_ROOT="${BATS_TEST_TMPDIR}/repo"
  export GITHUB_FIXTURES="${BATS_TEST_TMPDIR}/github"
  export FAKE_BIN="${BATS_TEST_TMPDIR}/bin"

  mkdir -p "${FIXTURE_ROOT}/.github/workflows"
  mkdir -p "${FIXTURE_ROOT}/apps/demo"
  mkdir -p "${FIXTURE_ROOT}/apps/sentiment"
  mkdir -p "${FIXTURE_ROOT}/apps/subnetcalc"
  mkdir -p "${FIXTURE_ROOT}/apps/subnetcalc/apim-simulator"
  mkdir -p "${FIXTURE_ROOT}/apps/subnetcalc/frontend-react/dist"
  mkdir -p "${FIXTURE_ROOT}/apps/subnetcalc/frontend-typescript-vite/dist"
  mkdir -p "${FIXTURE_ROOT}/apps/subnetcalc/frontend-react/dist/assets"
  mkdir -p "${FIXTURE_ROOT}/apps/subnetcalc/frontend-typescript-vite/dist/assets"
  mkdir -p "${FIXTURE_ROOT}/apps/subnetcalc/frontend-react/node_modules"
  mkdir -p "${FIXTURE_ROOT}/apps/subnetcalc/frontend-typescript-vite/node_modules"
  mkdir -p "${FAKE_BIN}"

  cat >"${FAKE_BIN}/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pm" && "${2:-}" == "ls" ]]; then
  if [[ ! -f .package-count ]]; then
    echo "missing .package-count in ${PWD}" >&2
    exit 1
  fi

  count="$(tr -d '[:space:]' < .package-count)"
  printf '%s node_modules (%s)\n' "${PWD}" "${count}"
  exit 0
fi

echo "unsupported fake bun command: $*" >&2
exit 1
EOF
  chmod +x "${FAKE_BIN}/bun"
  export PATH="${FAKE_BIN}:${PATH}"

  cat >"${FIXTURE_ROOT}/.github/workflows/release.yml" <<'EOF'
name: Release
jobs:
  semantic-release:
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
      - uses: actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e # v6.4.0
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

  cat >"${FIXTURE_ROOT}/apps/subnetcalc/apim-simulator/pyproject.toml" <<'EOF'
[project]
name = "apim-simulator"
version = "0.4.0"
EOF

  cat >"${FIXTURE_ROOT}/apps/subnetcalc/apim-simulator.vendor.json" <<'EOF'
{
  "vendored_path": "apps/subnetcalc/apim-simulator",
  "upstream": {
    "origin": "git@example.com:example/apim-simulator.git",
    "ref_kind": "tag",
    "requested_ref": "v0.4.0",
    "resolved_commit": "fd545987759d1d373ef015da2882532717e027fa"
  }
}
EOF

  for app in subnetcalc sentiment; do
    cat >"${FIXTURE_ROOT}/apps/${app}/catalog-info.yaml" <<EOF
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: ${app}
  annotations:
    backstage.io/techdocs-ref: dir:.
spec:
  type: openapi
  lifecycle: experimental
  owner: platform
  definition: |
    openapi: 3.0.3
    info:
      title: ${app}
      version: 0.1.0
    paths: {}
EOF

    cat >"${FIXTURE_ROOT}/apps/${app}/mkdocs.yml" <<'EOF'
site_name: fixture
docs_dir: .
plugins:
  - techdocs-core
EOF
  done

  cat >"${FIXTURE_ROOT}/apps/subnetcalc/frontend-budgets.json" <<'EOF'
{
  "frontends": [
    {
      "name": "frontend-react",
      "path": "apps/subnetcalc/frontend-react",
      "max_installed_packages": 240,
      "max_dist_asset_raw_bytes": 4096,
      "max_dist_asset_gzip_bytes": 1024,
      "max_initial_asset_raw_bytes": 4096,
      "max_initial_asset_gzip_bytes": 1024
    },
    {
      "name": "frontend-typescript-vite",
      "path": "apps/subnetcalc/frontend-typescript-vite",
      "max_installed_packages": 124,
      "max_dist_asset_raw_bytes": 4096,
      "max_dist_asset_gzip_bytes": 1024,
      "max_initial_asset_raw_bytes": 4096,
      "max_initial_asset_gzip_bytes": 1024
    }
  ]
}
EOF

  cat >"${FIXTURE_ROOT}/apps/subnetcalc/frontend-react/dist/index.html" <<'EOF'
<!doctype html>
<html>
  <head>
    <script type="module" src="/assets/index.js"></script>
  </head>
</html>
EOF

  cat >"${FIXTURE_ROOT}/apps/subnetcalc/frontend-typescript-vite/dist/index.html" <<'EOF'
<!doctype html>
<html>
  <head>
    <script type="module" src="/assets/index.js"></script>
  </head>
</html>
EOF

  printf '240\n' >"${FIXTURE_ROOT}/apps/subnetcalc/frontend-react/.package-count"
  printf '124\n' >"${FIXTURE_ROOT}/apps/subnetcalc/frontend-typescript-vite/.package-count"

  uv run --isolated python - <<'PY' "${FIXTURE_ROOT}"
from pathlib import Path
import sys

root = Path(sys.argv[1])
payload = bytes(range(256)) * 4

for rel in (
    "apps/subnetcalc/frontend-react/dist/assets/index.js",
    "apps/subnetcalc/frontend-typescript-vite/dist/assets/index.js",
):
    (root / rel).write_bytes(payload)
PY

  mkdir -p "${GITHUB_FIXTURES}/repos/actions/checkout/commits"
  mkdir -p "${GITHUB_FIXTURES}/repos/actions/setup-node/commits"
  printf '{"sha":"de0fac2e4500dabe0009e67214ff5f5447ce83dd"}\n' >"${GITHUB_FIXTURES}/repos/actions/checkout/commits/v6.0.2"
  printf '{"sha":"48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e"}\n' >"${GITHUB_FIXTURES}/repos/actions/setup-node/commits/v6.4.0"
}

@test "check-version passes with matching workflow pins and dependency age gates" {
  run env \
    CHECK_VERSION_REPO_ROOT="${FIXTURE_ROOT}" \
    CHECK_VERSION_WORKFLOW_FILE="${FIXTURE_ROOT}/.github/workflows/release.yml" \
    CHECK_VERSION_GITHUB_API_BASE="file://${GITHUB_FIXTURES}" \
    "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"actions/checkout v6.0.2 resolves to the pinned SHA"* ]]
  [[ "${output}" == *"apim-simulator v0.4.0 (fd545987759d1d373ef015da2882532717e027fa) is vendored; version 0.4.0; profile full"* ]]
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
    "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *".npmrc min-release-age gates are not synchronized"* ]]
  [[ "${output}" == *"version check(s) failed."* ]]
}

@test "check-version reports frontend package and bundle budgets" {
  run env \
    CHECK_VERSION_REPO_ROOT="${FIXTURE_ROOT}" \
    CHECK_VERSION_WORKFLOW_FILE="${FIXTURE_ROOT}/.github/workflows/release.yml" \
    CHECK_VERSION_GITHUB_API_BASE="file://${GITHUB_FIXTURES}" \
    "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"frontend-react: installed packages 240 <= 240"* ]]
  [[ "${output}" == *"frontend-typescript-vite: installed packages 124 <= 124"* ]]
  [[ "${output}" == *"frontend-react: initial asset raw bytes"* ]]
  [[ "${output}" == *"All frontend package and bundle budgets passed."* ]]
}

@test "check-version fails when a frontend package budget regresses" {
  cat >"${FIXTURE_ROOT}/apps/subnetcalc/frontend-budgets.json" <<'EOF'
{
  "frontends": [
    {
      "name": "frontend-react",
      "path": "apps/subnetcalc/frontend-react",
      "max_installed_packages": 200,
      "max_dist_asset_raw_bytes": 4096,
      "max_dist_asset_gzip_bytes": 1024,
      "max_initial_asset_raw_bytes": 4096,
      "max_initial_asset_gzip_bytes": 1024
    }
  ]
}
EOF

  run env \
    CHECK_VERSION_REPO_ROOT="${FIXTURE_ROOT}" \
    CHECK_VERSION_WORKFLOW_FILE="${FIXTURE_ROOT}/.github/workflows/release.yml" \
    CHECK_VERSION_GITHUB_API_BASE="file://${GITHUB_FIXTURES}" \
    "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"frontend-react: installed packages 240 exceed budget 200"* ]]
  [[ "${output}" == *"version check(s) failed."* ]]
}
