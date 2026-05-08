#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export HOST_ACCESS_RENDERER="${REPO_ROOT}/kubernetes/host-access/render-contracts.sh"
  export VARIANTS_DIR="${REPO_ROOT}/kubernetes/variants"
}

@test "host access projection contains one contract per variant" {
  run bash -c '
    set -euo pipefail
    projected_json="$("${HOST_ACCESS_RENDERER}" --execute)"
    projected_ids="$(jq -r ".variants | map(.id) | sort | join(\" \")" <<<"${projected_json}")"
    variant_ids="$(find "${VARIANTS_DIR}" -mindepth 2 -maxdepth 2 -name variant.json -type f -print | sort | xargs jq -r ".id" | sort | tr "\n" " " | sed "s/ $//")"

    [ "${projected_ids}" = "${variant_ids}" ]
    jq -e "
      .schema_version == \"platform.host_access_paths/v1\"
      and .source_schema_version == \"platform.variant/v1\"
      and (.variants | length == 3)
    " <<<"${projected_json}" >/dev/null
  '

  [ "${status}" -eq 0 ]
}

@test "host access projection is sourced from variant host_access_path facts" {
  run bash -c '
    set -euo pipefail
    projected_json="$("${HOST_ACCESS_RENDERER}" --execute)"

    for variant in "${VARIANTS_DIR}"/*/variant.json; do
      id="$(jq -r ".id" "${variant}")"
      jq -e --arg id "${id}" --slurpfile variant "${variant}" "
        .variants[]
        | select(.id == \$id)
        | .path == \$variant[0].path
          and .mode == \$variant[0].host_access_path.mode
          and .gateway_host_port == \$variant[0].host_access_path.gateway_host_port
          and (.gateway_forward_port // null) == (\$variant[0].host_access_path.gateway_forward_port // null)
          and (.gateway_target_port // null) == (\$variant[0].host_access_path.gateway_target_port // null)
          and .shared_host_ports == \$variant[0].host_access_path.shared_host_ports
          and .requires_proxy == \$variant[0].host_access_path.requires_proxy
          and .requires_forward_process == \$variant[0].host_access_path.requires_forward_process
          and .can_degrade == \$variant[0].host_access_path.can_degrade
      " <<<"${projected_json}" >/dev/null
    done
  '

  [ "${status}" -eq 0 ]
}

@test "host access projection validates kind lima and slicer modes and process requirements" {
  run bash -c '
    set -euo pipefail
    projected_json="$("${HOST_ACCESS_RENDERER}" --execute)"

    jq -e "
      .variants[] | select(.id == \"kind\")
      | .mode == \"kind-nodeports\"
        and .requires_proxy == false
        and .requires_forward_process == false
        and .required_processes == []
        and .can_degrade == false
    " <<<"${projected_json}" >/dev/null

    jq -e "
      .variants[] | select(.id == \"lima\")
      | .mode == \"host-gateway-proxy\"
        and .requires_proxy == true
        and .requires_forward_process == false
        and .required_processes == [\"proxy\"]
        and .can_degrade == true
    " <<<"${projected_json}" >/dev/null

    jq -e "
      .variants[] | select(.id == \"slicer\")
      | .mode == \"host-forwards-plus-proxy\"
        and .requires_proxy == true
        and .requires_forward_process == true
        and .required_processes == [\"proxy\", \"forward\"]
        and .can_degrade == true
    " <<<"${projected_json}" >/dev/null
  '

  [ "${status}" -eq 0 ]
}

@test "host access projection validates gateway ports and shared host ports" {
  run bash -c '
    set -euo pipefail
    projected_json="$("${HOST_ACCESS_RENDERER}" --execute)"
    shared_ports="[443,30022,30080,30090,31235,3301,3302]"

    jq -e --argjson shared_ports "${shared_ports}" "
      .variants
      | all(
          . as \$variant
          | \$variant.gateway_host_port == 443
            and \$variant.shared_host_ports == \$shared_ports
            and (\$variant.shared_host_ports | index(\$variant.gateway_host_port))
        )
    " <<<"${projected_json}" >/dev/null

    jq -e "
      .variants[] | select(.id == \"kind\")
      | .gateway_target_port == 30070
        and (.gateway_forward_port == null)
    " <<<"${projected_json}" >/dev/null

    jq -e "
      .variants[] | select(.id == \"lima\")
      | (.gateway_target_port == null)
        and (.gateway_forward_port == null)
    " <<<"${projected_json}" >/dev/null

    jq -e "
      .variants[] | select(.id == \"slicer\")
      | .gateway_target_port == 30070
        and .gateway_forward_port == 8443
    " <<<"${projected_json}" >/dev/null
  '

  [ "${status}" -eq 0 ]
}
