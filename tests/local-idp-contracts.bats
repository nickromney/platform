#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "local IDP launch plans document portal parity and runtime portability" {
  for path in \
    docs/plans/local-idp-gap-analysis.md \
    docs/plans/local-idp-implementation-roadmap.md \
    docs/plans/local-idp-mcp-and-tui-plan.md \
    docs/plans/local-idp-runtime-portability.md
  do
    [ -f "${REPO_ROOT}/${path}" ]
  done

  run rg -n "FastAPI|Backstage|Port|MCP|SDK|runtime adapter|16GB|Terraform" "${REPO_ROOT}/docs/plans/local-idp-"*.md
  [ "${status}" -eq 0 ]
}

@test "IDP contract schemas exist for portal API and automation payloads" {
  for schema in \
    catalog.schema.json \
    status.schema.json \
    action.schema.json \
    deployment.schema.json \
    secret-binding.schema.json \
    scorecard.schema.json \
    environment-request.schema.json \
    runtime.schema.json \
    audit-event.schema.json
  do
    run jq -e '.["$schema"] and .title and .type' "${REPO_ROOT}/schemas/idp/${schema}"
    [ "${status}" -eq 0 ]
  done
}

@test "catalog validates against the local IDP catalog schema" {
  run python3 "${REPO_ROOT}/scripts/validate-json-schema.py" \
    "${REPO_ROOT}/schemas/idp/catalog.schema.json" \
    "${REPO_ROOT}/catalog/platform-apps.json"

  [ "${status}" -eq 0 ]
}

@test "kind and lima expose Portal API Backstage SDK and MCP targets" {
  run make -C "${REPO_ROOT}/kubernetes/kind" help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make idp-api"* ]]
  [[ "${output}" == *"make backstage"* ]]
  [[ "${output}" == *"make idp-sdk"* ]]
  [[ "${output}" == *"make idp-mcp"* ]]

  run make -C "${REPO_ROOT}/kubernetes/lima" help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make idp-api"* ]]
  [[ "${output}" == *"make backstage"* ]]
  [[ "${output}" == *"make idp-sdk"* ]]
  [[ "${output}" == *"make idp-mcp"* ]]
}

@test "IDP Make targets are dry-run friendly and do not apply infrastructure" {
  for target in idp-api backstage idp-sdk idp-mcp; do
    run make -C "${REPO_ROOT}/kubernetes/kind" "${target}" DRY_RUN=1
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"would"* ]]

    run make -C "${REPO_ROOT}/kubernetes/lima" "${target}" DRY_RUN=1
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"would"* ]]
  done
}

@test "IDP operator surfaces advertise HTTPS sslip.io endpoints" {
  run make -C "${REPO_ROOT}/kubernetes/kind" idp-api DRY_RUN=1
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"https://portal-api.127.0.0.1.sslip.io"* ]]

  run make -C "${REPO_ROOT}/kubernetes/kind" backstage DRY_RUN=1
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"https://portal.127.0.0.1.sslip.io"* ]]

  run make -C "${REPO_ROOT}/kubernetes/lima" idp-api DRY_RUN=1
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"https://portal-api.127.0.0.1.sslip.io"* ]]

  run make -C "${REPO_ROOT}/kubernetes/lima" backstage DRY_RUN=1
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"https://portal.127.0.0.1.sslip.io"* ]]
}

@test "new IDP packages follow dependency cooldown and pinning guardrails" {
  run rg -n '^min-release-age=7$' "${REPO_ROOT}/apps/idp-sdk/.npmrc"
  [ "${status}" -eq 0 ]

  run jq -e '.packageManager == "yarn@4.4.1"' "${REPO_ROOT}/apps/backstage/package.json"
  [ "${status}" -eq 0 ]

  [ -f "${REPO_ROOT}/apps/backstage/.yarn/releases/yarn-4.4.1.cjs" ]
  [ -f "${REPO_ROOT}/apps/backstage/yarn.lock" ]

  run jq -e '.packageManager == "npm@11.12.1"' "${REPO_ROOT}/apps/idp-sdk/package.json"
  [ "${status}" -eq 0 ]

  run rg -n 'exclude-newer = "7 days"' \
    "${REPO_ROOT}/apps/idp-core/pyproject.toml" \
    "${REPO_ROOT}/apps/idp-mcp/pyproject.toml"
  [ "${status}" -eq 0 ]
}

@test "DDD language distinguishes the IDP from developer portal surfaces" {
  glossary="${REPO_ROOT}/docs/ddd/ubiquitous-language.md"

  for term in \
    "internal developer platform" \
    "developer portal" \
    "portal API" \
    "runtime adapter" \
    "portal.127.0.0.1.sslip.io" \
    "portal-api.127.0.0.1.sslip.io"
  do
    run rg -n "${term}" "${glossary}"
    [ "${status}" -eq 0 ]
  done
}
