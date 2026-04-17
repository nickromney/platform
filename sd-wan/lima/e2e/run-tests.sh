#!/usr/bin/env bash
# Run Playwright E2E tests

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../../.." && pwd)
playwright_args=()

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
while [[ "$#" -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --)
      shift
      while [[ "$#" -gt 0 ]]; do
        playwright_args+=("$1")
        shift
      done
      break
      ;;
    -*)
      shell_cli_unknown_flag "$1"
      exit 2
      ;;
    *)
      playwright_args+=("$1")
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

has_cached_chromium=0
for cache_root in \
  "$HOME/Library/Caches/ms-playwright" \
  "$HOME/.cache/ms-playwright"; do
  for chrome_binary in "${cache_root}/chromium-"*"/chrome-linux/chrome"; do
    if [[ -f "${chrome_binary}" ]]; then
      has_cached_chromium=1
      break 2
    fi
  done
done

if [[ "${has_cached_chromium}" -eq 0 ]]; then
	echo "Installing Playwright browsers..."
	npx playwright install chromium
fi

echo "Running Playwright tests..."
if [[ "${#playwright_args[@]}" -gt 0 ]]; then
  npx playwright test "${playwright_args[@]}"
else
  npx playwright test
fi
