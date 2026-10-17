#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

migrated_entrypoints() {
  printf '%s\n' \
    apps/shared/keycloak/start-with-templated-realm.sh \
    apps/subnetcalc/update-subnetcalc-image-tags.sh \
    kubernetes/kind/scripts/rewrite-devcontainer-kubeconfig.sh \
    kubernetes/kind/scripts/run-bats-shards.sh \
    kubernetes/scripts/idp-preview-action-catalog.sh \
    kubernetes/scripts/plan-post-apply-verification.sh \
    kubernetes/scripts/reconcile-kubeconfig.sh \
    kubernetes/scripts/run-diagnostic-check.sh \
    kubernetes/scripts/run-post-apply-verification.sh \
    kubernetes/workflow/validate-image-catalog-target-refs.sh \
    scripts/check-make-target-surfaces.sh \
    scripts/make-known-goals.sh \
    scripts/platform-status-action-catalog.sh \
    scripts/run-bats-shards.sh \
    scripts/validate-json-schema.sh \
    terraform/kubernetes/scripts/render-kind-apiserver-oidc-manifest.sh
}

interface_command() {
  if [[ "${INTERFACE_TEST_SHELL}" == "bash32" ]]; then
    /bin/bash "$@"
  else
    "$@"
  fi
}

@test "migrated shell entrypoints preview before operational requirements" {
  for INTERFACE_TEST_SHELL in native bash32; do
    while IFS= read -r relative; do
      printf '# checking %s (%s)\n' "${relative}" "${INTERFACE_TEST_SHELL}" >&3
      script="${REPO_ROOT}/${relative}"
      run interface_command "${script}"
      [ "${status}" -eq 0 ]
      [[ "${output}" == *"Usage:"* ]] || return 1
      [[ "${output}" == *"INFO dry-run:"* ]] || return 1
      run interface_command "${script}" --help
      [ "${status}" -eq 0 ]
      [[ "${output}" == *"Usage:"* ]] || return 1
      run interface_command "${script}" --dry-run
      [ "${status}" -eq 0 ]
      [[ "${output}" == *"INFO dry-run:"* ]] || return 1
      run interface_command "${script}" --dry-run --execute
      [ "${status}" -eq 0 ]
      [[ "${output}" == *"INFO dry-run:"* ]] || return 1
    done < <(migrated_entrypoints)
  done
}

@test "migrated shell entrypoint descriptors identify their filenames and safe default" {
  for INTERFACE_TEST_SHELL in native bash32; do
    while IFS= read -r relative; do
      printf '# checking %s (%s)\n' "${relative}" "${INTERFACE_TEST_SHELL}" >&3
      run interface_command "${REPO_ROOT}/${relative}" --shell-entrypoint-descriptor
      [ "${status}" -eq 0 ]
      descriptor="${output}"
      run jq -e --arg filename "${relative##*/}" \
        '.schema_version == "shell-entrypoint/v1" and .name == $filename and (.path | endswith("/" + $filename)) and .default_mode == "dry-run" and (.supports | sort) == (["--help", "--dry-run", "--execute"] | sort)' <<<"${descriptor}"
      [ "${status}" -eq 0 ]
    done < <(migrated_entrypoints)
  done
}

@test "migrated operational helpers refuse execution with missing required arguments" {
  for INTERFACE_TEST_SHELL in native bash32; do
    for relative in \
      kubernetes/kind/scripts/rewrite-devcontainer-kubeconfig.sh \
      terraform/kubernetes/scripts/render-kind-apiserver-oidc-manifest.sh \
      kubernetes/scripts/reconcile-kubeconfig.sh \
      kubernetes/scripts/plan-post-apply-verification.sh \
      kubernetes/scripts/run-diagnostic-check.sh \
      kubernetes/scripts/run-post-apply-verification.sh; do
      printf '# checking %s\n' "${relative}" >&3
      run interface_command "${REPO_ROOT}/${relative}" --execute
      [ "${status}" -ne 0 ]
      case "${relative}" in
        *rewrite-devcontainer-kubeconfig.sh) expected="expected 3 positional arguments" ;;
        *render-kind-apiserver-oidc-manifest.sh) expected="expected 7 positional arguments" ;;
        *reconcile-kubeconfig.sh) expected="--source-kubeconfig is required" ;;
        *) expected="missing --variant-json" ;;
      esac
      [[ "${output}" == *"${expected}"* ]] || return 1
      [[ "${output}" != *"command not found"* ]] || return 1
    done
  done
}

@test "standalone Keycloak entrypoint previews and refuses missing template without writing" {
  fixture="${BATS_TEST_TMPDIR}/keycloak"
  mkdir -p "${fixture}/bin"
  sed "s|/opt/keycloak|${fixture}|g" "${REPO_ROOT}/apps/shared/keycloak/start-with-templated-realm.sh" >"${fixture}/start.sh"
  for mode in '' --help --dry-run '--dry-run --execute'; do
    # The fixture entrypoint is self-contained and runs under POSIX sh.
    if [[ -z "${mode}" ]]; then
      run sh "${fixture}/start.sh"
    elif [[ "${mode}" == '--dry-run --execute' ]]; then
      run sh "${fixture}/start.sh" --dry-run --execute
    else
      run sh "${fixture}/start.sh" "${mode}"
    fi
    [ "${status}" -eq 0 ]
    [ ! -e "${fixture}/data" ]
  done
  run sh "${fixture}/start.sh" --execute
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Missing realm template:"* ]] || return 1
  [ ! -e "${fixture}/data" ]
}

@test "standalone Keycloak execution renders secrets and delegates to the server" {
  fixture="${BATS_TEST_TMPDIR}/keycloak"
  mkdir -p "${fixture}/bin" "${fixture}/local"
  sed "s|/opt/keycloak|${fixture}|g" "${REPO_ROOT}/apps/shared/keycloak/start-with-templated-realm.sh" >"${fixture}/start.sh"
  printf '%s\n' '{"client":"${OAUTH2_PROXY_CLIENT_SECRET}","password":"${KEYCLOAK_DEMO_PASSWORD}"}' >"${fixture}/local/realm-export.template.json"
  cat >"${fixture}/bin/kc.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >"${KEYCLOAK_TEST_CALLS}"
SH
  chmod +x "${fixture}/bin/kc.sh"
  run env OAUTH2_PROXY_CLIENT_SECRET='client&/secret|tail' KEYCLOAK_DEMO_PASSWORD='demo&/password|tail' KEYCLOAK_TEST_CALLS="${fixture}/calls" sh "${fixture}/start.sh" --execute
  [ "${status}" -eq 0 ]
  [ "$(cat "${fixture}/data/import/realm-export.json")" = '{"client":"client&/secret|tail","password":"demo&/password|tail"}' ]
  [ "$(cat "${fixture}/calls")" = $'start-dev\n--import-realm' ]
}

@test "shell audit exempts only the external Docker credential helper protocol" {
  run awk '/^entrypoint_interface_exemptions=\(/ { inside=1; next } inside && /^\)/ { exit } inside { print }' "${REPO_ROOT}/scripts/audit-shell-scripts.sh"
  [ "${status}" -eq 0 ]
  [ "${output}" = '  "kubernetes/scripts/docker-credential-platform-file.sh"' ]
}
