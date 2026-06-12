#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: make-known-goals.sh --dir <dir> [--database-out <path>] --execute

Print evaluated MAKE_KNOWN_GOALS for a Makefile directory without running
recipes. When --database-out is provided, also write the evaluated make
database to that path.
USAGE
}

make_dir=""
database_out=""
execute=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      make_dir="${2:-}"
      shift 2
      ;;
    --database-out)
      database_out="${2:-}"
      shift 2
      ;;
    --execute)
      execute=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 64
      ;;
  esac
done

if [ "${execute}" -ne 1 ] || [ -z "${make_dir}" ]; then
  usage >&2
  exit 64
fi

tmp_dir="${TMPDIR:-/tmp}/platform-make-known-goals.$$"
mkdir -p "${tmp_dir}"
trap 'rm -rf "${tmp_dir}"' EXIT

env_file="${tmp_dir}/platform.env"
cat >"${env_file}" <<'EOF'
PLATFORM_ADMIN_PASSWORD=local-admin-password
PLATFORM_DEMO_PASSWORD=local-dev-password
OAUTH2_PROXY_COOKIE_SECRET=0123456789abcdef0123456789abcdef
EOF

noop_makefile="${tmp_dir}/noop.mk"
cat >"${noop_makefile}" <<'EOF'
.PHONY: __platform_make_surface_noop
__platform_make_surface_noop:
EOF

db_file="${database_out:-${tmp_dir}/make.db}"
err_file="${tmp_dir}/make.err"
status=0

env \
  PLATFORM_ENV_FILE="${PLATFORM_ENV_FILE:-${env_file}}" \
  PLATFORM_ENV_TEMPLATE="${PLATFORM_ENV_TEMPLATE:-${env_file}}" \
  COMPOSE_CMD="${COMPOSE_CMD:-true}" \
  make -pRrq -C "${make_dir}" -f Makefile -f "${noop_makefile}" __platform_make_surface_noop >"${db_file}" 2>"${err_file}" || status=$?

if [ "${status}" -gt 1 ]; then
  cat "${err_file}" >&2
  exit "${status}"
fi

awk -F ' := ' '$1 == "MAKE_KNOWN_GOALS" { value = $2 } END { print value }' "${db_file}"
