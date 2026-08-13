#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/update-versions.sh"
  export COMPONENT_JSON="${BATS_TEST_TMPDIR}/components.json"
  export PROVIDER_JSON="${BATS_TEST_TMPDIR}/providers.json"
  export CALLS="${BATS_TEST_TMPDIR}/calls"

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
  [[ "${output}" == *"sites/docs:vite"* ]]
  [[ "${output}" == *"BLOCKED by cooldown"* ]]
  [[ "${output}" == *"2026-07-14"* ]]
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
# Newest release is 2 days old (still cooling); the one before it is 30 days
# old and therefore the newest cooldown-eligible version.
too_new="$(date -u -d "@$((now - 2 * 86400))" '+%Y-%m-%dT%H:%M:%SZ')"
eligible="$(date -u -d "@$((now - 30 * 86400))" '+%Y-%m-%dT%H:%M:%SZ')"
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
