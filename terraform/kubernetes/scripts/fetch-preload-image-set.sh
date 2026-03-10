#!/usr/bin/env bash
set -euo pipefail

fail() { echo "fetch-preload-image-set: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || fail "jq not found"
command -v shasum >/dev/null 2>&1 || fail "shasum not found"

query="$(cat)"
PRELOAD_SCRIPT="$(jq -r '.preload_script // empty' <<<"${query}")"
IMAGE_LIST="$(jq -r '.image_list // empty' <<<"${query}")"
ENABLE_SIGNOZ="$(jq -r '.enable_signoz // "false"' <<<"${query}")"
ENABLE_PROMETHEUS="$(jq -r '.enable_prometheus // "false"' <<<"${query}")"
ENABLE_GRAFANA="$(jq -r '.enable_grafana // "false"' <<<"${query}")"
ENABLE_LOKI="$(jq -r '.enable_loki // "false"' <<<"${query}")"
ENABLE_TEMPO="$(jq -r '.enable_tempo // "false"' <<<"${query}")"
ENABLE_HEADLAMP="$(jq -r '.enable_headlamp // "false"' <<<"${query}")"
ENABLE_SSO="$(jq -r '.enable_sso // "false"' <<<"${query}")"
ENABLE_ACTIONS_RUNNER="$(jq -r '.enable_actions_runner // "false"' <<<"${query}")"

[[ -n "${PRELOAD_SCRIPT}" ]] || fail "preload_script is required"
[[ -f "${PRELOAD_SCRIPT}" ]] || fail "preload_script not found at ${PRELOAD_SCRIPT}"
[[ -n "${IMAGE_LIST}" ]] || fail "image_list is required"
[[ -f "${IMAGE_LIST}" ]] || fail "image_list not found at ${IMAGE_LIST}"

images="$(
  PRELOAD_ENABLE_SIGNOZ="${ENABLE_SIGNOZ}" \
  PRELOAD_ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS}" \
  PRELOAD_ENABLE_GRAFANA="${ENABLE_GRAFANA}" \
  PRELOAD_ENABLE_LOKI="${ENABLE_LOKI}" \
  PRELOAD_ENABLE_TEMPO="${ENABLE_TEMPO}" \
  PRELOAD_ENABLE_HEADLAMP="${ENABLE_HEADLAMP}" \
  PRELOAD_ENABLE_SSO="${ENABLE_SSO}" \
  PRELOAD_ENABLE_ACTIONS_RUNNER="${ENABLE_ACTIONS_RUNNER}" \
  "${PRELOAD_SCRIPT}" --image-list "${IMAGE_LIST}" --print-images
)"

image_count="$(printf '%s\n' "${images}" | awk 'NF {count++} END {print count+0}')"
image_set_sha="$(printf '%s\n' "${images}" | awk 'NF' | shasum -a 256 | awk '{print $1}')"

jq -cn \
  --arg image_set_sha "${image_set_sha}" \
  --arg image_count "${image_count}" \
  '{image_set_sha: $image_set_sha, image_count: $image_count}'
