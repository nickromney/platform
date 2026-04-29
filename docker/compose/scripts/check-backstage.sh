#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Smoke-check the Docker Compose Backstage portal profile after it has started.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage \
  "would check Backstage health and portal SSO redirect in docker/compose" \
  "$@"

fail() {
  echo "FAIL $*" >&2
  exit 1
}

ok() {
  echo "OK   $*"
}

COMPOSE_COMMAND="${COMPOSE_COMMAND:-docker compose -f compose.yml --profile portal}"
PORTAL_URL="${PORTAL_URL:-https://portal.compose.127.0.0.1.sslip.io:8443}"
DEX_DEBUG_URL="${DEX_DEBUG_URL:-http://localhost:8300/dex/.well-known/openid-configuration}"
BACKSTAGE_HEALTH_URL="${BACKSTAGE_HEALTH_URL:-http://127.0.0.1:7007/api/app/health}"

export OAUTH2_PROXY_CLIENT_SECRET="${OAUTH2_PROXY_CLIENT_SECRET:-compose-oauth2-proxy-secret}"
export OAUTH2_PROXY_COOKIE_SECRET="${OAUTH2_PROXY_COOKIE_SECRET:-0123456789abcdef0123456789abcdef}"

cd "${COMPOSE_DIR}"

run_compose() {
  # COMPOSE_COMMAND is intentionally split so callers can pass "docker compose -f ...".
  # shellcheck disable=SC2086
  ${COMPOSE_COMMAND} "$@"
}

curl_tls_args=()
if command -v mkcert >/dev/null 2>&1; then
  caroot="$(mkcert -CAROOT 2>/dev/null || true)"
  if [[ -n "${caroot}" && -f "${caroot}/rootCA.pem" ]]; then
    curl_tls_args=(--cacert "${caroot}/rootCA.pem")
  fi
fi
if [[ "${#curl_tls_args[@]}" -eq 0 ]]; then
  curl_tls_args=(--insecure)
fi

wait_for_backstage_health() {
  local deadline
  deadline=$((SECONDS + 180))

  while (( SECONDS < deadline )); do
    if run_compose exec -T backstage node -e "
      fetch('${BACKSTAGE_HEALTH_URL}')
        .then(response => {
          if (!response.ok) process.exit(1);
        })
        .catch(() => process.exit(1));
    " >/dev/null 2>&1; then
      ok "Backstage backend health reachable inside compose"
      return 0
    fi
    sleep 3
  done

  run_compose ps backstage oauth2-proxy-backstage >&2 || true
  run_compose logs --tail=100 backstage oauth2-proxy-backstage >&2 || true
  fail "Backstage backend health did not become ready"
}

check_dex_discovery() {
  curl -fsS --max-time 10 "${DEX_DEBUG_URL}" >/dev/null
  ok "Dex discovery reachable: ${DEX_DEBUG_URL}"
}

check_portal_redirect() {
  local headers
  local code
  local location

  headers="$(mktemp)"
  code="$(
    curl -sS \
      "${curl_tls_args[@]}" \
      --max-time 10 \
      --output /dev/null \
      --dump-header "${headers}" \
      --write-out "%{http_code}" \
      "${PORTAL_URL}/" || true
  )"
  location="$(awk 'BEGIN{IGNORECASE=1} /^location:/ {print $0}' "${headers}" | tr -d '\r' | tail -n 1)"
  rm -f "${headers}"

  if [[ "${code}" != "302" ]]; then
    fail "expected ${PORTAL_URL}/ to redirect to Dex, got HTTP ${code}"
  fi
  if [[ "${location}" != *"https://dex.compose.127.0.0.1.sslip.io:8443/dex/auth"* ]]; then
    fail "expected portal redirect to Dex auth endpoint, got: ${location}"
  fi

  ok "Backstage portal is protected by compose SSO redirect"
}

wait_for_backstage_health
check_dex_discovery
check_portal_redirect

ok "Backstage compose smoke completed"
