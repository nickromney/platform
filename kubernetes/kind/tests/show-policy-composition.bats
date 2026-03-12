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
  [[ "${output}" == *'| `CiliumNetworkPolicy` | `subnetcalc-cloudflare-live-fetch` | [`terraform/kubernetes/cluster-policies/cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml`](./cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml) |'* ]]
  [[ "${output}" == *'| [`terraform/kubernetes/cluster-policies/cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml`](./cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml) | `CiliumNetworkPolicy/subnetcalc-cloudflare-live-fetch` |'* ]]
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
  [[ "${output}" == *"CiliumNetworkPolicy/sentiment-api-egress"* ]]
  [[ "${output}" == *"CiliumNetworkPolicy/sentiment-litellm-ingress-egress"* ]]
  [[ "${output}" == *"CiliumNetworkPolicy/sentiment-router-http-routes"* ]]
  [[ "${output}" != *"CiliumNetworkPolicy/sentiment-frontend-ingress"* ]]
  [[ "${output}" != *"CiliumNetworkPolicy/sentiment-router-ingress"* ]]
}

@test "show-policy-composition supports uat sentiment ingress slices" {
  run "${SCRIPT}" --target cilium --namespace uat --label sentiment --ingress --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Overlay: uat"* ]]
  [[ "${output}" != *"Overlay: dev"* ]]
  [[ "${output}" == *"CiliumNetworkPolicy/sentiment-router-ingress"* ]]
  [[ "${output}" == *"CiliumNetworkPolicy/sentiment-backend-ingress"* ]]
  [[ "${output}" == *"CiliumNetworkPolicy/sentiment-frontend-ingress"* ]]
  [[ "${output}" == *"CiliumNetworkPolicy/sentiment-litellm-ingress-egress"* ]]
  [[ "${output}" != *"CiliumNetworkPolicy/sentiment-api-egress"* ]]
}

@test "show-policy-composition supports allow and deny label slices" {
  run "${SCRIPT}" --target cilium --label allow --egress --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/allow-application-backend-egress-via-fqdn"* ]]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/allow-sentiment-llama-cpp-world-egress"* ]]
  [[ "${output}" != *"CiliumClusterwideNetworkPolicy/deny-cloud-metadata-egress"* ]]

  run "${SCRIPT}" --target cilium --label deny --egress --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/deny-cloud-metadata-egress"* ]]
  [[ "${output}" == *"CiliumClusterwideNetworkPolicy/deny-application-sentiment-to-subnetcalc"* ]]
}

@test "show-policy-composition supports sit overlay slices" {
  run "${SCRIPT}" --target cilium --namespace sit --label subnetcalc --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Overlay: sit"* ]]
  [[ "${output}" != *"Overlay: dev"* ]]
  [[ "${output}" == *"CiliumNetworkPolicy/subnetcalc-router-http-routes"* ]]
  [[ "${output}" == *"CiliumNetworkPolicy/subnetcalc-api-http-routes"* ]]
}
