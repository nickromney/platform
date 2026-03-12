#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

@test "every Cilium FQDN policy includes a DNS proxy rule" {
  fqdn_files="$(cd "${REPO_ROOT}" && rg -l 'toFQDNs:' terraform/kubernetes/cluster-policies/cilium -g '*.yaml' | sort)"

  [ -n "${fqdn_files}" ]

  while IFS= read -r relpath; do
    file="${REPO_ROOT}/${relpath}"
    grep -Fq "rules:" "${file}"
    grep -Fq "dns:" "${file}"
    grep -Fq 'matchPattern: "*"' "${file}"
  done <<EOF
${fqdn_files}
EOF
}

@test "dev Cloudflare policy is exact-host only and has no CIDR assist" {
  policy="${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml"

  grep -Fq "matchName: www.cloudflare.com" "${policy}"
  ! grep -Fq "matchName: cloudflare.com" "${policy}"
  ! grep -Fq "toCIDRSet:" "${policy}"
}

@test "shared identity egress policy stays pinned to the minimal Entra hosts" {
  policy="${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium/shared/shared-identity-egress-via-fqdn.yaml"

  grep -Fq "matchName: login.microsoftonline.com" "${policy}"
  grep -Fq "matchName: graph.microsoft.com" "${policy}"
  ! grep -Fq 'matchPattern: "*.microsoftonline.com"' "${policy}"
}

@test "rendered Cilium policy set no longer includes the shared Cloudflare policy" {
  run kubectl kustomize "${REPO_ROOT}/terraform/kubernetes/cluster-policies/cilium"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: subnetcalc-cloudflare-live-fetch"* ]]
  [[ "${output}" != *"name: allow-subnetcalc-api-cloudflare-egress"* ]]
}
