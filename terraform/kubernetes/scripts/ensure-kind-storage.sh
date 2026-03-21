#!/usr/bin/env bash
set -euo pipefail

fail() { echo "ensure-kind-storage: $*" >&2; exit 1; }
ok() { echo "ensure-kind-storage: $*"; }

require() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required binary: $1"
}

require kubectl
require jq

LOCAL_PATH_MANIFEST_PATH="${LOCAL_PATH_MANIFEST_PATH:-}"
STANDARD_STORAGECLASS_MANIFEST_PATH="${STANDARD_STORAGECLASS_MANIFEST_PATH:-}"

[[ -n "${LOCAL_PATH_MANIFEST_PATH}" && -f "${LOCAL_PATH_MANIFEST_PATH}" ]] || fail "LOCAL_PATH_MANIFEST_PATH is missing or unreadable"
[[ -n "${STANDARD_STORAGECLASS_MANIFEST_PATH}" && -f "${STANDARD_STORAGECLASS_MANIFEST_PATH}" ]] || fail "STANDARD_STORAGECLASS_MANIFEST_PATH is missing or unreadable"

has_storageclass() {
  local name="$1"
  kubectl get storageclass "${name}" >/dev/null 2>&1
}

default_storageclass_name() {
  kubectl get storageclass -o json | jq -r '
    first(
      .items[]
      | select(
          .metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true"
          or .metadata.annotations["storageclass.beta.kubernetes.io/is-default-class"] == "true"
        )
      | .metadata.name
    ) // ""
  '
}

ensure_local_path_provisioner() {
  if has_storageclass "local-path"; then
    return 0
  fi

  ok "installing Rancher local-path provisioner"
  kubectl apply -f "${LOCAL_PATH_MANIFEST_PATH}" >/dev/null
  kubectl -n local-path-storage rollout status deploy/local-path-provisioner --timeout=180s >/dev/null
}

ensure_standard_storageclass() {
  if ! has_storageclass "standard"; then
    ok "creating standard storage class backed by rancher.io/local-path"
    kubectl apply -f "${STANDARD_STORAGECLASS_MANIFEST_PATH}" >/dev/null
  fi

  local default_sc
  default_sc="$(default_storageclass_name)"
  if [[ -z "${default_sc}" || "${default_sc}" == "standard" ]]; then
    kubectl annotate storageclass standard storageclass.kubernetes.io/is-default-class=true --overwrite >/dev/null
    kubectl annotate storageclass standard storageclass.beta.kubernetes.io/is-default-class=true --overwrite >/dev/null
    ok "standard storage class is available${default_sc:+ and remains the default}"
  else
    ok "standard storage class is available (default remains ${default_sc})"
  fi
}

ensure_local_path_provisioner
ensure_standard_storageclass
