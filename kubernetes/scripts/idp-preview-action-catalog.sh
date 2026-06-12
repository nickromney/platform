#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  idp-preview-action-catalog.sh --targets
  idp-preview-action-catalog.sh --records
  idp-preview-action-catalog.sh --label TARGET
  idp-preview-action-catalog.sh --dry-run-message TARGET --runtime RUNTIME --idp-public-url URL --idp-api-public-url URL
  idp-preview-action-catalog.sh --run-command TARGET --runtime RUNTIME --repo-root PATH --idp-public-url URL --idp-api-public-url URL
USAGE
}

catalog_records() {
  printf '%s\t%s\n' 'idp-api' 'IDP API preview'
  printf '%s\t%s\n' 'backstage' 'Backstage preview'
  printf '%s\t%s\n' 'idp-sdk' 'IDP SDK preview'
  printf '%s\t%s\n' 'idp-mcp' 'IDP MCP preview'
}

target_label() {
  local target="$1"
  local catalog_target=""
  local label=""

  while IFS=$'\t' read -r catalog_target label; do
    if [ "${catalog_target}" = "${target}" ]; then
      printf '%s\n' "${label}"
      return 0
    fi
  done < <(catalog_records)

  printf 'Unknown IDP preview target: %s\n' "${target}" >&2
  return 1
}

dry_run_message() {
  local target="$1"
  local runtime="$2"
  local idp_public_url="$3"
  local idp_api_public_url="$4"

  case "${target}" in
    idp-api)
      printf 'INFO dry-run: would expose Go IDP core for %s at %s\n' "${runtime}" "${idp_api_public_url}"
      ;;
    backstage)
      printf 'INFO dry-run: would expose Backstage developer portal for %s at %s\n' "${runtime}" "${idp_public_url}"
      ;;
    idp-sdk)
      printf 'INFO dry-run: would generate IDP SDK from FastAPI OpenAPI for %s\n' "${runtime}"
      ;;
    idp-mcp)
      printf 'INFO dry-run: would start IDP MCP server for %s against %s\n' "${runtime}" "${idp_api_public_url}"
      ;;
    *)
      printf 'Unknown IDP preview target: %s\n' "${target}" >&2
      return 1
      ;;
  esac
}

run_command() {
  local target="$1"
  local runtime="$2"
  local repo_root="$3"
  local idp_public_url="$4"
  local idp_api_public_url="$5"

  case "${target}" in
    idp-api)
      printf 'Run: cd %s/apps/idp-core/app && IDP_RUNTIME=%s IDP_PUBLIC_URL=%s IDP_API_PUBLIC_URL=%s IDP_CATALOG_PATH=%s/catalog/platform-apps.json go run ./cmd/idp-core\n' \
        "${repo_root}" "${runtime}" "${idp_public_url}" "${idp_api_public_url}" "${repo_root}"
      ;;
    backstage)
      printf 'Run: cd %s/apps/backstage && docker build -t platform/backstage:dev -f Dockerfile . && docker run --rm -p 7007:7007 -e BACKSTAGE_BASE_URL=http://127.0.0.1:7007 platform/backstage:dev\n' "${repo_root}"
      ;;
    idp-sdk)
      printf 'Run: cd %s/apps/idp-sdk && npm test\n' "${repo_root}"
      ;;
    idp-mcp)
      printf 'Run: cd %s/apps/idp-mcp && IDP_API_BASE_URL=%s go run ./cmd/idp-mcp\n' "${repo_root}" "${idp_api_public_url}"
      ;;
    *)
      printf 'Unknown IDP preview target: %s\n' "${target}" >&2
      return 1
      ;;
  esac
}

mode=""
target=""
runtime=""
repo_root=""
idp_public_url=""
idp_api_public_url=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --targets|--records)
      mode="${1#--}"
      shift
      ;;
    --label|--dry-run-message|--run-command)
      mode="${1#--}"
      target="${2:-}"
      shift 2
      ;;
    --runtime)
      runtime="${2:-}"
      shift 2
      ;;
    --repo-root)
      repo_root="${2:-}"
      shift 2
      ;;
    --idp-public-url)
      idp_public_url="${2:-}"
      shift 2
      ;;
    --idp-api-public-url)
      idp_api_public_url="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "${mode}" in
  targets)
    catalog_records | cut -f1
    ;;
  records)
    catalog_records
    ;;
  label)
    target_label "${target}"
    ;;
  dry-run-message)
    dry_run_message "${target}" "${runtime}" "${idp_public_url}" "${idp_api_public_url}"
    ;;
  run-command)
    run_command "${target}" "${runtime}" "${repo_root}" "${idp_public_url}" "${idp_api_public_url}"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
