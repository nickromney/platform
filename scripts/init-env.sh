#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"
ENV_EXAMPLE_FILE="${ENV_EXAMPLE_FILE:-${REPO_ROOT}/.env.example}"
OPENSSL_BIN="${OPENSSL_BIN:-openssl}"

# Every key here hard-fails a stage when left empty, which is exactly the
# onboarding trap this script exists to remove: copying .env.example by hand
# leaves them blank and the failure surfaces much later, during stage 100.
GENERATED_KEYS=(
  PLATFORM_ADMIN_PASSWORD
  PLATFORM_DEMO_PASSWORD
  OAUTH2_PROXY_COOKIE_SECRET
)

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Create ${ENV_FILE##*/} from ${ENV_EXAMPLE_FILE##*/}, generating the local demo
credentials that the example file cannot ship with values.

Existing values are never overwritten: re-running only fills keys that are
present but empty, so this is safe to run against an already-configured .env.

$(shell_cli_standard_options)
EOF
}

fail() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}

# oauth2-proxy requires a 32-byte secret; it is supplied base64-encoded, and the
# URL-safe alphabet avoids '+' and '/' surviving into cookie and header values.
generate_secret() {
  if command -v "${OPENSSL_BIN}" >/dev/null 2>&1; then
    "${OPENSSL_BIN}" rand -base64 32 | tr '+/' '-_'
    return 0
  fi

  if command -v uv >/dev/null 2>&1; then
    uv run --isolated python -c \
      'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())'
    return 0
  fi

  fail "neither ${OPENSSL_BIN} nor uv is available to generate a secret"
}

key_value_in_file() {
  local key="$1"
  local file="$2"

  [[ -f "${file}" ]] || return 1
  KEY="${key}" awk -F= '
    $1 == ENVIRON["KEY"] {
      sub(/^[^=]*=/, "", $0)
      print $0
      found = 1
      exit
    }
    END { exit(found ? 0 : 1) }
  ' "${file}"
}

set_key_value() {
  local key="$1"
  local value="$2"
  local file="$3"
  local tmp

  tmp="$(mktemp "${file}.XXXXXX")"
  KEY="${key}" VALUE="${value}" awk '
    BEGIN { key = ENVIRON["KEY"]; value = ENVIRON["VALUE"] }
    {
      split($0, parts, "=")
      if (parts[1] == key) {
        printf "%s=%s\n", key, value
      } else {
        print $0
      }
    }
  ' "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
}

main() {
  [[ -f "${ENV_EXAMPLE_FILE}" ]] || fail "missing ${ENV_EXAMPLE_FILE}"

  local created=0
  if [[ ! -f "${ENV_FILE}" ]]; then
    cp "${ENV_EXAMPLE_FILE}" "${ENV_FILE}"
    # The file carries local credentials and must never be world-readable.
    chmod 600 "${ENV_FILE}"
    created=1
    printf 'Created %s from %s\n' "${ENV_FILE}" "${ENV_EXAMPLE_FILE}"
  else
    printf 'Keeping existing %s\n' "${ENV_FILE}"
  fi

  local key current filled=0 kept=0
  for key in "${GENERATED_KEYS[@]}"; do
    if ! current="$(key_value_in_file "${key}" "${ENV_FILE}")"; then
      printf '%s=%s\n' "${key}" "$(generate_secret)" >>"${ENV_FILE}"
      printf 'Added %s with a generated value\n' "${key}"
      filled=$((filled + 1))
      continue
    fi

    if [[ -z "${current}" ]]; then
      set_key_value "${key}" "$(generate_secret)" "${ENV_FILE}"
      printf 'Generated %s\n' "${key}"
      filled=$((filled + 1))
    else
      printf 'Kept existing %s\n' "${key}"
      kept=$((kept + 1))
    fi
  done

  printf '\n%s ready: %d generated, %d preserved\n' \
    "${ENV_FILE}" "${filled}" "${kept}"

  if [[ "${created}" -eq 1 ]]; then
    printf 'Review the file before running make -C kubernetes/kind apply.\n'
  fi
}

shell_cli_handle_standard_no_args \
  usage \
  "would create ${ENV_FILE} from ${ENV_EXAMPLE_FILE} and generate any empty local credentials" \
  "$@"

main
