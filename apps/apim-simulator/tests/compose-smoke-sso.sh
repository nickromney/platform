#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--execute" ]]; then
  echo "usage: $0 --execute" >&2
  exit 2
fi

cleanup() {
  make -C "$(dirname "$0")/.." down >/dev/null 2>&1 || true
}
trap cleanup EXIT

make -C "$(dirname "$0")/.." up

sso_url="${APIM_SSO_URL:-http://localhost:8307}"
for _ in $(seq 1 60); do
  if curl -sSI "${sso_url}/oauth2/sign_in" >/dev/null; then
    break
  fi
  sleep 1
done

sign_in_status="$(curl -sSI "${sso_url}/oauth2/sign_in" | awk 'NR == 1 { print $2 }')"
root_status="$(curl -sSI "${sso_url}/" | awk 'NR == 1 { print $2 }')"

case "${sign_in_status}" in
  200|302|403) ;;
  *) echo "unexpected sign-in status: ${sign_in_status}" >&2; exit 1 ;;
esac

case "${root_status}" in
  302|401|403) ;;
  *) echo "unexpected gated root status: ${root_status}" >&2; exit 1 ;;
esac
