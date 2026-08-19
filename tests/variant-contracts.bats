#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
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
  '

  [ "${status}" -eq 0 ]
}

@test "variant contracts match current Makefile defaults" {
  run bash -c '
    set -euo pipefail
    for id in kind lima; do
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

@test "kind and lima resolve tfvars through one shared order" {
  terragrunt_mk="${REPO_ROOT}/mk/k8s-terragrunt.mk"
  kind_mk="${REPO_ROOT}/kubernetes/kind/Makefile"
  lima_mk="${REPO_ROOT}/kubernetes/lima/Makefile"

  uv run --isolated python - "${terragrunt_mk}" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()

def assignment(name):
    match = re.search(
        rf"^{re.escape(name)} = ((?:.*\\\n)*.*)$",
        text,
        re.M,
    )
    if not match:
        raise SystemExit(f"missing {name} assignment")
    return re.sub(r"\\\n\s*", " ", match.group(1)).strip()

common = assignment("stack_tfvar_common")
guarded = assignment("stack_tfvar_args")
full = assignment("stack_tfvar_args_full")

expected_common = [
    '--optional-file "$(target_var_file)"',
    "$(stack_tfvar_profile)",
    '--optional-file "$${PLATFORM_BASE_TFVARS:-}"',
    '--optional-file "$${PLATFORM_TFVARS:-}"',
    "$(stack_tfvar_operator)",
]
positions = []
cursor = 0
for token in expected_common:
    at = common.find(token, cursor)
    if at < 0:
        raise SystemExit(f"stack_tfvar_common missing {token!r} after {cursor}: {common}")
    positions.append(at)
    cursor = at + len(token)

stage_guard = '$(if $(filter 1,$(STAGE_SPECIFIED)),--optional-file "$(stage_var_file)")'
if not guarded.startswith(stage_guard):
    raise SystemExit(f"stack_tfvar_args must start with the STAGE_SPECIFIED guard: {guarded}")
if "$(stack_tfvar_common)" not in guarded:
    raise SystemExit(f"stack_tfvar_args must reuse stack_tfvar_common: {guarded}")

if not full.startswith('--optional-file "$(stage_var_file)"'):
    raise SystemExit(f"stack_tfvar_args_full must always include the stage file: {full}")
if "$(stack_tfvar_common)" not in full:
    raise SystemExit(f"stack_tfvar_args_full must reuse stack_tfvar_common: {full}")
PY

  grep -Fq 'stack_tfvar_profile = $(kind_profile_tfvar_arg)' "${kind_mk}"
  grep -Fq 'stack_tfvar_operator = --optional-file "$(KIND_OPERATOR_OVERRIDES_FILE)"' "${kind_mk}"
  ! grep -q 'stack_tfvar_profile' "${lima_mk}"
  ! grep -q 'stack_tfvar_operator' "${lima_mk}"

  uv run --isolated python - "${kind_mk}" "${lima_mk}" <<'PY'
import pathlib
import re
import sys

def blocks(path):
    text = pathlib.Path(path).read_text()
    found = []
    for match in re.finditer(r'"\$\(BUILD_TFVAR_ARGS\)"', text):
        start = match.start()
        line_start = text.rfind("\n", 0, start) + 1
        end = start
        while True:
            line_end = text.find("\n", end)
            if line_end < 0:
                chunk = text[line_start:]
                break
            line = text[end:line_end]
            end = line_end + 1
            if not line.rstrip().endswith("\\"):
                chunk = text[line_start:line_end]
                break
        found.append(chunk)
    return found

for path, expected in ((sys.argv[1], 11), (sys.argv[2], 12)):
    found = blocks(path)
    if len(found) != expected:
        raise SystemExit(f"{path}: expected {expected} BUILD_TFVAR_ARGS sites, found {len(found)}")
    for block in found:
        uses_guarded = "$(stack_tfvar_args)" in block and "$(stack_tfvar_args_full)" not in block
        uses_full = "$(stack_tfvar_args_full)" in block
        if uses_guarded == uses_full:
            raise SystemExit(f"{path}: BUILD_TFVAR_ARGS site must use exactly one shared list:\n{block}")
        if "--optional-file" in block:
            raise SystemExit(f"{path}: BUILD_TFVAR_ARGS site restates --optional-file:\n{block}")
PY

  run make -n -C "${REPO_ROOT}/kubernetes/kind" check-health STAGE=900
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'build-tfvar-args.sh" --execute --format repeated --flag --var-file '* ]]
  [[ "${output}" == *'/stages/900-'* ]]
  [[ "${output}" == *'/targets/kind.tfvars"'* ]]
  [[ "${output}" == *'--optional-file "${PLATFORM_BASE_TFVARS:-}" --optional-file "${PLATFORM_TFVARS:-}"'* ]]
  [[ "${output}" == *'operator-overrides.tfvars"'* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/lima" check-health STAGE=900
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'build-tfvar-args.sh" --execute --format repeated --flag --var-file '* ]]
  [[ "${output}" == *'/stages/900-'* ]]
  [[ "${output}" == *'/targets/lima.tfvars"'* ]]
  [[ "${output}" == *'--optional-file "${PLATFORM_BASE_TFVARS:-}" --optional-file "${PLATFORM_TFVARS:-}"'* ]]
  [[ "${output}" != *'operator-overrides.tfvars"'* ]]
}

@test "kind and lima share the state-reset lifecycle" {
  lifecycle_mk="${REPO_ROOT}/mk/k8s-variant-lifecycle.mk"
  kind_mk="${REPO_ROOT}/kubernetes/kind/Makefile"
  lima_mk="${REPO_ROOT}/kubernetes/lima/Makefile"

  grep -Fq 'include ../../mk/k8s-variant-lifecycle.mk' "${kind_mk}"
  grep -Fq 'include ../../mk/k8s-variant-lifecycle.mk' "${lima_mk}"
  grep -Fq 'lock_file="$(STATE_LOCK_FILE)"' "${lifecycle_mk}"
  ! grep -q 'lock_file="$(STATE_LOCK_FILE)"' "${kind_mk}"
  ! grep -q 'lock_file="$(STATE_LOCK_FILE)"' "${lima_mk}"
}

@test "kind and lima share check-kubeconfig lint and gitea-sync" {
  lifecycle_mk="${REPO_ROOT}/mk/k8s-variant-lifecycle.mk"
  kind_mk="${REPO_ROOT}/kubernetes/kind/Makefile"
  lima_mk="${REPO_ROOT}/kubernetes/lima/Makefile"

  grep -Fq '$(check_kubeconfig_body)' "${kind_mk}"
  grep -Fq '$(check_kubeconfig_body)' "${lima_mk}"
  grep -Fq 'define check_kubeconfig_body' "${lifecycle_mk}"
  ! grep -q 'kubie lint' "${kind_mk}"
  ! grep -q 'kubie lint' "${lima_mk}"

  grep -Fq 'GITEA_SYNC_KUBECONFIG_TARGET = ensure-kind-kubeconfig' "${kind_mk}"
  grep -Fq 'GITEA_SYNC_ASSERT_TARGET = assert-kind-active' "${kind_mk}"
  grep -Fq 'GITEA_LOCAL_ACCESS_MODE_DEFAULT = nodeport' "${kind_mk}"
  grep -Fq 'GITEA_SYNC_KUBECONFIG_TARGET = check-kubeconfig' "${lima_mk}"
  grep -Fq 'GITEA_SYNC_ASSERT_TARGET = assert-lima-active' "${lima_mk}"
  grep -Fq 'GITEA_LOCAL_ACCESS_MODE_DEFAULT = port-forward' "${lima_mk}"
  ! grep -q '^gitea-sync:' "${kind_mk}"
  ! grep -q '^gitea-sync:' "${lima_mk}"
  grep -q '^gitea-sync:' "${lifecycle_mk}"

  grep -Fq 'CONFLICTING_CLUSTER_CHECK = check-lima-stopped' "${kind_mk}"
  grep -Fq 'CONFLICTING_CLUSTER_CHECK = check-kind-stopped' "${lima_mk}"
  ! grep -q '^check-conflicting-clusters-stopped:' "${kind_mk}"
  ! grep -q '^check-conflicting-clusters-stopped:' "${lima_mk}"
}
