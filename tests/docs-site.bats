#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export DOCS_SITE="${REPO_ROOT}/sites/docs"
}

@test "docs site lives under sites/docs with source content" {
  [ -d "${DOCS_SITE}" ]
  [ -f "${DOCS_SITE}/package.json" ]
  [ -f "${DOCS_SITE}/README.md" ]
  [ -d "${DOCS_SITE}/content" ]
  [ -d "${DOCS_SITE}/diagrams/d2" ]
}

@test "docs site import excludes build artifacts and vendored dependencies" {
  [ ! -d "${DOCS_SITE}/.git" ]
  [ ! -d "${DOCS_SITE}/.next" ]
  [ ! -d "${DOCS_SITE}/node_modules" ]
  [ ! -d "${DOCS_SITE}/.run" ]
  [ ! -d "${DOCS_SITE}/.playwright-mcp" ]
  [ ! -f "${DOCS_SITE}/tsconfig.tsbuildinfo" ]
}

@test "docs site does not carry generated video outputs" {
  run find "${DOCS_SITE}" -type f \( -name '*.mp4' -o -name '*.mov' -o -name '*.webm' \) -print
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "docs site non-text assets are D2 SVGs or app chrome" {
  run find "${DOCS_SITE}" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.gif' \) -print
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "docs site keeps D2 sources and excludes Remotion source by default" {
  run find "${DOCS_SITE}/diagrams/d2" -type f -name '*.d2' -print
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]

  [ ! -d "${DOCS_SITE}/remotion" ]
  [ ! -f "${DOCS_SITE}/remotion.config.ts" ]
}

@test "docs site has validation scripts for content and diagrams" {
  run grep -E '"(lint:content|test:docs|check:d2|typecheck|build)"' "${DOCS_SITE}/package.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"lint:content"'* ]]
  [[ "${output}" == *'"test:docs"'* ]]
  [[ "${output}" == *'"check:d2"'* ]]
  [[ "${output}" == *'"typecheck"'* ]]
  [[ "${output}" == *'"build"'* ]]
}

@test "docs Makefile build installs dependencies from a clean checkout" {
  rm -rf "${DOCS_SITE}/node_modules" "${DOCS_SITE}/.next" "${DOCS_SITE}/tsconfig.tsbuildinfo"

  run make -C "${DOCS_SITE}" build

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"bun install"* ]]
  [[ "${output}" == *"bun run build"* ]]
  [ -f "${DOCS_SITE}/node_modules/.bun-install.stamp" ]
  [ -d "${DOCS_SITE}/.next" ]

  rm -rf "${DOCS_SITE}/node_modules" "${DOCS_SITE}/.next" "${DOCS_SITE}/tsconfig.tsbuildinfo"
}
