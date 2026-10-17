#!/usr/bin/env bats

setup() {
  local repo_root
  repo_root="$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)"
  export FIXTURE_ROOT="${BATS_TEST_TMPDIR}/standalone"
  export HOME="${FIXTURE_ROOT}/home"
  export MOCK_LOG="${FIXTURE_ROOT}/git.log"
  export MOCK_MANIFESTS="${FIXTURE_ROOT}/manifests"
  export MOCK_RESULT="${FIXTURE_ROOT}/result"
  mkdir -p "${FIXTURE_ROOT}/app" "${FIXTURE_ROOT}/bin" "$HOME" "${MOCK_MANIFESTS}/apps/workloads/base"
  cp "${repo_root}/apps/subnetcalc/update-subnetcalc-image-tags.sh" "${FIXTURE_ROOT}/app/update-subnetcalc-image-tags.sh"
  export SCRIPT="${FIXTURE_ROOT}/app/update-subnetcalc-image-tags.sh"
  export PATH="${FIXTURE_ROOT}/bin:${PATH}"
  unset GITEA_HTTP_BASE GITEA_REPO_OWNER REGISTRY_HOST TAG REGISTRY_USERNAME REGISTRY_PWD
  cat >"${MOCK_MANIFESTS}/apps/workloads/base/all.yaml" <<'YAML'
image: old.example/team/subnetcalc-api:old
image: old.example/team/subnetcalc-frontend:old
image: old.example/team/subnetcalc-apim-simulator:old
image: old.example/team/unrelated:keep
YAML
  cat >"${FIXTURE_ROOT}/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"${MOCK_LOG}"
case "$1" in
  credential-store) cat >/dev/null ;;
  clone)
    for destination do :; done
    mkdir -p "$destination"
    cp -R "${MOCK_MANIFESTS}/." "$destination/"
    ;;
  config|fetch|checkout|add) ;;
  diff) [ "${MOCK_UNCHANGED:-0}" -eq 1 ] ;;
  commit) mkdir -p "${MOCK_RESULT}"; cp -R apps "${MOCK_RESULT}/" ;;
  push)
    if [ "${MOCK_RETRY:-0}" -eq 1 ] && [ ! -e "${FIXTURE_ROOT}/push-attempted" ]; then
      touch "${FIXTURE_ROOT}/push-attempted"
      exit 1
    fi
    ;;
  reset) cp -R "${MOCK_MANIFESTS}/." ./ ;;
  *) exit 99 ;;
esac
MOCK
  chmod +x "${FIXTURE_ROOT}/bin/git"
}

execute_fixture() {
  env GITEA_HTTP_BASE=https://gitea.example GITEA_REPO_OWNER=team \
    REGISTRY_HOST=registry.example TAG=verified REGISTRY_USERNAME=fixture \
    REGISTRY_PWD=synthetic-password PUSH_RETRY_SLEEP_SECONDS=0 \
    bash "$SCRIPT" "$@"
}

@test "standalone image updater bare invocation and help need no Platform library or credentials" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: update-subnetcalc-image-tags.sh"* ]] || return 1
  [[ "$output" == *"INFO dry-run:"* ]] || return 1
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--execute"* ]] || return 1
  [ ! -e "$MOCK_LOG" ]
}

@test "standalone image updater descriptor is machine-readable without side effects" {
  run bash "$SCRIPT" --shell-entrypoint-descriptor
  [ "$status" -eq 0 ]
  run jq -e --arg script "$SCRIPT" '(.schema_version == "shell-entrypoint/v1") and (.name == "update-subnetcalc-image-tags.sh") and (.path == $script) and (.supports == ["--help","--dry-run","--execute"]) and (.default_mode == "dry-run")' <<< "$output"
  [ "$status" -eq 0 ]
  [ ! -e "$MOCK_LOG" ]
}

@test "standalone image updater dry-run dominates execute in either argument order" {
  run bash "$SCRIPT" --execute --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO dry-run:"* ]] || return 1
  run bash "$SCRIPT" --dry-run --execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO dry-run:"* ]] || return 1
  [ ! -e "$MOCK_LOG" ]
}

@test "standalone image updater refuses unknown arguments before Git writes" {
  run execute_fixture --execute --unexpected
  [ "$status" -ne 0 ]
  [[ "$output" == *"unrecognized argument: --unexpected"* ]] || return 1
  run execute_fixture --execute accidental
  [ "$status" -ne 0 ]
  [[ "$output" == *"unrecognized argument: accidental"* ]] || return 1
  [ ! -e "$MOCK_LOG" ]
}

@test "standalone image updater explicit execution still requires credentials" {
  run bash "$SCRIPT" --execute
  [ "$status" -ne 0 ]
  [[ "$output" == *"GITEA_HTTP_BASE is required"* ]] || return 1
  [ ! -e "$MOCK_LOG" ]
}

@test "standalone image updater execute rewrites intended tags and pushes the policies branch" {
  run execute_fixture --execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated policies manifests to verified"* ]] || return 1
  grep -Fxq 'image: registry.example/team/subnetcalc-api:verified' "${MOCK_RESULT}/apps/workloads/base/all.yaml"
  grep -Fxq 'image: registry.example/team/subnetcalc-frontend:verified' "${MOCK_RESULT}/apps/workloads/base/all.yaml"
  grep -Fxq 'image: registry.example/team/subnetcalc-apim-simulator:verified' "${MOCK_RESULT}/apps/workloads/base/all.yaml"
  grep -Fxq 'image: old.example/team/unrelated:keep' "${MOCK_RESULT}/apps/workloads/base/all.yaml"
  grep -Fxq 'push origin HEAD:main' "$MOCK_LOG"
  run grep -F 'synthetic-password' "$MOCK_LOG"
  [ "$status" -eq 1 ]
}

@test "standalone image updater unchanged manifests do not commit or push" {
  export MOCK_UNCHANGED=1
  run execute_fixture --execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"Manifest already contained verified"* ]] || return 1
  run grep -E '^(commit|push) ' "$MOCK_LOG"
  [ "$status" -eq 1 ]
}

@test "standalone image updater retries rejected pushes and rewrites after reset" {
  export MOCK_RETRY=1
  run execute_fixture --execute
  [ "$status" -eq 0 ]
  [ "$(grep -c '^push ' "$MOCK_LOG")" -eq 2 ]
  grep -Fxq 'reset --hard origin/main' "$MOCK_LOG"
  grep -Fxq 'image: registry.example/team/subnetcalc-api:verified' "${MOCK_RESULT}/apps/workloads/base/all.yaml"
}
