#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/scripts/update-versions.sh"
  export COMPONENT_JSON="${BATS_TEST_TMPDIR}/components.json"
  export PROVIDER_JSON="${BATS_TEST_TMPDIR}/providers.json"
  export CALLS="${BATS_TEST_TMPDIR}/calls"
  # Keep the repo's real mise.toml out of reach: tests that exercise the mise
  # install check write their own.
  export MISE_CONFIG_FILE="${BATS_TEST_TMPDIR}/absent-mise.toml"

  cat >"${COMPONENT_JSON}" <<'EOF'
{
  "format": "check-version/v1",
  "components": [
    {
      "component": "kyverno chart",
      "codebase": "1.0.0",
      "latest": "1.1.0",
      "status_code": "update_available",
      "update_available": true
    },
    {
      "component": "argo-cd chart",
      "codebase": "10.2.1",
      "latest": "10.2.1",
      "status_code": "cooldown_active",
      "update_available": false
    }
  ],
  "chart_cooldowns": [
    {
      "component": "argo-cd chart",
      "latest_eligible": "10.2.1",
      "latest_overall": "10.3.0",
      "eligible_date": "2026-08-11"
    }
  ],
  "app_dependencies": [
    {
      "app": "tests/kubernetes/sso",
      "dependency": "playwright",
      "current": "1.0.0",
      "latest_eligible": "1.1.0",
      "latest_overall": "1.1.0",
      "status_code": "update_available",
      "status_text": "update available"
    },
    {
      "app": "sites/docs",
      "dependency": "vite",
      "current": "7.0.0",
      "latest_eligible": "7.0.0",
      "latest_overall": "7.1.0",
      "eligible_date": "2026-07-14",
      "status_code": "cooldown_active",
      "status_text": "cooldown active"
    }
  ],
  "external_images": [],
  "summary": {}
}
EOF

  cat >"${PROVIDER_JSON}" <<'EOF'
{
  "format": "check-provider-version/v1",
  "providers": [
    {
      "provider": "hashicorp/helm",
      "constraint": ">= 2.0.0",
      "locked": "2.0.0",
      "latest": "2.1.0",
      "status": "update available"
    }
  ],
  "summary": {
    "outdated_count": 1,
    "error_count": 0
  }
}
EOF

  export UPDATE_VERSIONS_COMPONENT_REPORT_CMD="cat '${COMPONENT_JSON}'"
  export UPDATE_VERSIONS_PROVIDER_REPORT_CMD="cat '${PROVIDER_JSON}'"
  export UPDATE_VERSIONS_TOOL_REPORT_TSV=$'yq\tv4.0.0\tv4.1.0\tupdate_available\t'
  export UPDATE_VERSIONS_DEVCONTAINER_REPORT_TSV=$'devcontainer base\tmcr.microsoft.com/devcontainers/base:ubuntu-24.04\tmcr.microsoft.com/devcontainers/base:ubuntu-24.10\tupdate_available\t'
  export UPDATE_VERSIONS_IMAGE_REPORT_TSV=$'preload lock\tsha256:old\tsha256:new\tupdate_available\t'
  export UPDATE_VERSIONS_AUDIT_COMMANDS="true"
}

write_fake_curl() {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat >"${BATS_TEST_TMPDIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
printf '%s\n' "$*" >>"${CURL_ARGS_LOG:-/dev/null}"
cat >/dev/null
case "${url}" in
  */repos/mikefarah/yq/releases/latest)
    printf '{"tag_name":"v4.2.0","published_at":"2020-01-01T00:00:00Z"}\n'
    ;;
  */repos/kyverno/kyverno/releases/latest)
    printf '{"tag_name":"v1.99.0","published_at":"2999-01-01T00:00:00Z"}\n'
    ;;
  */repos/evilmartians/lefthook/releases/latest)
    printf '{"tag_name":"v2.2.0"}\n'
    ;;
  */repos/opentofu/opentofu/releases/latest)
    printf '{"tag_name":"v1.12.5","published_at":"2020-01-01T00:00:00Z"}\n'
    ;;
  */repos/smallstep/cli/releases/latest)
    printf '{"tag_name":"0.31.0","published_at":"2020-01-01T00:00:00Z"}\n'
    ;;
  */v2/devcontainers/base/tags/list)
    printf '{"name":"devcontainers/base","tags":["ubuntu-22.04","ubuntu-24.04","ubuntu-24.10"]}\n'
    ;;
  *)
    printf 'unexpected curl URL: %s\n' "${url}" >&2
    exit 22
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

write_toolchain_fixture() {
  export TOOLCHAIN_VERSIONS_FILE="${BATS_TEST_TMPDIR}/toolchain-versions.sh"
  export TOOLCHAIN_SOURCES_FILE="${BATS_TEST_TMPDIR}/toolchain-sources.tsv"
  cat >"${TOOLCHAIN_VERSIONS_FILE}" <<'EOF'
#!/usr/bin/env bash

KYVERNO_VERSION="${KYVERNO_VERSION:-v1.17.2}"
LEFTHOOK_VERSION="${LEFTHOOK_VERSION:-v2.1.9}"

DEVCONTAINER_ARKADE_TOOLS=(
  "yq=v4.0.0"
)
EOF
  cat >"${TOOLCHAIN_SOURCES_FILE}" <<'EOF'
yq	github:mikefarah/yq	ARKADE:yq
kyverno	github:kyverno/kyverno	KYVERNO_VERSION
lefthook	github:evilmartians/lefthook	LEFTHOOK_VERSION
EOF
}

@test "report mode lists all domains" {
  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"== tools =="* ]]
  [[ "${output}" == *"== devcontainer =="* ]]
  [[ "${output}" == *"== charts =="* ]]
  [[ "${output}" == *"== packages =="* ]]
  [[ "${output}" == *"== providers =="* ]]
  [[ "${output}" == *"== images =="* ]]
  [[ "${output}" == *"kyverno chart"* ]]
  [[ "${output}" == *"hashicorp/helm"* ]]
}

@test "cooldown blocks a too-new version and prints the eligible date" {
  run "${SCRIPT}" --execute --only packages

  [ "${status}" -eq 0 ]
  # The row names the blocked release (7.1.0), not the 7.0.0 already in use.
  [[ "${output}" == *$'sites/docs:vite\t7.0.0\t7.1.0\tBLOCKED by cooldown\t2026-07-14'* ]]
}

@test "a cooldown-held package without a reported date gets one from the blocked release" {
  jq '.app_dependencies = [{
    "app": "apps/idp-sdk",
    "dependency": "jest",
    "current": "30.3.0",
    "latest_eligible": "30.3.0",
    "latest_overall": "30.6.0",
    "status_code": "cooldown_active",
    "status_text": "cooldown active"
  }]' "${COMPONENT_JSON}" >"${COMPONENT_JSON}.tmp"
  mv "${COMPONENT_JSON}.tmp" "${COMPONENT_JSON}"

  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/http-cache"
  # Whole-second timestamps are what used to resolve to 1970-01-08.
  cat >"${BATS_TEST_TMPDIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${*: -1}" in
  https://registry.npmjs.org/jest)
    printf '{"time":{"30.3.0":"2026-03-01T00:00:00Z","30.6.0":"2026-11-20T09:30:00Z"}}\n'
    ;;
  *)
    exit 22
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"

  run env PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" HTTP_FETCH_CACHE_DIR="${BATS_TEST_TMPDIR}/http-cache" \
    "${SCRIPT}" --execute --only packages

  [ "${status}" -eq 0 ]
  # apps/idp-sdk/.npmrc sets min-release-age=7, so 2026-11-20 clears on 2026-11-27.
  [[ "${output}" == *$'apps/idp-sdk:jest\t30.3.0\t30.6.0\tBLOCKED by cooldown\t2026-11-27'* ]]
}

@test "charts report surfaces cooldown-held chart versions with eligible dates" {
  run "${SCRIPT}" --execute --only charts

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'argo-cd chart\t10.2.1\t10.3.0\tBLOCKED by cooldown\t2026-08-11'* ]]
  [[ "${output}" == *$'kyverno chart\t1.0.0\t1.1.0\tupdate available'* ]]
}

@test "--only filters domains" {
  run "${SCRIPT}" --execute --only providers

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"== providers =="* ]]
  [[ "${output}" != *"== packages =="* ]]
  [[ "${output}" != *"== charts =="* ]]
}

@test "--execute --apply invokes per-domain appliers" {
  export UPDATE_VERSIONS_TOOLS_APPLY_CMD="printf 'tools\n' >>'${CALLS}'"
  export UPDATE_VERSIONS_DEVCONTAINER_APPLY_CMD="printf 'devcontainer\n' >>'${CALLS}'"
  export UPDATE_VERSIONS_CHARTS_APPLY_CMD="printf 'charts\n' >>'${CALLS}'"
  export UPDATE_VERSIONS_PACKAGES_APPLY_CMD="printf 'packages\n' >>'${CALLS}'"
  export UPDATE_VERSIONS_PROVIDERS_APPLY_CMD="printf 'providers\n' >>'${CALLS}'"
  export UPDATE_VERSIONS_IMAGES_APPLY_CMD="printf 'images\n' >>'${CALLS}'"

  run "${SCRIPT}" --execute --apply --only tools,devcontainer,charts,packages,providers,images

  [ "${status}" -eq 0 ]
  [ "$(cat "${CALLS}")" = "$(printf 'tools\ndevcontainer\ncharts\npackages\nproviders\nimages\n')" ]
  [[ "${output}" == *"== audit verdicts =="* ]]
}

@test "a domain error yields nonzero but other domains still run" {
  export UPDATE_VERSIONS_COMPONENT_REPORT_CMD="exit 42"

  run "${SCRIPT}" --execute --only charts,providers

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"== charts =="* ]]
  [[ "${output}" == *"== providers =="* ]]
  [[ "${output}" == *"hashicorp/helm"* ]]
}

@test "--dry-run prints preview and does not run domains" {
  export UPDATE_VERSIONS_COMPONENT_REPORT_CMD="printf 'should-not-run\n'; exit 99"
  export UPDATE_VERSIONS_PROVIDER_REPORT_CMD="printf 'should-not-run\n'; exit 99"

  run "${SCRIPT}" --dry-run --only charts,providers

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: update-versions.sh"* ]]
  [[ "${output}" == *"INFO dry-run: would report available version updates across domains (charts,providers)"* ]]
  [[ "${output}" != *"== charts =="* ]]
  [[ "${output}" != *"should-not-run"* ]]
}

@test "tools resolver reports latest versions and cooldown-blocked rows" {
  write_fake_curl
  write_toolchain_fixture
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV

  run "${SCRIPT}" --execute --only tools

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'yq\tv4.0.0\tv4.2.0\tupdate available'* ]]
  [[ "${output}" == *$'kyverno\tv1.17.2\tv1.99.0\tBLOCKED by cooldown'* ]]
}

@test "tools apply rewrites eligible pins in a temp toolchain file" {
  write_fake_curl
  write_toolchain_fixture
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV

  run "${SCRIPT}" --execute --apply --only tools

  [ "${status}" -eq 0 ]
  expected=$'update-versions mode: apply\n'
  expected+=$'domains: tools\n'
  expected+=$'cooldown semantics: packages reuse js_dependency_cooldown_seconds; release resolvers use 604800 seconds\n'
  expected+=$'\n'
  expected+=$'== tools ==\n'
  expected+=$'source: .devcontainer/toolchain-versions.sh; sources: .devcontainer/toolchain-sources.tsv\n'
  expected+=$'Name\tCurrent\tLatest eligible\tStatus\tEligible date\n'
  expected+=$'yq\tv4.0.0\tv4.2.0\tupdate available\t2020-01-08\n'
  expected+=$'kyverno\tv1.17.2\tv1.99.0\tBLOCKED by cooldown\t2999-01-08\n'
  expected+=$'lefthook\tv2.1.9\tv2.2.0\tBLOCKED by unknown cooldown\tunknown\n'
  expected+=$'Updated tools: yq v4.0.0 -> v4.2.0\n'
  expected+=$'Skipped tools: kyverno latest v1.99.0 is blocked by cooldown until 2999-01-08\n'
  expected+=$'Skipped tools: lefthook latest v2.2.0 has unknown cooldown; set UPDATE_VERSIONS_ALLOW_UNKNOWN_COOLDOWN=1 to apply\n'
  expected+=$'Skipped 2 toolchain update(s) because of cooldown policy.\n'
  expected+=$'\n'
  expected+=$'== audit verdicts ==\n'
  expected+=$'Running: true\n'
  expected+=$'PASS'
  [ "${output}" = "${expected}" ]

  expected_file=$'#!/usr/bin/env bash\n'
  expected_file+=$'\n'
  expected_file+=$'KYVERNO_VERSION="${KYVERNO_VERSION:-v1.17.2}"\n'
  expected_file+=$'LEFTHOOK_VERSION="${LEFTHOOK_VERSION:-v2.1.9}"\n'
  expected_file+=$'\n'
  expected_file+=$'DEVCONTAINER_ARKADE_TOOLS=(\n'
  expected_file+=$'  "yq=v4.2.0"\n'
  expected_file+=$')'
  [ "$(cat "${TOOLCHAIN_VERSIONS_FILE}")" = "${expected_file}" ]
}

write_pin_style_fixture() {
  local opentofu_pin="$1"
  export TOOLCHAIN_VERSIONS_FILE="${BATS_TEST_TMPDIR}/toolchain-versions.sh"
  export TOOLCHAIN_SOURCES_FILE="${BATS_TEST_TMPDIR}/toolchain-sources.tsv"
  cat >"${TOOLCHAIN_VERSIONS_FILE}" <<EOF
#!/usr/bin/env bash

OPENTOFU_VERSION="\${OPENTOFU_VERSION:-${opentofu_pin}}"
STEP_VERSION="\${STEP_VERSION:-v0.30.6}"
EOF
  cat >"${TOOLCHAIN_SOURCES_FILE}" <<'EOF'
opentofu	github:opentofu/opentofu	OPENTOFU_VERSION
step	github:smallstep/cli	STEP_VERSION
EOF
}

@test "tools apply preserves each pin's leading-v style when the upstream tag differs" {
  write_fake_curl
  write_pin_style_fixture "1.12.3"
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV

  run "${SCRIPT}" --execute --apply --only tools

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'opentofu\t1.12.3\t1.12.5\tupdate available'* ]]
  [[ "${output}" == *"Updated tools: opentofu 1.12.3 -> 1.12.5"* ]]
  [[ "${output}" == *"Updated tools: step v0.30.6 -> v0.31.0"* ]]
  [[ "$(cat "${TOOLCHAIN_VERSIONS_FILE}")" == *'OPENTOFU_VERSION="${OPENTOFU_VERSION:-1.12.5}"'* ]]
  [[ "$(cat "${TOOLCHAIN_VERSIONS_FILE}")" == *'STEP_VERSION="${STEP_VERSION:-v0.31.0}"'* ]]
}

write_mise_fixture() {
  export MISE_CONFIG_FILE="${BATS_TEST_TMPDIR}/mise.toml"
  cat >"${MISE_CONFIG_FILE}" <<'EOF'
[tools]
opentofu = "1.12.3"
step = "0.30.6"

[settings]
step = "untouched"
EOF
  export MISE_CALLS="${BATS_TEST_TMPDIR}/mise-calls"
  export UPDATE_VERSIONS_MISE_CMD="${BATS_TEST_TMPDIR}/bin/mise"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  # Stands in for mise: logs each install with the data dir it was given and
  # fails opentofu the way a cosign mismatch does.
  cat >"${UPDATE_VERSIONS_MISE_CMD}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s data=%s\n' "$*" "${MISE_DATA_DIR:-unset}" >>"${MISE_CALLS}"
case "$*" in
  "install -y opentofu@1.12.5")
    printf 'mise ERROR Failed to install aqua:opentofu/opentofu@1.12.5: cosign bundle-based verification failed\n' >&2
    exit 1
    ;;
esac
exit 0
EOF
  chmod +x "${UPDATE_VERSIONS_MISE_CMD}"
}

@test "tools apply skips a mise-pinned bump that fails mise install verification" {
  write_fake_curl
  write_pin_style_fixture "1.12.3"
  write_mise_fixture
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV

  run "${SCRIPT}" --execute --apply --only tools

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Skipped tools: opentofu 1.12.5 failed mise install verification: mise ERROR Failed to install aqua:opentofu/opentofu@1.12.5: cosign bundle-based verification failed"* ]]
  [[ "${output}" != *"Updated tools: opentofu"* ]]
  [[ "${output}" == *"Skipped 1 toolchain update(s) that failed mise install verification."* ]]
  # Neither file moves for the failed tool.
  [[ "$(cat "${TOOLCHAIN_VERSIONS_FILE}")" == *'OPENTOFU_VERSION="${OPENTOFU_VERSION:-1.12.3}"'* ]]
  grep -qx 'opentofu = "1.12.3"' "${MISE_CONFIG_FILE}"
  # The install ran against a throwaway data dir, not the operator's mise.
  run grep -c 'data=unset' "${MISE_CALLS}"
  [ "${output}" = "0" ]
}

@test "tools apply keeps mise.toml in step with a verified bump" {
  write_fake_curl
  write_pin_style_fixture "1.12.3"
  write_mise_fixture
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV

  run "${SCRIPT}" --execute --apply --only tools

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Updated mise.toml: step 0.30.6 -> 0.31.0"* ]]
  [[ "${output}" == *"Updated tools: step v0.30.6 -> v0.31.0"* ]]
  [[ "$(cat "${TOOLCHAIN_VERSIONS_FILE}")" == *'STEP_VERSION="${STEP_VERSION:-v0.31.0}"'* ]]
  grep -qx 'step = "0.31.0"' "${MISE_CONFIG_FILE}"
  # Only the [tools] entry changes; a same-named key in another table stays.
  grep -qx 'step = "untouched"' "${MISE_CONFIG_FILE}"
  grep -qx 'install -y step@0.31.0 data=.*' "${MISE_CALLS}"
}

@test "tools apply can skip the mise install check when asked" {
  write_fake_curl
  write_pin_style_fixture "1.12.3"
  write_mise_fixture
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV

  run env UPDATE_VERSIONS_VERIFY_MISE_INSTALL=0 "${SCRIPT}" --execute --apply --only tools

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Updated tools: opentofu 1.12.3 -> 1.12.5"* ]]
  grep -qx 'opentofu = "1.12.5"' "${MISE_CONFIG_FILE}"
  [ ! -e "${MISE_CALLS}" ]
}

@test "tools report treats a pin as current when only the leading-v style differs from the tag" {
  write_fake_curl
  write_pin_style_fixture "1.12.5"
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV

  run "${SCRIPT}" --execute --only tools

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'opentofu\t1.12.5\t1.12.5\tcurrent'* ]]
}

@test "devcontainer domain reports a newer same-family base tag" {
  write_fake_curl
  unset UPDATE_VERSIONS_DEVCONTAINER_REPORT_TSV
  export DEVCONTAINER_DOCKERFILE="${BATS_TEST_TMPDIR}/Dockerfile"
  export DEVCONTAINER_CONFIG="${BATS_TEST_TMPDIR}/devcontainer.json"
  cat >"${DEVCONTAINER_DOCKERFILE}" <<'EOF'
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04
EOF
  cat >"${DEVCONTAINER_CONFIG}" <<'EOF'
{"features":{}}
EOF

  run "${SCRIPT}" --execute --only devcontainer

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'devcontainer base\tmcr.microsoft.com/devcontainers/base:ubuntu-24.04\tmcr.microsoft.com/devcontainers/base:ubuntu-24.10\tupdate available'* ]]
}

@test "unknown cooldown blocks tools apply unless explicitly allowed" {
  write_fake_curl
  write_toolchain_fixture
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV

  run "${SCRIPT}" --execute --apply --only tools

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Skipped tools: lefthook latest v2.2.0 has unknown cooldown"* ]]
  [[ "$(cat "${TOOLCHAIN_VERSIONS_FILE}")" == *'LEFTHOOK_VERSION="${LEFTHOOK_VERSION:-v2.1.9}"'* ]]

  export UPDATE_VERSIONS_ALLOW_UNKNOWN_COOLDOWN=1
  run "${SCRIPT}" --execute --apply --only tools

  [ "${status}" -eq 0 ]
  [[ "$(cat "${TOOLCHAIN_VERSIONS_FILE}")" == *'LEFTHOOK_VERSION="${LEFTHOOK_VERSION:-v2.2.0}"'* ]]
}

@test "tools resolver sends a bearer token to the GitHub API when GITHUB_TOKEN is set" {
  write_fake_curl
  write_toolchain_fixture
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV
  export CURL_ARGS_LOG="${BATS_TEST_TMPDIR}/curl-args.log"
  export GITHUB_TOKEN="test-token-123"

  run "${SCRIPT}" --execute --only tools

  [ "${status}" -eq 0 ]
  grep -q "Authorization: Bearer test-token-123" "${CURL_ARGS_LOG}"
}

@test "tools resolver stays anonymous when no token source is available" {
  write_fake_curl
  write_toolchain_fixture
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV
  export CURL_ARGS_LOG="${BATS_TEST_TMPDIR}/curl-args.log"
  unset GITHUB_TOKEN GH_TOKEN
  printf '#!/usr/bin/env bash\nexit 1\n' >"${BATS_TEST_TMPDIR}/bin/gh"
  chmod +x "${BATS_TEST_TMPDIR}/bin/gh"

  run "${SCRIPT}" --execute --only tools

  [ "${status}" -eq 0 ]
  grep -q "repos/mikefarah/yq/releases/latest" "${CURL_ARGS_LOG}"
  ! grep -q "Authorization" "${CURL_ARGS_LOG}"
}

@test "GitHub token is never sent to non-GitHub hosts" {
  write_fake_curl
  unset UPDATE_VERSIONS_DEVCONTAINER_REPORT_TSV
  export CURL_ARGS_LOG="${BATS_TEST_TMPDIR}/curl-args.log"
  export GITHUB_TOKEN="test-token-123"
  export DEVCONTAINER_DOCKERFILE="${BATS_TEST_TMPDIR}/Dockerfile"
  export DEVCONTAINER_CONFIG="${BATS_TEST_TMPDIR}/devcontainer.json"
  cat >"${DEVCONTAINER_DOCKERFILE}" <<'EOF'
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04
EOF
  cat >"${DEVCONTAINER_CONFIG}" <<'EOF'
{"features":{}}
EOF

  run "${SCRIPT}" --execute --only devcontainer

  [ "${status}" -eq 0 ]
  grep -q "v2/devcontainers/base/tags/list" "${CURL_ARGS_LOG}"
  ! grep "v2/devcontainers/base/tags/list" "${CURL_ARGS_LOG}" | grep -q "Authorization"
}

write_release_list_curl() {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat >"${BATS_TEST_TMPDIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
cat >/dev/null
now="$(date -u '+%s')"
# BSD date first, GNU second -- the same order scripts/update-versions.sh uses
# in date_from_epoch. `date -d` is GNU-only, and a bare one here made this the
# only file in the sweep that still assumed GNU date: the fixture died under
# set -e on macOS and took the cooldown-resolver test with it.
epoch_to_iso() {
  date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null ||
    date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'
}
# Newest release is 2 days old (still cooling); the one before it is 30 days
# old and therefore the newest cooldown-eligible version.
too_new="$(epoch_to_iso "$((now - 2 * 86400))")"
eligible="$(epoch_to_iso "$((now - 30 * 86400))")"
case "${url}" in
  */repos/mikefarah/yq/releases\?per_page=*)
    printf '[{"tag_name":"v4.9.0","published_at":"%s","prerelease":false,"draft":false},' "${too_new}"
    printf '{"tag_name":"v4.5.0","published_at":"%s","prerelease":false,"draft":false},' "${eligible}"
    printf '{"tag_name":"v4.1.0","published_at":"2020-01-01T00:00:00Z","prerelease":false,"draft":false}]\n'
    ;;
  */repos/mikefarah/yq/releases/latest)
    printf '{"tag_name":"v4.9.0","published_at":"%s"}\n' "${too_new}"
    ;;
  */releases\?per_page=*)
    printf '[]\n'
    ;;
  */repos/kyverno/kyverno/releases/latest)
    printf '{"tag_name":"v1.17.2","published_at":"2020-01-01T00:00:00Z"}\n'
    ;;
  */repos/evilmartians/lefthook/releases/latest)
    printf '{"tag_name":"v2.1.9","published_at":"2020-01-01T00:00:00Z"}\n'
    ;;
  *)
    printf 'unexpected curl URL: %s\n' "${url}" >&2
    exit 22
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

@test "tools resolver picks the newest cooldown-eligible release, not the newest overall" {
  write_release_list_curl
  write_toolchain_fixture
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV

  run "${SCRIPT}" --execute --only tools

  [ "${status}" -eq 0 ]
  # v4.9.0 is only 2 days old, so the takeable version is v4.5.0. Reporting
  # v4.9.0 here would block yq entirely despite an eligible release existing.
  [[ "${output}" == *$'yq\tv4.0.0\tv4.5.0\tupdate available'* ]]
  [[ "${output}" != *"v4.9.0"* ]]
}

@test "release timestamps without fractional seconds resolve a cooldown date" {
  # GitHub publishes "2020-01-01T00:00:00Z" with no fractional part. Appending
  # a Z unconditionally produced "...:00ZZ", which no date implementation
  # parses, so every cooldown check silently degraded to unknown.
  write_fake_curl
  write_toolchain_fixture
  unset UPDATE_VERSIONS_TOOL_REPORT_TSV

  run "${SCRIPT}" --execute --only tools

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'yq\tv4.0.0\tv4.2.0\tupdate available\t2020-01-08'* ]]
  [[ "${output}" != *$'yq\tv4.0.0\tv4.2.0\tBLOCKED by unknown cooldown'* ]]
}
