#!/usr/bin/env sh

set -eu

TEMPLATE=/opt/keycloak/local/realm-export.template.json
OUTPUT=/opt/keycloak/data/import/realm-export.json

if [ ! -f "$TEMPLATE" ]; then
  echo "Missing realm template: $TEMPLATE" >&2
  exit 1
fi

if [ -z "${OAUTH2_PROXY_CLIENT_SECRET:-}" ]; then
  echo "Missing env var: OAUTH2_PROXY_CLIENT_SECRET" >&2
  exit 1
fi

if [ -z "${KEYCLOAK_DEMO_PASSWORD:-}" ]; then
  echo "Missing env var: KEYCLOAK_DEMO_PASSWORD" >&2
  exit 1
fi

mkdir -p /opt/keycloak/data/import

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&/]/\\\\&/g'
}

client_secret_escaped=$(escape_sed_replacement "$OAUTH2_PROXY_CLIENT_SECRET")
demo_password_escaped=$(escape_sed_replacement "$KEYCLOAK_DEMO_PASSWORD")

sed \
  -e "s|\\${OAUTH2_PROXY_CLIENT_SECRET}|$client_secret_escaped|g" \
  -e "s|\\${KEYCLOAK_DEMO_PASSWORD}|$demo_password_escaped|g" \
  "$TEMPLATE" >"$OUTPUT"

exec /opt/keycloak/bin/kc.sh start-dev --import-realm
