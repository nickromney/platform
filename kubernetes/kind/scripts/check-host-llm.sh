#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }
warn() { echo "WARN $*"; }

usage() {
  cat <<'EOF'
Usage: check-host-llm.sh [--var-file PATH]...

Checks whether the host-side LLM endpoint required by the direct sentiment
gateway path appears to be available.
EOF
}

TFVARS_FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file)
      [[ $# -ge 2 ]] || fail "--var-file requires a path"
      TFVARS_FILES+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

tfvar_value() {
  local key="$1"
  local fallback="$2"
  local file
  local value=""

  for file in "${TFVARS_FILES[@]}"; do
    [[ -f "${file}" ]] || continue
    local match_line
    match_line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 || true)"
    [[ -n "${match_line}" ]] || continue
    value="$(
      printf '%s\n' "${match_line}" | \
        sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | \
        xargs || true
    )"
  done

  if [[ -z "${value}" ]]; then
    value="${fallback}"
  fi

  printf '%s\n' "${value}"
}

probe_url() {
  local url="$1"
  local body_file="$2"
  curl -sS -m 3 -o "${body_file}" -w '%{http_code}' "${url}" 2>/dev/null || true
}

classify_v1_models() {
  local body_file="$1"

  if jq -e '.data | type == "array"' "${body_file}" >/dev/null 2>&1; then
    if jq -e '.data[]? | select(.owned_by == "docker")' "${body_file}" >/dev/null 2>&1; then
      printf 'Docker Desktop model runner'
      return 0
    fi
    printf 'OpenAI-compatible model endpoint'
    return 0
  fi

  return 1
}

classify_ollama_tags() {
  local body_file="$1"

  if jq -e '.models | type == "array"' "${body_file}" >/dev/null 2>&1; then
    printf 'Ollama-compatible model endpoint'
    return 0
  fi

  return 1
}

main() {
  command -v curl >/dev/null 2>&1 || fail "curl not found in PATH"
  command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"

  local mode host probe_host port body_file code description
  mode="$(tfvar_value llm_gateway_mode litellm)"
  host="$(tfvar_value llm_gateway_external_name host.docker.internal)"
  port="${LLM_HOST_PORT:-12434}"

  if [[ "${mode}" != "direct" ]]; then
    ok "host-side LLM check skipped (llm_gateway_mode=${mode})"
    return 0
  fi

  probe_host="${host}"
  if [[ "${host}" == "host.docker.internal" ]]; then
    probe_host="127.0.0.1"
  fi

  body_file="$(mktemp)"
  trap 'rm -f "${body_file}"' RETURN

  code="$(probe_url "http://${probe_host}:${port}/v1/models" "${body_file}")"
  if [[ "${code}" == "200" ]]; then
    if description="$(classify_v1_models "${body_file}")"; then
      ok "host-side LLM endpoint detected at ${probe_host}:${port} (${description})"
      return 0
    fi
    ok "host-side LLM endpoint detected at ${probe_host}:${port} (responded to /v1/models)"
    return 0
  fi

  code="$(probe_url "http://${probe_host}:${port}/api/tags" "${body_file}")"
  if [[ "${code}" == "200" ]]; then
    if description="$(classify_ollama_tags "${body_file}")"; then
      ok "host-side LLM endpoint detected at ${probe_host}:${port} (${description})"
      return 0
    fi
    ok "host-side LLM endpoint detected at ${probe_host}:${port} (responded to /api/tags)"
    return 0
  fi

  code="$(probe_url "http://${probe_host}:${port}/engines" "${body_file}")"
  case "${code}" in
    200|301|302|307|308|401|403|404)
      warn "host-side LLM endpoint responded at ${probe_host}:${port}, but did not expose /v1/models or /api/tags cleanly"
      return 0
      ;;
  esac

  fail "host-side LLM endpoint not detected at ${probe_host}:${port} for llm_gateway_mode=direct"
}

main "$@"
