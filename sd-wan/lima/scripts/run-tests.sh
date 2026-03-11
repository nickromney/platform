#!/bin/sh
# Run tests against the Lima SD-WAN lab
set -e

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
