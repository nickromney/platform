#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export DOCS_CONTENT="${REPO_ROOT}/sites/docs/content"
}

@test "docs site covers current platform app surfaces" {
  [ -f "${DOCS_CONTENT}/apps/apim-simulator.mdx" ]
  [ -f "${DOCS_CONTENT}/apps/platform-mcp.mdx" ]
  [ -f "${DOCS_CONTENT}/apps/backstage-idp.mdx" ]

  run grep -R "apps/platform-mcp\\|apps/backstage\\|apps/idp-core\\|apps/idp-mcp\\|apps/idp-sdk" "${DOCS_CONTENT}/apps"
  [ "${status}" -eq 0 ]
}

@test "docs site describes current stage 800/900 observability defaults" {
  run grep -R "VictoriaLogs" "${DOCS_CONTENT}"
  [ "${status}" -eq 0 ]

  run grep -R "enable_loki = false" "${DOCS_CONTENT}"
  [ "${status}" -eq 0 ]
}

@test "docs site treats app-of-apps as optional, not the default" {
  run grep -R "app-of-apps" "${DOCS_CONTENT}"
  [ "${status}" -eq 0 ]

  run grep -R "app-of-apps.*default" "${DOCS_CONTENT}"
  [ "${status}" -ne 0 ]
}

@test "docs site has no references to removed generated media" {
  run grep -R "generated-media\\|ThemeVideo\\|media:render\\|media:still\\|media:studio" "${REPO_ROOT}/sites/docs"
  [ "${status}" -ne 0 ]
}

@test "docs site has reader paths, contracts, and footguns pages in navigation" {
  [ -f "${DOCS_CONTENT}/concepts/reader-paths.mdx" ]
  [ -f "${DOCS_CONTENT}/reference/contracts.mdx" ]
  [ -f "${DOCS_CONTENT}/operations/footguns.mdx" ]

  run grep -E "reader-paths|contracts|footguns" "${REPO_ROOT}/sites/docs/app/_meta.global.tsx"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"reader-paths"* ]]
  [[ "${output}" == *"contracts"* ]]
  [[ "${output}" == *"footguns"* ]]
}

@test "contracts page defines the platform's operational boundaries" {
  run grep -E "Operator entrypoints|Stage shape|GitOps source|Route surface|Identity|Policy|Docs media" "${DOCS_CONTENT}/reference/contracts.mdx"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Operator entrypoints"* ]]
  [[ "${output}" == *"Stage shape"* ]]
  [[ "${output}" == *"GitOps source"* ]]
  [[ "${output}" == *"Route surface"* ]]
  [[ "${output}" == *"Docs media"* ]]
}

@test "reader paths page serves beginners and experienced engineers" {
  run grep -E "TLDR For Experienced Engineers|New To This Project|New To The Technology|Daily Operators" "${DOCS_CONTENT}/concepts/reader-paths.mdx"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"TLDR For Experienced Engineers"* ]]
  [[ "${output}" == *"New To This Project"* ]]
  [[ "${output}" == *"New To The Technology"* ]]
  [[ "${output}" == *"Daily Operators"* ]]
}

@test "footguns page covers high-risk local platform mistakes" {
  run grep -E "Stage And Runtime Gotchas|Kubeconfig Gotchas|GitOps Gotchas|Image Gotchas|Route And Auth Gotchas|Policy Gotchas|Docs Gotchas" "${DOCS_CONTENT}/operations/footguns.mdx"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Stage And Runtime Gotchas"* ]]
  [[ "${output}" == *"Kubeconfig Gotchas"* ]]
  [[ "${output}" == *"GitOps Gotchas"* ]]
  [[ "${output}" == *"Route And Auth Gotchas"* ]]
  [[ "${output}" == *"Docs Gotchas"* ]]
}
