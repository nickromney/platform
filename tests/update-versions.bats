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
  export UPDATE_VERSIONS_IMAGE_REPORT_TSV=$'preload lock\tsha256:old\tsha256:new\tupdate_available\t'
  export UPDATE_VERSIONS_AUDIT_COMMANDS="true"
}

@test "report mode lists all domains" {
  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"== tools =="* ]]
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

@test "--only filters domains" {
  run "${SCRIPT}" --execute --only providers

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"== providers =="* ]]
  [[ "${output}" != *"== packages =="* ]]
  [[ "${output}" != *"== charts =="* ]]
}

@test "--execute --apply invokes per-domain appliers" {
  export UPDATE_VERSIONS_TOOLS_APPLY_CMD="printf 'tools\n' >>'${CALLS}'"
  export UPDATE_VERSIONS_CHARTS_APPLY_CMD="printf 'charts\n' >>'${CALLS}'"
  export UPDATE_VERSIONS_PACKAGES_APPLY_CMD="printf 'packages\n' >>'${CALLS}'"
  export UPDATE_VERSIONS_PROVIDERS_APPLY_CMD="printf 'providers\n' >>'${CALLS}'"
  export UPDATE_VERSIONS_IMAGES_APPLY_CMD="printf 'images\n' >>'${CALLS}'"

  run "${SCRIPT}" --execute --apply --only tools,charts,packages,providers,images

  [ "${status}" -eq 0 ]
  [ "$(cat "${CALLS}")" = "$(printf 'tools\ncharts\npackages\nproviders\nimages\n')" ]
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
