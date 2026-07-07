#!/usr/bin/env bash
set -euo pipefail

CREDS_FILE="${PLATFORM_DOCKER_CREDS_FILE:-${HOME}/.config/platform/docker-creds.json}"

usage() {
  cat <<'EOF' >&2
Usage: docker-credential-platform-file <get|store|erase|list>

Docker credential-helper protocol implementation backed by:
  ${PLATFORM_DOCKER_CREDS_FILE:-$HOME/.config/platform/docker-creds.json}

This helper is intended for dhi.io pull-only mirror credentials.
EOF
}

fail() {
  printf 'docker-credential-platform-file: %s\n' "$*" >&2
  exit 1
}

require_jq() {
  command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
}

ensure_store() {
  local dir=""

  dir="$(dirname "${CREDS_FILE}")"
  mkdir -p "${dir}"
  chmod 700 "${dir}" 2>/dev/null || true

  if [[ ! -f "${CREDS_FILE}" ]]; then
    umask 077
    printf '{}\n' >"${CREDS_FILE}"
  fi
  chmod 600 "${CREDS_FILE}"
}

validate_store() {
  if [[ -f "${CREDS_FILE}" ]]; then
    jq -e 'type == "object"' "${CREDS_FILE}" >/dev/null
  fi
}

write_store() {
  local tmp=""

  tmp="$(mktemp "${CREDS_FILE}.XXXXXX")"
  cat >"${tmp}"
  chmod 600 "${tmp}"
  mv "${tmp}" "${CREDS_FILE}"
}

read_stdin() {
  cat
}

normalize_server() {
  local server="$1"
  printf '%s\n' "${server}" | sed 's/[[:space:]]*$//'
}

credential_key_filter() {
  cat <<'EOF'
def candidates($server):
  [
    $server,
    ($server | sub("^https://"; "")),
    ($server | sub("^https://"; "") | sub("/$"; "")),
    ("https://" + ($server | sub("^https://"; "") | sub("/$"; ""))),
    ("https://" + ($server | sub("^https://"; "") | sub("/$"; "")) + "/")
  ] | unique;
candidates($server)[] as $key
| select(.[$key] != null)
| $key
EOF
}

cmd_get() {
  local server=""
  local key=""

  server="$(normalize_server "$(read_stdin)")"
  [[ -n "${server}" ]] || exit 1
  [[ -f "${CREDS_FILE}" ]] || exit 1
  validate_store || fail "credential file is not valid JSON: ${CREDS_FILE}"

  key="$(jq -r --arg server "${server}" "$(credential_key_filter)" "${CREDS_FILE}" | head -n 1)"
  [[ -n "${key}" ]] || exit 1

  jq -c --arg key "${key}" '.[$key] | {Username: .Username, Secret: .Secret}' "${CREDS_FILE}"
}

cmd_store() {
  local payload=""
  local server=""

  ensure_store
  validate_store || fail "credential file is not valid JSON: ${CREDS_FILE}"

  payload="$(read_stdin)"
  server="$(printf '%s' "${payload}" | jq -r '.ServerURL // empty')"
  [[ -n "${server}" ]] || fail "store payload missing ServerURL"
  printf '%s' "${payload}" |
    jq -e '.Username != null and .Secret != null' >/dev/null ||
    fail "store payload missing Username or Secret"

  jq --arg server "${server}" --argjson credential "${payload}" \
    '.[$server] = {Username: $credential.Username, Secret: $credential.Secret}' \
    "${CREDS_FILE}" | write_store
}

cmd_erase() {
  local server=""

  ensure_store
  validate_store || fail "credential file is not valid JSON: ${CREDS_FILE}"
  server="$(normalize_server "$(read_stdin)")"
  [[ -n "${server}" ]] || exit 0

  jq --arg server "${server}" '
    def candidates($server):
      [
        $server,
        ($server | sub("^https://"; "")),
        ($server | sub("^https://"; "") | sub("/$"; "")),
        ("https://" + ($server | sub("^https://"; "") | sub("/$"; ""))),
        ("https://" + ($server | sub("^https://"; "") | sub("/$"; "")) + "/")
      ] | unique;
    reduce candidates($server)[] as $key (. ; del(.[$key]))
  ' "${CREDS_FILE}" | write_store
}

cmd_list() {
  if [[ ! -f "${CREDS_FILE}" ]]; then
    printf '{}\n'
    return 0
  fi
  validate_store || fail "credential file is not valid JSON: ${CREDS_FILE}"
  jq -c 'with_entries(.value = (.value.Username // ""))' "${CREDS_FILE}"
}

require_jq
case "${1:-}" in
  get)
    cmd_get
    ;;
  store)
    cmd_store
    ;;
  erase)
    cmd_erase
    ;;
  list)
    cmd_list
    ;;
  -h|--help|"")
    usage
    exit 1
    ;;
  *)
    usage
    exit 1
    ;;
esac
