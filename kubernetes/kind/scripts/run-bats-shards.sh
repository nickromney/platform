#!/bin/bash
set -euo pipefail

# Compatibility wrapper: shard execution lives in scripts/run-bats-shards.sh
# so make test-ci and kind test-bats share one runner.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
exec "${REPO_ROOT}/scripts/run-bats-shards.sh" "$@"
