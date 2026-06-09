#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "Backstage portal SDK and MCP surfaces exist with an HTTP API boundary" {
  for path in \
    apps/backstage/package.json \
    apps/backstage/app-config.production.yaml \
    apps/backstage/catalog/entities.yaml \
    apps/backstage/catalog/templates/platform-service/template.yaml \
    apps/idp-sdk/package.json \
    apps/idp-sdk/src/index.ts \
    apps/idp-mcp/go.mod \
    apps/idp-mcp/cmd/idp-mcp/main.go
  do
    [ -f "${REPO_ROOT}/${path}" ]
  done

  run rg -n 'Backstage|scaffolder|catalog|Template|platform-service-request|portal-api\.127\.0\.0\.1\.sslip\.io|backstage' "${REPO_ROOT}/apps/backstage"
  [ "${status}" -eq 0 ]

  run rg -n 'class IdpClient|fetch\(|listApps|getRuntime|/api/v1/catalog/apps|/api/v1/environments|/api/v1/deployments/promote' "${REPO_ROOT}/apps/idp-sdk/src/index.ts"
  [ "${status}" -eq 0 ]

  for path in \
    apps/idp-sdk/src/index.ts
  do
    run rg -n 'credentials: "include"' "${REPO_ROOT}/${path}"
    [ "${status}" -eq 0 ]
  done

  run rg -n 'IDP_API_BASE_URL|http.NewRequest|platform_status|catalog_list|environment_create|/api/v1/catalog/apps|/api/v1/environments' "${REPO_ROOT}/apps/idp-mcp/cmd/idp-mcp/main.go"
  [ "${status}" -eq 0 ]
}

@test "IDP SDK, MCP, and Backstage default to public portal HTTPS FQDNs" {
  run rg -n 'DEFAULT_IDP_API_BASE_URL = "https://portal-api\.127\.0\.0\.1\.sslip\.io"' "${REPO_ROOT}/apps/idp-sdk/src/index.ts"
  [ "${status}" -eq 0 ]

  run rg -n 'https://portal-api\.127\.0\.0\.1\.sslip\.io|https://portal\.127\.0\.0\.1\.sslip\.io' "${REPO_ROOT}/apps/backstage"
  [ "${status}" -eq 0 ]

  run rg -n 'defaultIDPAPIBaseURL = "https://portal-api\.127\.0\.0\.1\.sslip\.io"' "${REPO_ROOT}/apps/idp-mcp/cmd/idp-mcp/main.go"
  [ "${status}" -eq 0 ]

  run rg -n 'Developer Portal|Portal API' \
    "${REPO_ROOT}/apps/backstage" \
    "${REPO_ROOT}/terraform/kubernetes/config/platform-launchpad.apps.json" \
    "${REPO_ROOT}/catalog/platform-apps.json"
  [ "${status}" -eq 0 ]
}

@test "IDP MCP wrapper calls HTTP APIs rather than direct operator scripts" {
  run rg -n 'subprocess|os\\.system|Popen|kubectl|make -C|scripts/' \
    "${REPO_ROOT}/apps/idp-sdk" \
    "${REPO_ROOT}/apps/idp-mcp"
  [ "${status}" -ne 0 ]

  run rg -n 'exec\\.Command|os\\.System|kubectl|make -C|scripts/' "${REPO_ROOT}/apps/idp-mcp"
  [ "${status}" -ne 0 ]

  run rg -n 'http.NewRequest|POST|GET|client.Do' "${REPO_ROOT}/apps/idp-mcp/cmd/idp-mcp/main.go"

  [ "${status}" -eq 0 ]
}

@test "IDP SDK and MCP share named API path registries" {
  run rg -n 'IDP_API_PATHS|/api/v1/runtime|/api/v1/status|/api/v1/catalog/apps|/api/v1/environments|/api/v1/deployments/promote' "${REPO_ROOT}/apps/idp-sdk/src/index.ts"
  [ "${status}" -eq 0 ]

  run rg -n 'idpAPIPaths|/api/v1/runtime|/api/v1/status|/api/v1/catalog/apps|/api/v1/environments|/api/v1/deployments/promote' "${REPO_ROOT}/apps/idp-mcp/cmd/idp-mcp/main.go"
  [ "${status}" -eq 0 ]
}
