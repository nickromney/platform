#!/bin/sh
# Run tests against the Lima SD-WAN lab
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../../.." && pwd)

. "${REPO_ROOT}/scripts/lib/shell-cli-posix.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Run the SD-WAN Lima test suite through the local Makefile workflow.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would run the SD-WAN Lima test suite via make test" "$@"

cd "$(dirname "$0")/.."

if command -v limactl >/dev/null 2>&1 && limactl list 2>/dev/null | grep -q "cloud1"; then
    echo "=== Running tests against Lima VMs ==="
    make test
else
    echo "Lima VMs are not running. Start them first with: make up"
    exit 1
fi

echo ""
echo "All tests passed!"
