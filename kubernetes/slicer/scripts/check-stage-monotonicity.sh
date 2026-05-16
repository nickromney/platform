#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SLICER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STAGES_DIR="${STAGES_DIR:-${SLICER_DIR}/stages}"

exec "${SCRIPT_DIR}/../../scripts/check-stage-monotonicity.sh" \
  --stack-dir "${SLICER_DIR}" \
  --stages-dir "${STAGES_DIR}" \
  --label Slicer \
  "$@"
