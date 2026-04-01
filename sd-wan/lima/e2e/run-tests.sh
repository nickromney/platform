#!/bin/sh
# Run Playwright E2E tests

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../../.." && pwd)
playwright_args=

. "${REPO_ROOT}/scripts/lib/shell-cli-posix.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute] [-- <playwright args...>]

Run the Playwright browser checks for the SD-WAN Lima lab.

Arguments after \`--\` are forwarded to \`npx playwright test\`.

$(shell_cli_standard_options)
EOF
}

shell_cli_init_standard_flags
while [ "$#" -gt 0 ]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --)
      shift
      playwright_args="$*"
      break
      ;;
    -*)
      shell_cli_unknown_flag "$1"
      exit 2
      ;;
    *)
      playwright_args="$playwright_args $1"
      ;;
  esac
  shift
done

shell_cli_maybe_execute_or_preview_summary \
  usage \
  "would run the SD-WAN Playwright E2E suite"

cd "$(dirname "$0")"

if [ ! -d "node_modules" ]; then
	echo "Installing dependencies..."
	npm install
fi

if [ ! -f "$HOME/Library/Caches/ms-playwright/chromium-*/chrome-linux/chrome" ] &&
	[ ! -f "$HOME/.cache/ms-playwright/chromium-*/chrome-linux/chrome" ]; then
	echo "Installing Playwright browsers..."
	npx playwright install chromium
fi

echo "Running Playwright tests..."
if [ -n "${playwright_args}" ]; then
  # shellcheck disable=SC2086
  npx playwright test ${playwright_args}
else
  npx playwright test
fi
