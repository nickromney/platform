#!/usr/bin/env sh

set -eu

TEMPLATE=/opt/keycloak/local/realm-export.template.json
OUTPUT=/opt/keycloak/data/import/realm-export.json

usage() {
  cat <<'EOF'
Usage: start-with-templated-realm.sh [--dry-run] [--execute]

Renders the local Keycloak realm template with runtime secrets and starts
Keycloak in development mode with realm import enabled.

Options:
  --dry-run  Show a summary and exit before side effects
  --execute  Execute the script body; without it the script prints help and/or preview output
  --shell-entrypoint-descriptor
             Print machine-readable entrypoint contract metadata
  -h, --help Show this message
EOF
}

descriptor() {
  printf '{"schema_version":"shell-entrypoint/v1","name":"start-with-templated-realm.sh","path":"%s","supports":["--help","--dry-run","--execute"],"default_mode":"dry-run"}\n' "$0"
}

dry_run=0
execute=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --execute)
      execute=1
      shift
      ;;
    --shell-entrypoint-descriptor)
      descriptor
      exit 0
      ;;
    *)
      printf 'start-with-templated-realm.sh: unrecognized argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "${dry_run}" -eq 1 ]; then
  printf 'INFO dry-run: would render %s from %s and start Keycloak\n' "${OUTPUT}" "${TEMPLATE}"
  exit 0
fi

if [ "${execute}" -ne 1 ]; then
  usage
  printf 'INFO dry-run: would render %s from %s and start Keycloak\n' "${OUTPUT}" "${TEMPLATE}"
  exit 0
fi

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
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

client_secret_escaped=$(escape_sed_replacement "$OAUTH2_PROXY_CLIENT_SECRET")
demo_password_escaped=$(escape_sed_replacement "$KEYCLOAK_DEMO_PASSWORD")

sed \
  -e "s|\${OAUTH2_PROXY_CLIENT_SECRET}|$client_secret_escaped|g" \
  -e "s|\${KEYCLOAK_DEMO_PASSWORD}|$demo_password_escaped|g" \
  "$TEMPLATE" >"$OUTPUT"

exec /opt/keycloak/bin/kc.sh start-dev --import-realm
