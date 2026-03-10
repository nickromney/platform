#!/usr/bin/env bash
set -euo pipefail

fail() { echo "fetch-mkcert-ca-cert: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || fail "jq not found"
command -v mkcert >/dev/null 2>&1 || fail "mkcert not found"

CAROOT="$(mkcert -CAROOT 2>/dev/null || true)"
[[ -n "${CAROOT}" ]] || fail "mkcert -CAROOT returned empty"

CA_CERT="${CAROOT}/rootCA.pem"
[[ -f "${CA_CERT}" ]] || fail "mkcert CA cert not found at ${CA_CERT}"

ca_value="$(cat "${CA_CERT}")"
[[ -n "${ca_value}" ]] || fail "mkcert CA cert at ${CA_CERT} is empty"

jq -cn --arg value "${ca_value}" '{value: $value}'
