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
  [[ "${output}" == *"app: sentiment"* ]]
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
  [[ "${output}" == *"app: sentiment"* ]]
  [[ "${output}" == *"app: subnetcalc"* ]]
  [[ "${output}" == *"project: kindlocal"* ]]
  [[ "${output}" == *"team: dolphin"* ]]
}

@test "kyverno render enforces the shared label contract in application namespaces" {
  run kubectl kustomize "${REPO_ROOT}/terraform/kubernetes/cluster-policies/kyverno"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: require-app-labels-application-namespaces"* ]]
  [[ "${output}" == *"Deployments in application namespaces must carry app, tier,"* ]]
  [[ "${output}" == *$'            matchLabels:\n              platform.publiccloudexperiments.net/namespace-role: application'* ]]
  [[ "${output}" == *"project: kindlocal"* ]]
  [[ "${output}" == *"team: dolphin"* ]]
  [[ "${output}" == *"app: ?*"* ]]
  [[ "${output}" == *"tier: ?*"* ]]
}

@test "namespace definitions separate application, shared, and platform roles" {
  dev_ns="${REPO_ROOT}/terraform/kubernetes/namespaces.tf"
  argocd_ns="${REPO_ROOT}/terraform/kubernetes/argocd.tf"
  sso_ns="${REPO_ROOT}/terraform/kubernetes/sso.tf"
  observability_ns="${REPO_ROOT}/terraform/kubernetes/observability.tf"
  apim_manifest="${REPO_ROOT}/terraform/kubernetes/apps/apim/all.yaml"
  observability_manifest="${REPO_ROOT}/terraform/kubernetes/apps/argocd-apps/80-observability.namespace.yaml"
  platform_gateway_manifest="${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway/namespace.yaml"
  gateway_routes_manifest="${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes/namespace.yaml"
  gateway_routes_sso_manifest="${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/namespace.yaml"
  nginx_gateway_manifest="${REPO_ROOT}/terraform/kubernetes/apps/nginx-gateway-fabric/deploy.yaml"

  grep -Fq '"platform.publiccloudexperiments.net/namespace-role" = "application"' "${dev_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/environment"    = "dev"' "${dev_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/environment"    = "uat"' "${dev_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/environment"    = "sit"' "${dev_ns}"
  grep -Fq 'name = "dev"' "${dev_ns}"
  grep -Fq 'name = "uat"' "${dev_ns}"
  grep -Fq 'name = "sit"' "${dev_ns}"
  grep -Fq 'name: cert-manager' "${dev_ns}"
  grep -Fq 'name: kyverno' "${dev_ns}"
  grep -Fq 'name: policy-reporter' "${dev_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/namespace-role" = "shared"' "${dev_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/sensitivity"    = "private"' "${dev_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/namespace-role" = "platform"' "${dev_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/namespace-role" = "platform"' "${argocd_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/namespace-role" = "shared"' "${sso_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/sensitivity"    = "restricted"' "${sso_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/namespace-role" = "shared"' "${observability_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/sensitivity"    = "confidential"' "${observability_ns}"
  grep -Fq '"platform.publiccloudexperiments.net/namespace-role": shared' "${apim_manifest}"
  grep -Fq '"platform.publiccloudexperiments.net/namespace-role": shared' "${observability_manifest}"
  grep -Fq '"platform.publiccloudexperiments.net/sensitivity": confidential' "${observability_manifest}"
  grep -Fq '"platform.publiccloudexperiments.net/namespace-role": shared' "${platform_gateway_manifest}"
  grep -Fq '"platform.publiccloudexperiments.net/namespace-role": shared' "${gateway_routes_manifest}"
  grep -Fq '"platform.publiccloudexperiments.net/namespace-role": shared' "${gateway_routes_sso_manifest}"
  grep -Fq '"platform.publiccloudexperiments.net/namespace-role": platform' "${nginx_gateway_manifest}"
}

@test "cilium render keeps external egress on app backends and APIM next hops only" {
  run kubectl kustomize "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: allow-application-backend-egress-via-fqdn"* ]]
  [[ "${output}" == *"name: shared-baseline"* ]]
  [[ "${output}" == *"name: shared-auth-proxy-bridge"* ]]
  [[ "${output}" == *"name: shared-identity-provider-ingress"* ]]
  [[ "${output}" == *"name: allow-shared-identity-egress-via-fqdn"* ]]
  [[ "${output}" == *$'      - sentiment-api\n      - subnetcalc-api'* ]]
  [[ "${output}" != *"      - sentiment-auth-ui"* ]]
  [[ "${output}" != *"      - subnetcalc-router"* ]]
  [[ "${output}" == *"name: application-baseline"* ]]
  [[ "${output}" == *"name: apim-baseline"* ]]
  [[ "${output}" == *"k8s:app.kubernetes.io/component: authentication-proxy"* ]]
  [[ "${output}" == *"k8s:app.kubernetes.io/name: dex"* ]]
  [[ "${output}" == *"k8s:io.cilium.k8s.namespace.labels.platform.publiccloudexperiments.net/namespace-role: shared"* ]]
  [[ "${output}" == *"k8s:app.kubernetes.io/name: subnetcalc-router"* ]]
  [[ "${output}" == *"k8s:app.kubernetes.io/name: subnetcalc-api"* ]]
  [[ "${output}" == *"k8s:io.cilium.k8s.namespace.labels.platform.publiccloudexperiments.net/namespace-role: application"* ]]
  [[ "${output}" == *"k8s:tier: gateway"* ]]
  [[ "${output}" == *"k8s:tier: backend"* ]]
  [[ "${output}" == *"name: deny-application-sentiment-to-subnetcalc"* ]]
  [[ "${output}" == *"k8s:app: sentiment"* ]]
  [[ "${output}" == *"k8s:app: subnetcalc"* ]]
  [[ "${output}" == *"kind: CiliumNetworkPolicy"* ]]
  [[ "${output}" == *"namespace: sit"* ]]
}

@test "application router policies trust shared auth proxies instead of hard-coded sso namespace matches" {
  sentiment_runtime="${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml"
  subnetcalc_runtime="${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-runtime.yaml"

  grep -Fq '"k8s:app.kubernetes.io/component": authentication-proxy' "${sentiment_runtime}"
  grep -Fq '"k8s:io.cilium.k8s.namespace.labels.platform.publiccloudexperiments.net/namespace-role": shared' "${sentiment_runtime}"
  ! grep -Fq '"k8s:io.kubernetes.pod.namespace": sso' "${sentiment_runtime}"

  grep -Fq '"k8s:app.kubernetes.io/component": authentication-proxy' "${subnetcalc_runtime}"
  grep -Fq '"k8s:io.cilium.k8s.namespace.labels.platform.publiccloudexperiments.net/namespace-role": shared' "${subnetcalc_runtime}"
  ! grep -Fq '"k8s:io.kubernetes.pod.namespace": sso' "${subnetcalc_runtime}"
}

@test "dev overlay carries the project override without leaking it to uat or sit" {
  run kubectl kustomize "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/dev"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: subnetcalc-cloudflare-live-fetch"* ]]
  [[ "${output}" == *"namespace: dev"* ]]

  run kubectl kustomize "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/uat"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"name: subnetcalc-cloudflare-live-fetch"* ]]

  run kubectl kustomize "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/sit"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"name: subnetcalc-cloudflare-live-fetch"* ]]
}
