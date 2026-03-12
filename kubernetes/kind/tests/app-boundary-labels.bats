#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

@test "dev and uat workload renders include the shared app boundary labels" {
  run kubectl kustomize "${REPO_ROOT}/terraform/kubernetes/apps/dev"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: sentiment-api"* ]]
  [[ "${output}" == *"name: subnetcalc-api"* ]]
  [[ "${output}" == *"app: sentiment-llm"* ]]
  [[ "${output}" == *"app: subnetcalc"* ]]
  [[ "${output}" == *"project: kindlocal"* ]]
  [[ "${output}" == *"team: dolphin"* ]]
  [[ "${output}" == *"tier: frontend"* ]]
  [[ "${output}" == *"tier: gateway"* ]]
  [[ "${output}" == *"tier: backend"* ]]

  run kubectl kustomize "${REPO_ROOT}/terraform/kubernetes/apps/uat"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: sentiment-api"* ]]
  [[ "${output}" == *"name: subnetcalc-api"* ]]
  [[ "${output}" == *"app: sentiment-llm"* ]]
  [[ "${output}" == *"app: subnetcalc"* ]]
  [[ "${output}" == *"project: kindlocal"* ]]
  [[ "${output}" == *"team: dolphin"* ]]
}

@test "kyverno render enforces the shared label contract in application namespaces" {
  run kubectl kustomize "${REPO_ROOT}/terraform/kubernetes/cluster-policies/kyverno"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: require-app-labels-application-namespaces"* ]]
  [[ "${output}" == *"Deployments in application namespaces must carry app, tier,"* ]]
  [[ "${output}" == *$'            matchLabels:\n              role: application'* ]]
  [[ "${output}" == *"project: kindlocal"* ]]
  [[ "${output}" == *"team: dolphin"* ]]
  [[ "${output}" == *"app: ?*"* ]]
  [[ "${output}" == *"tier: ?*"* ]]
}

@test "terraform namespace definitions separate application and shared roles" {
  dev_ns="${REPO_ROOT}/terraform/kubernetes/namespaces.tf"
  sso_ns="${REPO_ROOT}/terraform/kubernetes/sso.tf"
  observability_ns="${REPO_ROOT}/terraform/kubernetes/observability.tf"
  apim_manifest="${REPO_ROOT}/terraform/kubernetes/apps/apim/all.yaml"
  observability_manifest="${REPO_ROOT}/terraform/kubernetes/apps/argocd-apps/80-observability.namespace.yaml"

  grep -Fq '"role"                         = "application"' "${dev_ns}"
  grep -Fq 'name = "dev"' "${dev_ns}"
  grep -Fq 'name = "uat"' "${dev_ns}"
  grep -Fq '"role"                         = "shared"' "${dev_ns}"
  grep -Fq '"role"                = "shared"' "${sso_ns}"
  grep -Fq '"role"                         = "shared"' "${observability_ns}"
  grep -Fq 'role: shared' "${apim_manifest}"
  grep -Fq 'role: shared' "${observability_manifest}"
}

@test "cilium render keeps external egress on app backends and APIM next hops only" {
  run kubectl kustomize "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: allow-dev-uat-apps-egress-via-fqdn"* ]]
  [[ "${output}" == *$'      - sentiment-api\n      - subnetcalc-api'* ]]
  [[ "${output}" != *"      - sentiment-auth-ui"* ]]
  [[ "${output}" != *"      - subnetcalc-router"* ]]
  [[ "${output}" == *"name: apim-baseline"* ]]
  [[ "${output}" == *"k8s:app.kubernetes.io/name: subnetcalc-router"* ]]
  [[ "${output}" == *"k8s:app.kubernetes.io/name: subnetcalc-api"* ]]
  [[ "${output}" == *"k8s:tier: gateway"* ]]
  [[ "${output}" == *"k8s:tier: backend"* ]]
  [[ "${output}" == *"name: deny-sentiment-to-subnetcalc-dev"* ]]
  [[ "${output}" == *"k8s:app: sentiment-llm"* ]]
  [[ "${output}" == *"k8s:app: subnetcalc"* ]]
}
