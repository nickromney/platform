#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export CATALOG="${REPO_ROOT}/catalog/platform-apps.json"
}

@test "IDP catalog declares app ownership environments RBAC secrets and deployment evidence" {
  [ -f "${CATALOG}" ]

  run jq -e '
    .schema_version == "platform.idp/v1" and
    (.applications | length) >= 3 and
    any(.applications[]; .name == "hello-platform" and .owner == "team-dolphin") and
    any(.applications[]; .name == "subnetcalc" and any(.environments[]; .name == "dev" and .rbac.group == "app-subnetcalc-dev")) and
    any(.applications[]; .name == "sentiment" and any(.environments[]; .name == "uat" and .rbac.group == "app-sentiment-uat")) and
    all(.applications[]; has("deployment") and has("secrets") and has("scorecard"))
  ' "${CATALOG}"

  [ "${status}" -eq 0 ]
}

@test "hello-platform is a real checked-in workload with dev and UAT promotion overlays" {
  for path in \
    terraform/kubernetes/apps/workloads/hello-platform/all.yaml \
    terraform/kubernetes/apps/workloads/hello-platform/kustomization.yaml \
    terraform/kubernetes/apps/dev/hello-platform-image-patch.yaml \
    terraform/kubernetes/apps/uat/hello-platform-image-patch.yaml \
    terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-hello-platform-dev.yaml \
    terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-hello-platform-uat.yaml \
    terraform/kubernetes/cluster-policies/cilium/projects/hello-platform/hello-platform-ingress.yaml
  do
    [ -f "${REPO_ROOT}/${path}" ]
  done

  run rg -n '../workloads/hello-platform|hello-platform-image-patch.yaml' \
    "${REPO_ROOT}/terraform/kubernetes/apps/dev/kustomization.yaml" \
    "${REPO_ROOT}/terraform/kubernetes/apps/uat/kustomization.yaml"
  [ "${status}" -eq 0 ]

  run rg -n 'httproute-hello-platform-dev.yaml|httproute-hello-platform-uat.yaml' \
    "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/kustomization.yaml"
  [ "${status}" -eq 0 ]
}

@test "hello-platform SSO routes are permitted by the sso namespace ReferenceGrant" {
  grant="${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/referencegrant-sso.yaml"

  for service in \
    oauth2-proxy-hello-platform-dev \
    oauth2-proxy-hello-platform-uat
  do
    run rg -n "name: ${service}" "${grant}"
    [ "${status}" -eq 0 ]
  done
}

@test "developer portal and API have public portal gateway routes" {
  for path in \
    terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-portal.yaml \
    terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-portal-api.yaml
  do
    [ -f "${REPO_ROOT}/${path}" ]
  done

  run rg -n 'httproute-portal.yaml|httproute-portal-api.yaml' \
    "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/kustomization.yaml"
  [ "${status}" -eq 0 ]

  run rg -n 'portal\.127\.0\.0\.1\.sslip\.io' \
    "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-portal.yaml"
  [ "${status}" -eq 0 ]

  run rg -n 'portal-api\.127\.0\.0\.1\.sslip\.io' \
    "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/httproute-portal-api.yaml"
  [ "${status}" -eq 0 ]
}

@test "developer portal gateway routes are permitted by the sso namespace ReferenceGrant" {
  grant="${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/referencegrant-sso.yaml"

  for service in \
    oauth2-proxy-idp-portal \
    oauth2-proxy-idp-core
  do
    run rg -n "name: ${service}" "${grant}"
    [ "${status}" -eq 0 ]
  done
}

@test "app and environment authorization uses Keycloak groups instead of email-domain shortcuts" {
  for group in \
    app-subnetcalc-dev \
    app-subnetcalc-uat \
    app-sentiment-dev \
    app-sentiment-uat \
    app-hello-platform-dev \
    app-hello-platform-uat
  do
    run rg -n "${group}" "${REPO_ROOT}/terraform/kubernetes/sso.tf" "${REPO_ROOT}/terraform/kubernetes/locals.tf"
    [ "${status}" -eq 0 ]
  done

  run rg -n 'allowed-group: app-(subnetcalc|sentiment)-(dev|uat)' "${REPO_ROOT}/terraform/kubernetes/sso.tf"
  [ "${status}" -eq 0 ]

  run rg -n 'allowed-group: \$\{each\.value\.group\}' "${REPO_ROOT}/terraform/kubernetes/sso.tf"
  [ "${status}" -eq 0 ]

  run rg -n 'email-domain: "(dev|uat)\\.test"' "${REPO_ROOT}/terraform/kubernetes/sso.tf"
  [ "${status}" -ne 0 ]
}

@test "Keycloak realm bootstrap includes app callbacks and a requestable groups client scope" {
  realm_tf="${REPO_ROOT}/terraform/kubernetes/sso.tf"

  for expected in \
    'clientScopes = [' \
    'name        = local.sso_groups_claim' \
    'optionalClientScopes = [local.sso_groups_claim]' \
    '${local.hello_platform_dev_public_url}/oauth2/callback' \
    '${local.hello_platform_uat_public_url}/oauth2/callback' \
    '${local.idp_portal_public_url}/oauth2/callback' \
    '${local.idp_api_public_url}/oauth2/callback'
  do
    run rg -n -F "${expected}" "${realm_tf}"
    [ "${status}" -eq 0 ]
  done

  run rg -n 'resource "null_resource" "reconcile_keycloak_realm"' "${realm_tf}"
  [ "${status}" -eq 0 ]
}

@test "launchpad and IDP catalog use portal public FQDNs" {
  launchpad="${REPO_ROOT}/terraform/kubernetes/config/platform-launchpad.apps.json"
  catalog="${REPO_ROOT}/catalog/platform-apps.json"

  run jq -e '.tiles[] | select(.title == "Developer Portal") | .url == "https://portal.127.0.0.1.sslip.io"' "${launchpad}"
  [ "${status}" -eq 0 ]

  run jq -e '.tiles[] | select(.title == "Portal API") | .url == "https://portal-api.127.0.0.1.sslip.io"' "${launchpad}"
  [ "${status}" -eq 0 ]

  run jq -e '
    any(.applications[]; .name == "idp-portal" and any(.environments[]; .route == "https://portal.127.0.0.1.sslip.io")) and
    any(.applications[]; .name == "idp-core" and any(.environments[]; .route == "https://portal-api.127.0.0.1.sslip.io"))
  ' "${catalog}"
  [ "${status}" -eq 0 ]
}

@test "APIM uses a dedicated stage-900 resource audience without owning subnetcalc or compose auth" {
  realm_tf="${REPO_ROOT}/terraform/kubernetes/sso.tf"
  apim_manifest="${REPO_ROOT}/terraform/kubernetes/apps/apim/all.yaml"
  compose_stack="${REPO_ROOT}/docker/compose/compose.yml"
  subnetcalc_compose="${REPO_ROOT}/apps/subnetcalc/compose.yml"
  contracts="${REPO_ROOT}/docs/ddd/contracts.md"
  glossary="${REPO_ROOT}/docs/ddd/ubiquitous-language.md"

  run rg -n 'sso_apim_audience\s*=\s*"apim-simulator"' "${REPO_ROOT}/terraform/kubernetes/locals.tf"
  [ "${status}" -eq 0 ]

  run rg -n 'clientId\s*=\s*local\.sso_apim_audience|included\.client\.audience.*local\.sso_apim_audience' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n '"audience": "apim-simulator"' "${apim_manifest}"
  [ "${status}" -eq 0 ]

  run rg -n 'oidc-issuer-url=https://dex\.compose\.127\.0\.0\.1\.sslip\.io:8443/dex' "${compose_stack}"
  [ "${status}" -eq 0 ]

  run rg -n 'AUTH_METHOD=none' "${subnetcalc_compose}"
  [ "${status}" -eq 0 ]

  run rg -n 'profiles: \["oidc"\]' "${subnetcalc_compose}"
  [ "${status}" -eq 0 ]

  for term in \
    "resource audience" \
    "portable auth mode" \
    "apim-simulator"
  do
    run rg -n "${term}" "${contracts}" "${glossary}"
    [ "${status}" -eq 0 ]
  done
}

@test "Keycloak admin console lands on the platform realm and uses a permanent admin lifecycle" {
  realm_tf="${REPO_ROOT}/terraform/kubernetes/sso.tf"
  reconcile_script="${REPO_ROOT}/terraform/kubernetes/scripts/reconcile-keycloak-realm.sh"
  launchpad="${REPO_ROOT}/terraform/kubernetes/config/platform-launchpad.apps.json"
  e2e="${REPO_ROOT}/tests/kubernetes/sso/tests/sso-smoke.spec.ts"

  run rg -n 'resource "kubernetes_secret_v1" "keycloak_bootstrap_admin"' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'resource "kubernetes_secret_v1" "keycloak_admin"' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'name: keycloak-bootstrap-admin' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'KEYCLOAK_PERMANENT_ADMIN_SECRET|ensure_master_admin|delete_bootstrap_admins_from_master' "${reconcile_script}"
  [ "${status}" -eq 0 ]

  run rg -n 'ensure_group_client_role "platform-admins" "realm-management" "realm-admin"' "${reconcile_script}"
  [ "${status}" -eq 0 ]

  run rg -n 'defaultClientScopes\s*=\s*\["web-origins", "acr", "profile", "basic", "email"\]' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'reconcile_client_scope_attachments|detach_client_scope_attachment' "${reconcile_script}"
  [ "${status}" -eq 0 ]

  run jq -e '.tiles[] | select(.title == "Keycloak") | .url == "https://keycloak.127.0.0.1.sslip.io/admin/platform/console/#/platform/users"' "${launchpad}"
  [ "${status}" -eq 0 ]

  run rg -n "KEYCLOAK_CONSOLE_ADMIN_LOGIN.*'demo@admin.test'" "${e2e}"
  [ "${status}" -eq 0 ]
}

@test "Keycloak realm reconcile explicitly attaches rendered client scopes" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/reconcile-keycloak-realm.sh"

  run rg -n 'ensure_client_scope_attachment "\$\{client_uuid\}" "optional" "\$\{scope_name\}"' "${script}"
  [ "${status}" -eq 0 ]
}

@test "oauth2-proxy uses an internal session store for Keycloak token sessions" {
  realm_tf="${REPO_ROOT}/terraform/kubernetes/sso.tf"

  run rg -n 'resource "kubectl_manifest" "oauth2_proxy_session_store_deployment"' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'session-store-type: redis' "${realm_tf}"
  [ "${status}" -eq 0 ]

  run rg -n 'redis-connection-url: \$\{local\.oauth2_proxy_redis_url\}' "${realm_tf}"
  [ "${status}" -eq 0 ]
}

@test "admin SSO proxies use org groups rather than admin email-domain shortcuts" {
  run rg -n 'allowed-group: \$\{local\.sso_(admin|viewer)_group\}' "${REPO_ROOT}/terraform/kubernetes/sso.tf"
  [ "${status}" -eq 0 ]

  run rg -n 'email-domain: "admin\\.test"' "${REPO_ROOT}/terraform/kubernetes/sso.tf"
  [ "${status}" -ne 0 ]
}

@test "kind exposes self-service IDP commands as dry-run friendly operator surfaces" {
  run make -C "${REPO_ROOT}/kubernetes/kind" help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make idp-catalog"* ]]
  [[ "${output}" == *"make idp-env ACTION=create APP=hello-platform ENV=preview-nr"* ]]
  [[ "${output}" == *"make idp-deployments"* ]]
  [[ "${output}" == *"make idp-secrets"* ]]

  run make -C "${REPO_ROOT}/kubernetes/kind" idp-catalog DRY_RUN=1
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"would inspect the IDP service catalog"* ]]

  run make -C "${REPO_ROOT}/kubernetes/kind" idp-env DRY_RUN=1 ACTION=create APP=hello-platform ENV=preview-nr
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"would create environment preview-nr for hello-platform"* ]]
}

@test "self-service environment requests render a usable workload base reference" {
  export PLATFORM_IDP_RUN_DIR="${REPO_ROOT}/.run/idp-core-components-test"
  rm -rf "${PLATFORM_IDP_RUN_DIR}"

  run make -C "${REPO_ROOT}/kubernetes/kind" idp-env ACTION=create APP=hello-platform ENV=preview-nr
  [ "${status}" -eq 0 ]

  request_dir="${PLATFORM_IDP_RUN_DIR}/hello-platform-preview-nr"
  [ -f "${request_dir}/request.json" ]
  [ -f "${request_dir}/kustomization.yaml" ]

  run sed -n '1,20p' "${request_dir}/kustomization.yaml"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"terraform/kubernetes/apps/workloads/hello-platform"* ]]

  run kubectl kustomize "${request_dir}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: hello-platform"* ]]

  rm -rf "${PLATFORM_IDP_RUN_DIR}"
}

@test "active SSO route tracing follows Keycloak rather than the old Dex route" {
  run rg -n 'name: keycloak' "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/observabilitypolicy-tracing.yaml"
  [ "${status}" -eq 0 ]

  run rg -n 'name: dex' "${REPO_ROOT}/terraform/kubernetes/apps/platform-gateway-routes-sso/observabilitypolicy-tracing.yaml"
  [ "${status}" -ne 0 ]
}

@test "source repo carries concrete closure artifacts claimed by platform-docs" {
  for path in \
    terraform/kubernetes/scripts/gitea-repo-lifecycle-demo.sh \
    terraform/kubernetes/apps/apim/subnetcalc.api-product.yaml.example \
    apps/sentiment/evaluation.jsonl \
    apps/sentiment/MODEL_CARD.md
  do
    [ -f "${REPO_ROOT}/${path}" ]
  done
}

@test "DDD language names the new IDP domain concepts" {
  for term in \
    "service catalog" \
    "application spec" \
    "environment request" \
    "deployment record" \
    "secret binding" \
    "scorecard" \
    "app/environment RBAC" \
    "hello-platform"
  do
    run rg -n "${term}" \
      "${REPO_ROOT}/docs/ddd/ubiquitous-language.md" \
      "${REPO_ROOT}/docs/ddd/context-map.md" \
      "${REPO_ROOT}/docs/ddd/contracts.md"
    [ "${status}" -eq 0 ]
  done
}
