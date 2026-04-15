#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/show-policy-composition.sh"
}

@test "show-policy-composition renders the dev Cloudflare policy and omits the deleted shared policy" {
  run "${SCRIPT}" --execute --target cilium --format markdown

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'[`terraform/kubernetes/scripts/show-policy-composition.sh`](../scripts/show-policy-composition.sh)'* ]]
  [[ "${output}" == *'Displayed policy source paths below are relative to [`terraform/kubernetes/cluster-policies/cilium`](./cilium).'* ]]
  [[ "${output}" == *'| Name | Source |'* ]]
  [[ "${output}" != *'| Name | Source Files |'* ]]
  [[ "${output}" != *'| Source | Rendered Resources |'* ]]
  [[ "${output}" == *'#### CiliumNetworkPolicy'* ]]
  [[ "${output}" == *'| `subnetcalc-cloudflare-live-fetch` | [`dev/overrides/subnetcalc-cloudflare-live-fetch.yaml`](./cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml) |'* ]]
  [[ "${output}" != *'subnetcalc-api-cloudflare-egress.yaml` | `CiliumClusterwideNetworkPolicy/allow-subnetcalc-api-cloudflare-egress`'* ]]
}

@test "show-policy-composition renders kyverno shared and uat overlays" {
  run "${SCRIPT}" --execute --target kyverno --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Overlay: shared"* ]]
  [[ "${output}" == *"Overlay: uat"* ]]
  [[ "${output}" == *"  ClusterPolicy"* ]]
  [[ "${output}" == *"protect-default-deny-netpol"* ]]
}

@test "show-policy-composition supports dev sentiment egress slices" {
  run "${SCRIPT}" --execute --target cilium --namespace dev --label sentiment --egress --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Overlay: dev"* ]]
  [[ "${output}" != *"Overlay: uat"* ]]
  [[ "${output}" == *"  CiliumNetworkPolicy"* ]]
  [[ "${output}" == *"sentiment-api-egress"* ]]
  [[ "${output}" == *"sentiment-router-http-routes"* ]]
  [[ "${output}" != *"sentiment-frontend-ingress"* ]]
  [[ "${output}" != *"sentiment-router-ingress"* ]]
}

@test "show-policy-composition supports uat sentiment ingress slices" {
  run "${SCRIPT}" --execute --target cilium --namespace uat --label sentiment --ingress --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Overlay: uat"* ]]
  [[ "${output}" != *"Overlay: dev"* ]]
  [[ "${output}" == *"  CiliumNetworkPolicy"* ]]
  [[ "${output}" == *"sentiment-router-ingress"* ]]
  [[ "${output}" == *"sentiment-backend-ingress"* ]]
  [[ "${output}" == *"sentiment-frontend-ingress"* ]]
  [[ "${output}" != *"sentiment-api-egress"* ]]
}

@test "show-policy-composition supports allow and deny label slices" {
  run "${SCRIPT}" --execute --target cilium --label allow --egress --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"  CiliumClusterwideNetworkPolicy"* ]]
  [[ "${output}" == *"allow-application-backend-egress-via-fqdn"* ]]

  run "${SCRIPT}" --execute --target cilium --label deny --egress --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"  CiliumClusterwideNetworkPolicy"* ]]
  [[ "${output}" == *"deny-cloud-metadata-egress"* ]]
  [[ "${output}" == *"deny-application-sentiment-to-subnetcalc"* ]]
}

@test "show-policy-composition supports sit overlay slices" {
  run "${SCRIPT}" --execute --target cilium --namespace sit --label subnetcalc --format text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Overlay: sit"* ]]
  [[ "${output}" != *"Overlay: dev"* ]]
  [[ "${output}" == *"  CiliumNetworkPolicy"* ]]
  [[ "${output}" == *"subnetcalc-router-http-routes"* ]]
  [[ "${output}" == *"subnetcalc-api-http-routes"* ]]
}
