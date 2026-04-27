#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "idp-core image contract uses uv, port 8080, non-root, and an explicit catalog path" {
  dockerfile="${REPO_ROOT}/apps/idp-core/Dockerfile"
  dockerignore="${REPO_ROOT}/apps/idp-core/.dockerignore"
  dockerfile_ignore="${dockerfile}.dockerignore"

  [ -f "${dockerfile}" ]
  [ -f "${dockerignore}" ]
  [ -f "${dockerfile_ignore}" ]

  run rg -n 'ghcr.io/astral-sh/uv|uv sync --frozen|EXPOSE 8080|USER 65532:65532|HOME=/tmp|IDP_CATALOG_PATH=/app/catalog/platform-apps.json|catalog/platform-apps.json|--port", "8080"' "${dockerfile}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ghcr.io/astral-sh/uv"* ]]
  [[ "${output}" == *"uv sync --frozen"* ]]
  [[ "${output}" == *"EXPOSE 8080"* ]]
  [[ "${output}" == *"USER 65532:65532"* ]]
  [[ "${output}" == *"HOME=/tmp"* ]]
  [[ "${output}" == *"IDP_CATALOG_PATH=/app/catalog/platform-apps.json"* ]]
  [[ "${output}" == *"catalog/platform-apps.json"* ]]
  [[ "${output}" == *"--port\", \"8080\""* ]]

  for pattern in \
    '^\*\*$' \
    '^!apps/idp-core/app/\*\*$' \
    '^!apps/idp-core/pyproject\.toml$' \
    '^!apps/idp-core/uv\.lock$' \
    '^!catalog/platform-apps\.json$'
  do
    run rg -n "${pattern}" "${dockerfile_ignore}"
    [ "${status}" -eq 0 ]
  done

  for pattern in \
    '^\.venv/$' \
    '^__pycache__/$' \
    '^\.pytest_cache/$' \
    '^\.run/$' \
    '^tests/$' \
    '^dist/$' \
    '^build/$'
  do
    run rg -n "${pattern}" "${dockerignore}"
    [ "${status}" -eq 0 ]
  done
}

@test "Backstage image contract builds with Yarn and uses a hardened DHI Node runtime" {
  dockerfile="${REPO_ROOT}/apps/backstage/Dockerfile"
  dockerignore="${REPO_ROOT}/apps/backstage/.dockerignore"

  [ -f "${dockerfile}" ]
  [ -f "${dockerignore}" ]

  run rg -n 'FROM node:22-bookworm-slim AS packages|FROM node:22-bookworm-slim AS deps|FROM node:22-bookworm-slim AS production-deps|FROM dhi\.io/node:22-debian13 AS runtime|COPY package.json yarn.lock \.yarnrc\.yml backstage\.json tsconfig\.json ./|find packages -mindepth 2 -maxdepth 2 ! -name package\.json|corepack enable|yarn install --immutable|yarn tsc|yarn build:backend|COPY --from=production-deps /usr/lib/aarch64-linux-gnu/libsqlite3\.so\.0\*|COPY --chown=1000:1000 --from=production-deps /app ./|ENV BACKSTAGE_BASE_URL=https://portal\.127\.0\.0\.1\.sslip\.io|USER 1000:1000|EXPOSE 7007' "${dockerfile}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"FROM node:22-bookworm-slim AS packages"* ]]
  [[ "${output}" == *"FROM node:22-bookworm-slim AS deps"* ]]
  [[ "${output}" == *"FROM node:22-bookworm-slim AS production-deps"* ]]
  [[ "${output}" == *"FROM dhi.io/node:22-debian13 AS runtime"* ]]
  [[ "${output}" == *"COPY package.json yarn.lock .yarnrc.yml backstage.json tsconfig.json ./"* ]]
  [[ "${output}" == *"find packages -mindepth 2 -maxdepth 2 ! -name package.json"* ]]
  [[ "${output}" == *"corepack enable"* ]]
  [[ "${output}" == *"yarn install --immutable"* ]]
  [[ "${output}" == *"yarn tsc"* ]]
  [[ "${output}" == *"yarn build:backend"* ]]
  [[ "${output}" == *"COPY --from=production-deps /usr/lib/aarch64-linux-gnu/libsqlite3.so.0"* ]]
  [[ "${output}" == *"COPY --chown=1000:1000 --from=production-deps /app ./"* ]]
  [[ "${output}" == *"ENV BACKSTAGE_BASE_URL=https://portal.127.0.0.1.sslip.io"* ]]
  [[ "${output}" == *"USER 1000:1000"* ]]
  [[ "${output}" == *"EXPOSE 7007"* ]]

  for pattern in \
    '^node_modules$' \
    '^packages/\*/node_modules$' \
    '^packages/\*/dist$' \
    '^test-results$' \
    '^playwright-report$'
  do
    run rg -n "${pattern}" "${dockerignore}"
    [ "${status}" -eq 0 ]
  done
}
