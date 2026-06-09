#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/sync-gitea-app-repo.sh"
}

@test "app repo sync contract loads repo-specific values into sync-gitea-repo interface" {
  contract_file="${BATS_TEST_TMPDIR}/app-repo-sync-contract.json"
  cat >"${contract_file}" <<'EOF'
{
  "source_dir": "/work/apps/sentiment",
  "repo_name": "sentiment",
  "repo_owner": "platform",
  "repo_is_org": true,
  "repo_owner_fallback": "gitea-admin",
  "deploy_key_title": "ci-sentiment-key"
}
EOF

  run bash -lc "export APP_REPO_SYNC_CONTRACT_FILE='${contract_file}'; source '${SCRIPT}'; load_app_repo_sync_contract_defaults; printf '%s\n' \"\$SOURCE_DIR\" \"\$GITEA_REPO_NAME\" \"\$GITEA_REPO_OWNER\" \"\$GITEA_REPO_OWNER_IS_ORG\" \"\$GITEA_REPO_OWNER_FALLBACK\" \"\$DEPLOY_KEY_TITLE\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '/work/apps/sentiment\nsentiment\nplatform\ntrue\ngitea-admin\nci-sentiment-key')" ]
}

@test "app repo sync exports contract values before delegating" {
  contract_file="${BATS_TEST_TMPDIR}/app-repo-sync-contract.json"
  helper_dir="${BATS_TEST_TMPDIR}/helpers"
  capture_file="${BATS_TEST_TMPDIR}/delegated-env"
  mkdir -p "${helper_dir}"
  cat >"${contract_file}" <<'EOF'
{
  "source_dir": "/work/apps/subnetcalc",
  "repo_name": "subnetcalc",
  "repo_owner": "platform",
  "repo_is_org": true,
  "repo_owner_fallback": "gitea-admin",
  "deploy_key_title": "ci-subnetcalc-key"
}
EOF
  cat >"${helper_dir}/sync-gitea-repo.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\n' "${SOURCE_DIR:-}"
  printf '%s\n' "${GITEA_REPO_NAME:-}"
  printf '%s\n' "${GITEA_REPO_OWNER:-}"
  printf '%s\n' "${GITEA_REPO_OWNER_IS_ORG:-}"
  printf '%s\n' "${GITEA_REPO_OWNER_FALLBACK:-}"
  printf '%s\n' "${DEPLOY_KEY_TITLE:-}"
} >"${CAPTURE_FILE:?}"
EOF
  chmod +x "${helper_dir}/sync-gitea-repo.sh"
  cp "${SCRIPT}" "${helper_dir}/sync-gitea-app-repo.sh"
  chmod +x "${helper_dir}/sync-gitea-app-repo.sh"

  run env \
    APP_REPO_SYNC_CONTRACT_FILE="${contract_file}" \
    REPO_ROOT="${REPO_ROOT}" \
    STACK_DIR="${BATS_TEST_TMPDIR}/stack" \
    DEPLOY_PUBLIC_KEY="ssh-ed25519 test" \
    SSH_PRIVATE_KEY_PATH="${BATS_TEST_TMPDIR}/id_ed25519" \
    CAPTURE_FILE="${capture_file}" \
    bash "${helper_dir}/sync-gitea-app-repo.sh" --execute

  [ "${status}" -eq 0 ]
  [ "$(cat "${capture_file}")" = "$(printf '/work/apps/subnetcalc\nsubnetcalc\nplatform\ntrue\ngitea-admin\nci-subnetcalc-key')" ]
}

@test "app repo sync projects extra source dirs into delegated repo content" {
  contract_file="${BATS_TEST_TMPDIR}/app-repo-sync-contract.json"
  helper_dir="${BATS_TEST_TMPDIR}/helpers"
  source_dir="${BATS_TEST_TMPDIR}/source"
  extra_dir="${BATS_TEST_TMPDIR}/apim-source"
  capture_file="${BATS_TEST_TMPDIR}/delegated-tree"
  mkdir -p "${helper_dir}" "${source_dir}" "${extra_dir}"
  printf 'base\n' >"${source_dir}/base.txt"
  printf 'apim\n' >"${extra_dir}/service.txt"
  cat >"${contract_file}" <<EOF
{
  "source_dir": "${source_dir}",
  "repo_name": "subnetcalc",
  "repo_owner": "platform",
  "repo_is_org": true,
  "repo_owner_fallback": "gitea-admin",
  "deploy_key_title": "ci-subnetcalc-key",
  "extra_source_dirs": [
    {
      "source_dir": "${extra_dir}",
      "target_dir": "apim-simulator"
    }
  ]
}
EOF
  cat >"${helper_dir}/sync-gitea-repo.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
find "${SOURCE_DIR:?}" -maxdepth 2 -type f -print \
  | sed "s#^${SOURCE_DIR}/##" \
  | sort >"${CAPTURE_FILE:?}"
EOF
  chmod +x "${helper_dir}/sync-gitea-repo.sh"
  cp "${SCRIPT}" "${helper_dir}/sync-gitea-app-repo.sh"
  chmod +x "${helper_dir}/sync-gitea-app-repo.sh"

  run env \
    APP_REPO_SYNC_CONTRACT_FILE="${contract_file}" \
    REPO_ROOT="${REPO_ROOT}" \
    STACK_DIR="${BATS_TEST_TMPDIR}/stack" \
    DEPLOY_PUBLIC_KEY="ssh-ed25519 test" \
    SSH_PRIVATE_KEY_PATH="${BATS_TEST_TMPDIR}/id_ed25519" \
    CAPTURE_FILE="${capture_file}" \
    bash "${helper_dir}/sync-gitea-app-repo.sh" --execute

  [ "${status}" -eq 0 ]
  [ "$(cat "${capture_file}")" = "$(printf 'apim-simulator/service.txt\nbase.txt')" ]
}

@test "Terraform app repo sync resources delegate repo-specific values to shared helper" {
  gitops_tf="${REPO_ROOT}/terraform/kubernetes/gitops.tf"

  sentiment_block="$(sed -n '/resource \"null_resource\" \"sync_gitea_app_repo_sentiment\"/,/^}/p' "${gitops_tf}")"
  subnetcalc_block="$(sed -n '/resource \"null_resource\" \"sync_gitea_app_repo_subnetcalc\"/,/^}/p' "${gitops_tf}")"

  [[ "${sentiment_block}" == *"sync-gitea-app-repo.sh"* ]]
  [[ "${sentiment_block}" == *"--execute"* ]]
  [[ "${subnetcalc_block}" == *"sync-gitea-app-repo.sh"* ]]
  [[ "${subnetcalc_block}" == *"--execute"* ]]
  [[ "${sentiment_block}" == *"APP_REPO_SYNC_CONTRACT_FILE"* ]]
  [[ "${subnetcalc_block}" == *"APP_REPO_SYNC_CONTRACT_FILE"* ]]

  for block in "${sentiment_block}" "${subnetcalc_block}"; do
    [[ "${block}" != *"SOURCE_DIR"* ]]
    [[ "${block}" != *"GITEA_REPO_NAME"* ]]
    [[ "${block}" != *"DEPLOY_KEY_TITLE"* ]]
    [[ "${block}" != *"GITEA_REPO_OWNER_IS_ORG"* ]]
    [[ "${block}" != *"GITEA_REPO_OWNER_FALLBACK"* ]]
  done
}

@test "app repo sync contracts project shared source" {
  locals_tf="${REPO_ROOT}/terraform/kubernetes/locals.tf"

  grep -Eq 'app_shared_source_dir[[:space:]]*= abspath\("\$\{local\.monorepo_apps_dir\}/shared"\)' "${locals_tf}"
  grep -Eq 'target_dir[[:space:]]*= "shared"' "${locals_tf}"
  grep -Eq 'extra_source_dirs[[:space:]]*= local\.sentiment_app_extra_source_dirs' "${locals_tf}"
  grep -Eq 'extra_source_dirs[[:space:]]*= local\.subnetcalc_app_extra_source_dirs' "${locals_tf}"
}

@test "subnetcalc app repo sync contract projects APIM simulator source" {
  locals_tf="${REPO_ROOT}/terraform/kubernetes/locals.tf"

  grep -Eq 'extra_source_dirs[[:space:]]*= local\.subnetcalc_app_extra_source_dirs' "${locals_tf}"
  grep -Eq 'source_dir[[:space:]]*= abspath\("\$\{local\.monorepo_apps_dir\}/apim-simulator"\)' "${locals_tf}"
  grep -Eq 'target_dir[[:space:]]*= "apim-simulator"' "${locals_tf}"
}

@test "subnetcalc workflow stamps policies with built image tags" {
  workflow="${REPO_ROOT}/apps/subnetcalc/.gitea/workflows/build-images.yaml"
  stamp_script="${REPO_ROOT}/apps/subnetcalc/update-subnetcalc-image-tags.sh"

  grep -Fq '"update-subnetcalc-image-tags.sh"' "${workflow}"
  grep -Fq "bash update-subnetcalc-image-tags.sh" "${workflow}"
  grep -Fq "subnetcalc-apim-simulator" "${workflow}"
  grep -Fq "apps/apim/all.yaml" "${stamp_script}"
  grep -Fq '"subnetcalc-apim-simulator"' "${stamp_script}"
}

@test "subnetcalc workflow clones the synced app repo name" {
  workflow="${REPO_ROOT}/apps/subnetcalc/.gitea/workflows/build-images.yaml"

  grep -Fq "APP_REPO_NAME: subnetcalc" "${workflow}"
  grep -Fq '${GITEA_HTTP_BASE}/${GITEA_REPO_OWNER}/${APP_REPO_NAME}.git' "${workflow}"
  ! grep -Fq "subnet-calculator.git" "${workflow}"
}

@test "app Gitea workflows rebuild when shared app libraries change" {
  for workflow in \
    "${REPO_ROOT}/apps/sentiment/.gitea/workflows/build-images.yaml" \
    "${REPO_ROOT}/apps/subnetcalc/.gitea/workflows/build-images.yaml" \
    "${REPO_ROOT}/apps/chatgpt-sim/.gitea/workflows/build-images.yaml"; do
    grep -Fq '"shared/**"' "${workflow}"
    grep -Fq -- '-v "${APPS_DIR}/shared:/shared:ro"' "${workflow}"
    ! grep -Fq "COPY shared /shared" "${workflow}"
  done
}

@test "subnetcalc workflow Dockerfiles avoid remote Dockerfile frontend pulls" {
  dockerfile="${REPO_ROOT}/apps/subnetcalc/app/Dockerfile"
  ! head -n 1 "${dockerfile}" | grep -Fq '# syntax=docker/dockerfile'
}
