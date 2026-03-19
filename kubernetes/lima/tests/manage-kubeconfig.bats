#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export HELPER="${REPO_ROOT}/terraform/kubernetes/scripts/manage-kubeconfig.sh"
}

@test "delete-context removes the resolved cluster and user behind a repo context" {
  kubeconfig="${BATS_TEST_TMPDIR}/config"
  cat >"${kubeconfig}" <<'YAML'
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    server: https://127.0.0.1:6443
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: limavm-k3s
current-context: limavm-k3s
users:
- name: default
  user:
    token: test
YAML

  run "${HELPER}" delete-context "${kubeconfig}" "limavm-k3s" "limavm-k3s" "limavm-k3s" 0

  [ "${status}" -eq 0 ]
  [[ -f "${kubeconfig}" ]]
  run env KUBECONFIG="${kubeconfig}" kubectl config view --raw -o jsonpath='{range .contexts[*]}{.name}{"\n"}{end}'
  [ "${status}" -eq 0 ]
  [[ -z "${output}" ]]
  run env KUBECONFIG="${kubeconfig}" kubectl config view --raw -o jsonpath='{.current-context}'
  [ "${status}" -eq 0 ]
  [[ -z "${output}" ]]
  run env KUBECONFIG="${kubeconfig}" kubectl config view --raw -o jsonpath='{.clusters[*].name}'
  [ "${status}" -eq 0 ]
  [[ -z "${output}" ]]
  run env KUBECONFIG="${kubeconfig}" kubectl config view --raw -o jsonpath='{.users[*].name}'
  [ "${status}" -eq 0 ]
  [[ -z "${output}" ]]
}

@test "prepare-for-reset deletes an invalid repo-owned singleton kubeconfig without creating a backup when auto-approved" {
  kubeconfig="${BATS_TEST_TMPDIR}/config"
  cat >"${kubeconfig}" <<'YAML'
apiVersion: v1
clusters:
- cluster:
    server: https://127.0.0.1:6443
  name: default
contexts: null
current-context: limavm-k3s
kind: Config
users:
- name: default
  user:
    token: test
YAML

  run env KUBECONFIG_RESET_AUTO_APPROVE=1 "${HELPER}" prepare-for-reset "${kubeconfig}"

  [ "${status}" -eq 0 ]
  [[ ! -e "${kubeconfig}" ]]
  run find "${BATS_TEST_TMPDIR}" -maxdepth 1 -name 'config.broken.*'
  [ "${status}" -eq 0 ]
  [[ -z "${output}" ]]
}

@test "prepare-for-reset still backs up invalid non-repo kubeconfigs" {
  kubeconfig="${BATS_TEST_TMPDIR}/config"
  cat >"${kubeconfig}" <<'YAML'
apiVersion: v1
clusters:
- cluster:
    server: https://10.0.0.5:6443
  name: prod
contexts: null
current-context: prod-cluster
kind: Config
users:
- name: prod
  user:
    token: test
YAML

  run "${HELPER}" prepare-for-reset "${kubeconfig}"

  [ "${status}" -eq 0 ]
  [[ ! -e "${kubeconfig}" ]]
  run find "${BATS_TEST_TMPDIR}" -maxdepth 1 -name 'config.broken.*'
  [ "${status}" -eq 0 ]
  [[ -n "${output}" ]]
}

@test "merge normalizes repo-owned default cluster and user refs" {
  source_kubeconfig="${BATS_TEST_TMPDIR}/source"
  target_kubeconfig="${BATS_TEST_TMPDIR}/target"
  cat >"${source_kubeconfig}" <<'YAML'
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    server: https://127.0.0.1:6443
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: slicer-k3s
current-context: slicer-k3s
users:
- name: default
  user:
    token: test
YAML
  cat >"${target_kubeconfig}" <<'YAML'
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    server: https://10.0.0.5:6443
  name: prod
contexts:
- context:
    cluster: prod
    user: prod
  name: prod
current-context: prod
users:
- name: prod
  user:
    token: prod
YAML

  run "${HELPER}" merge "${source_kubeconfig}" "${target_kubeconfig}" "slicer-k3s"

  [ "${status}" -eq 0 ]
  run env KUBECONFIG="${target_kubeconfig}" kubectl config view --raw -o jsonpath='{range .contexts[*]}{.name}{"\t"}{.context.cluster}{"\t"}{.context.user}{"\n"}{end}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'slicer-k3s\tslicer-k3s-cluster\tslicer-k3s-user'* ]]
  [[ "${output}" == *$'prod\tprod\tprod'* ]]
}

@test "merge repairs an existing stale repo-owned context instead of preserving default refs" {
  source_kubeconfig="${BATS_TEST_TMPDIR}/source"
  target_kubeconfig="${BATS_TEST_TMPDIR}/target"
  cat >"${source_kubeconfig}" <<'YAML'
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    server: https://127.0.0.1:6443
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: limavm-k3s
current-context: limavm-k3s
users:
- name: default
  user:
    token: fresh
YAML
  cat >"${target_kubeconfig}" <<'YAML'
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    server: https://127.0.0.1:6443
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: limavm-k3s
current-context: limavm-k3s
users:
- name: default
  user:
    token: stale
YAML

  run "${HELPER}" merge "${source_kubeconfig}" "${target_kubeconfig}" "limavm-k3s"

  [ "${status}" -eq 0 ]
  run env KUBECONFIG="${target_kubeconfig}" kubectl config view --raw -o jsonpath='{range .contexts[*]}{.name}{"\t"}{.context.cluster}{"\t"}{.context.user}{"\n"}{end}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == $'limavm-k3s\tlimavm-k3s-cluster\tlimavm-k3s-user' ]]
  run env KUBECONFIG="${target_kubeconfig}" kubectl config view --raw -o jsonpath='{.clusters[*].name}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == "limavm-k3s-cluster" ]]
  run env KUBECONFIG="${target_kubeconfig}" kubectl config view --raw -o jsonpath='{.users[*].name}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == "limavm-k3s-user" ]]
}
