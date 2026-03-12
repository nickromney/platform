#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/show-policy-composition.sh"
}

@test "show-policy-composition renders the dev Cloudflare policy and omits the deleted shared policy" {
  run "${SCRIPT}" --target cilium --format markdown

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'[`terraform/kubernetes/scripts/show-policy-composition.sh`](../scripts/show-policy-composition.sh)'* ]]
  [[ "${output}" == *'| `CiliumClusterwideNetworkPolicy` | `dev-subnetcalc-api-cloudflare-egress` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-subnetcalc-api-cloudflare-egress.yaml`](./cilium/dev/dev-subnetcalc-api-cloudflare-egress.yaml) |'* ]]
  [[ "${output}" == *'| [`terraform/kubernetes/cluster-policies/cilium/dev/dev-subnetcalc-api-cloudflare-egress.yaml`](./cilium/dev/dev-subnetcalc-api-cloudflare-egress.yaml) | `CiliumClusterwideNetworkPolicy/dev-subnetcalc-api-cloudflare-egress` |'* ]]
  [[ "${output}" != *'subnetcalc-api-cloudflare-egress.yaml` | `CiliumClusterwideNetworkPolicy/allow-subnetcalc-api-cloudflare-egress`'* ]]
}

@test "show-policy-composition renders kyverno shared and uat overlays" {
  run "${SCRIPT}" --target kyverno --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Overlay: shared"* ]]
  [[ "${output}" == *"Overlay: uat"* ]]
  [[ "${output}" == *"ClusterPolicy/protect-default-deny-netpol"* ]]
}

@test "show-policy-composition supports dev sentiment egress slices" {
  run "${SCRIPT}" --target cilium --namespace dev --label sentiment --egress --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Overlay: dev"* ]]
  [[ "${output}" != *"Overlay: uat"* ]]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/dev-sentiment-api-egress"* ]]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/dev-sentiment-litellm-ingress-egress"* ]]
  [[ "${output}" != *"CiliumClusterwideNetworkPolicy/dev-sentiment-frontend-ingress"* ]]
  [[ "${output}" != *"CiliumClusterwideNetworkPolicy/dev-sentiment-router-ingress"* ]]
}

@test "show-policy-composition supports uat sentiment ingress slices" {
  run "${SCRIPT}" --target cilium --namespace uat --label sentiment --ingress --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Overlay: uat"* ]]
  [[ "${output}" != *"Overlay: dev"* ]]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/uat-sentiment-router-ingress"* ]]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/uat-sentiment-backend-ingress"* ]]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/uat-sentiment-frontend-ingress"* ]]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/uat-sentiment-litellm-ingress-egress"* ]]
  [[ "${output}" != *"CiliumClusterwideNetworkPolicy/uat-sentiment-api-egress"* ]]
}

@test "show-policy-composition supports allow and deny label slices" {
  run "${SCRIPT}" --target cilium --label allow --egress --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/allow-dev-uat-apps-egress-via-fqdn"* ]]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/allow-sentiment-llama-cpp-world-egress"* ]]
  [[ "${output}" != *"CiliumClusterwideNetworkPolicy/deny-cloud-metadata-egress"* ]]

  run "${SCRIPT}" --target cilium --label deny --egress --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/deny-cloud-metadata-egress"* ]]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/deny-sentiment-to-subnetcalc-dev"* ]]
}
