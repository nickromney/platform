#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export RENDER_OPTIONS="${REPO_ROOT}/kubernetes/workflow/render-options.sh"
  export VARIANTS_DIR="${REPO_ROOT}/kubernetes/variants"
}

@test "variant contracts match workflow option variants" {
  run bash -c '
    set -euo pipefail
    options_json="$("${RENDER_OPTIONS}" --execute)"
    option_ids="$(jq -r ".variants | map(.id) | sort | join(\" \")" <<<"${options_json}")"
    contract_ids="$(find "${VARIANTS_DIR}" -name variant.json -maxdepth 2 -type f -print | sort | xargs jq -r ".id" | sort | tr "\n" " " | sed "s/ $//")"
    [ "${option_ids}" = "${contract_ids}" ]

    for contract in "${VARIANTS_DIR}"/*/variant.json; do
      id="$(jq -r ".id" "${contract}")"
      jq -e --arg id "${id}" --slurpfile contract "${contract}" "
        .variants[]
        | select(.id == \$id)
        | .path == \$contract[0].path
          and .class == \$contract[0].class
          and .family == \$contract[0].family
          and .lifecycle_mode == \$contract[0].lifecycle_mode
          and .state_scope == \$contract[0].state_scope
          and .contexts == \$contract[0].contexts
          and .readiness.command == \$contract[0].readiness.command
          and .variant_contract == \$contract[0]
      " <<<"${options_json}" >/dev/null
    done
  '

  [ "${status}" -eq 0 ]
}

@test "variant contracts expose required solution adapter facts" {
  run bash -c '
    set -euo pipefail
    for contract in "${VARIANTS_DIR}"/*/variant.json; do
      jq -e "
        .schema_version == \"platform.variant/v1\"
        and (.id | type == \"string\" and length > 0)
        and (.path | type == \"string\" and startswith(\"kubernetes/\"))
        and (.execution_adapter.type == \"make\")
        and (.execution_adapter.make_dir == .path)
        and (.state.runtime_scope == .id)
        and (.state.state_file | type == \"string\" and startswith(\"terraform/.run/\"))
        and (.state.state_lock_file | type == \"string\" and startswith(\"terraform/.run/\"))
        and (.cluster_access.kubeconfig_path | type == \"string\" and startswith(\"~/.kube/\"))
        and (.cluster_access.kubeconfig_context | type == \"string\" and length > 0)
        and (.stage_ladder.target_profile_file | type == \"string\")
        and (.stage_ladder.stage_files | keys == [\"100\",\"200\",\"300\",\"400\",\"500\",\"600\",\"700\",\"800\",\"900\",\"920\"])
        and (.readiness.facets | index(\"operator_prereqs\"))
        and (.readiness.facets | index(\"blockers\"))
        and (.blockers.conflicting_variants | type == \"array\")
        and (.registry.runtime_host | type == \"string\" and length > 0)
        and (.registry.push_host | type == \"string\" and length > 0)
        and (.host_access_path.mode | type == \"string\" and length > 0)
        and (.host_access_path.shared_host_ports | index(443))
        and (.network_profile.allowed | type == \"array\" and length > 0)
      " "${contract}" >/dev/null
    done
  '

  [ "${status}" -eq 0 ]
}

@test "variant contracts record current local adapter differences" {
  run bash -c '
    set -euo pipefail
    jq -e "
      .state.state_file == \"terraform/.run/kubernetes/terraform.tfstate\"
      and .cluster_access.kubeconfig_context == \"kind-kind-local\"
      and .registry.runtime_host == \"host.docker.internal:5002\"
      and .host_access_path.mode == \"kind-nodeports\"
      and .host_access_path.requires_proxy == false
    " "${VARIANTS_DIR}/kind/variant.json" >/dev/null

    jq -e "
      .state.state_file == \"terraform/.run/kubernetes-lima/terraform.tfstate\"
      and .cluster_access.kubeconfig_context == \"limavm-k3s\"
      and .registry.runtime_host == \"host.lima.internal:5002\"
      and .host_access_path.mode == \"host-gateway-proxy\"
      and .host_access_path.requires_proxy == true
    " "${VARIANTS_DIR}/lima/variant.json" >/dev/null

    jq -e "
      .state.state_file == \"terraform/.run/kubernetes-slicer/terraform.tfstate\"
      and .cluster_access.kubeconfig_context == \"slicer-k3s\"
      and .registry.runtime_host == \"192.168.64.1:5002\"
      and .host_access_path.mode == \"host-forwards-plus-proxy\"
      and .host_access_path.gateway_forward_port == 8443
      and .network_profile.allowed == [\"cilium\", \"default\"]
    " "${VARIANTS_DIR}/slicer/variant.json" >/dev/null
  '

  [ "${status}" -eq 0 ]
}

@test "variant contracts match current Makefile defaults" {
  run bash -c '
    set -euo pipefail
    for id in kind lima slicer; do
      contract="${VARIANTS_DIR}/${id}/variant.json"
      make_json="$(make --no-print-directory -C "${REPO_ROOT}/kubernetes/${id}" variant-contract-print)"
      jq -e \
        --arg repo_root "${REPO_ROOT}" \
        --arg home "${HOME}" \
        --argjson make_json "${make_json}" \
        "
        def expand_home: sub(\"^~\"; \$home);
        def abs_repo_path: if startswith(\"/\") then . else \$repo_root + \"/\" + . end;
        .id == \$make_json.id
        and .path == \$make_json.path
        and (.state.state_file | abs_repo_path) == \$make_json.state.state_file
        and (.state.state_lock_file | abs_repo_path) == \$make_json.state.state_lock_file
        and (.cluster_access.kubeconfig_path | expand_home) == \$make_json.cluster_access.kubeconfig_path
        and .cluster_access.kubeconfig_context == \$make_json.cluster_access.kubeconfig_context
        and .registry.runtime_host == \$make_json.registry.runtime_host
        and .registry.push_host == \$make_json.registry.push_host
        and .registry.scheme == \$make_json.registry.scheme
        " "${contract}" >/dev/null
    done
  '

  [ "${status}" -eq 0 ]
}
