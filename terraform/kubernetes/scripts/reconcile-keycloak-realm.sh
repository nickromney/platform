#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Reconciles the existing Postgres-backed Keycloak realm with the rendered
bootstrap realm ConfigMap. Keycloak's start-time import intentionally skips an
existing realm, so this keeps local stage-900 client, group, and user changes
reproducible after the first boot.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would reconcile the Keycloak platform realm" "$@"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

decode_b64() {
  if base64 --decode >/dev/null 2>&1 <<<""; then
    base64 --decode
  elif base64 -d >/dev/null 2>&1 <<<""; then
    base64 -d
  else
    base64 -D
  fi
}

KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-sso}"
KEYCLOAK_DEPLOYMENT="${KEYCLOAK_DEPLOYMENT:-keycloak}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-platform}"
KEYCLOAK_REALM_CONFIGMAP="${KEYCLOAK_REALM_CONFIGMAP:-keycloak-realm}"
KEYCLOAK_REALM_CONFIG_KEY="${KEYCLOAK_REALM_CONFIG_KEY:-platform-realm.json}"
KEYCLOAK_BOOTSTRAP_ADMIN_SECRET="${KEYCLOAK_BOOTSTRAP_ADMIN_SECRET:-keycloak-bootstrap-admin}"
KEYCLOAK_PERMANENT_ADMIN_SECRET="${KEYCLOAK_PERMANENT_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_ADMIN_SERVER="${KEYCLOAK_ADMIN_SERVER:-http://127.0.0.1:8080}"

require_cmd kubectl
require_cmd jq

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

realm_file="${tmpdir}/realm.json"
kubectl -n "${KEYCLOAK_NAMESPACE}" get configmap "${KEYCLOAK_REALM_CONFIGMAP}" -o json |
  jq -r --arg key "${KEYCLOAK_REALM_CONFIG_KEY}" '.data[$key] // empty' >"${realm_file}"

if ! jq -e --arg realm "${KEYCLOAK_REALM}" '.realm == $realm' "${realm_file}" >/dev/null; then
  echo "Rendered realm config does not describe realm ${KEYCLOAK_REALM}" >&2
  exit 1
fi

kubectl -n "${KEYCLOAK_NAMESPACE}" rollout status "deployment/${KEYCLOAK_DEPLOYMENT}" --timeout=300s >/dev/null

keycloak_pod="$(kubectl -n "${KEYCLOAK_NAMESPACE}" get pods \
  -l "app.kubernetes.io/name=${KEYCLOAK_DEPLOYMENT}" \
  -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${keycloak_pod}" ]]; then
  echo "No Keycloak pod found in namespace ${KEYCLOAK_NAMESPACE}" >&2
  exit 1
fi

secret_field() {
  local secret_name="$1"
  local field_name="$2"

  kubectl -n "${KEYCLOAK_NAMESPACE}" get secret "${secret_name}" -o "jsonpath={.data.${field_name}}" 2>/dev/null |
    decode_b64 || true
}

kcadm() {
  kubectl -n "${KEYCLOAK_NAMESPACE}" exec "${keycloak_pod}" -- /opt/keycloak/bin/kcadm.sh "$@"
}

kcadm_stdin() {
  kubectl -n "${KEYCLOAK_NAMESPACE}" exec -i "${keycloak_pod}" -- /opt/keycloak/bin/kcadm.sh "$@"
}

permanent_admin_user="$(secret_field "${KEYCLOAK_PERMANENT_ADMIN_SECRET}" username)"
permanent_admin_password="$(secret_field "${KEYCLOAK_PERMANENT_ADMIN_SECRET}" password)"
bootstrap_admin_user="$(secret_field "${KEYCLOAK_BOOTSTRAP_ADMIN_SECRET}" username)"
bootstrap_admin_password="$(secret_field "${KEYCLOAK_BOOTSTRAP_ADMIN_SECRET}" password)"

login_keycloak_admin() {
  local username="$1"
  local password="$2"

  [[ -n "${username}" && -n "${password}" ]] || return 1
  kcadm config credentials \
    --server "${KEYCLOAK_ADMIN_SERVER}" \
    --realm master \
    --user "${username}" \
    --password "${password}" >/dev/null 2>&1
}

if login_keycloak_admin "${permanent_admin_user}" "${permanent_admin_password}"; then
  echo "Keycloak admin authenticated with permanent admin: ${permanent_admin_user}"
elif login_keycloak_admin "${bootstrap_admin_user}" "${bootstrap_admin_password}"; then
  echo "Keycloak admin authenticated with bootstrap admin: ${bootstrap_admin_user}"
else
  echo "Could not authenticate to Keycloak with either permanent or bootstrap admin credentials" >&2
  exit 1
fi

login_permanent_keycloak_admin() {
  if login_keycloak_admin "${permanent_admin_user}" "${permanent_admin_password}"; then
    echo "Keycloak admin re-authenticated with permanent admin: ${permanent_admin_user}"
    return 0
  fi

  echo "Could not re-authenticate to Keycloak with permanent admin credentials" >&2
  exit 1
}

group_id_for_name() {
  local group_name="$1"
  kcadm get groups -r "${KEYCLOAK_REALM}" -q "search=${group_name}" --fields id,name |
    jq -r --arg name "${group_name}" '.[] | select(.name == $name) | .id' |
    head -n 1
}

client_id_for_client_id() {
  local client_id="$1"
  client_id_for_client_id_in_realm "${KEYCLOAK_REALM}" "${client_id}"
}

client_id_for_client_id_in_realm() {
  local realm="$1"
  local client_id="$2"
  kcadm get clients -r "${realm}" -q "clientId=${client_id}" --fields id,clientId |
    jq -r --arg clientId "${client_id}" '.[] | select(.clientId == $clientId) | .id' |
    head -n 1
}

client_scope_id_for_name() {
  local scope_name="$1"
  kcadm get client-scopes -r "${KEYCLOAK_REALM}" -q "name=${scope_name}" --fields id,name |
    jq -r --arg name "${scope_name}" '.[] | select(.name == $name) | .id' |
    head -n 1
}

client_scope_is_attached() {
  local client_uuid="$1"
  local scope_kind="$2"
  local scope_name="$3"

  kcadm get "clients/${client_uuid}/${scope_kind}-client-scopes" -r "${KEYCLOAK_REALM}" --fields name |
    jq -e --arg name "${scope_name}" 'any(.[]?; .name == $name)' >/dev/null
}

user_id_for_username() {
  local username="$1"
  user_id_for_username_in_realm "${KEYCLOAK_REALM}" "${username}"
}

user_id_for_username_in_realm() {
  local realm="$1"
  local username="$2"

  kcadm get users -r "${realm}" -q "username=${username}" --fields id,username |
    jq -r --arg username "${username}" '.[] | select(.username == $username) | .id' |
    head -n 1
}

user_has_realm_role() {
  local realm="$1"
  local user_id="$2"
  local role_name="$3"

  kcadm get "users/${user_id}/role-mappings/realm" -r "${realm}" --fields name |
    jq -e --arg name "${role_name}" 'any(.[]?; .name == $name)' >/dev/null
}

group_has_client_role() {
  local realm="$1"
  local group_id="$2"
  local client_uuid="$3"
  local role_name="$4"

  kcadm get "groups/${group_id}/role-mappings/clients/${client_uuid}" -r "${realm}" --fields name |
    jq -e --arg name "${role_name}" 'any(.[]?; .name == $name)' >/dev/null
}

ensure_master_admin() {
  local username="${permanent_admin_user}"
  local password="${permanent_admin_password}"
  local email="${KEYCLOAK_PERMANENT_ADMIN_EMAIL:-keycloak-admin@platform.local}"
  local user_id

  [[ -n "${username}" && -n "${password}" ]] || {
    echo "Permanent Keycloak admin secret is missing username/password" >&2
    exit 1
  }

  user_id="$(user_id_for_username_in_realm master "${username}")"
  if [[ -z "${user_id}" ]]; then
    kcadm create users -r master \
      -s "username=${username}" \
      -s "email=${email}" \
      -s "enabled=true" \
      -s "emailVerified=true" >/dev/null
    user_id="$(user_id_for_username_in_realm master "${username}")"
    echo "Keycloak permanent master admin created: ${username}"
  else
    kcadm update "users/${user_id}" -r master \
      -s "email=${email}" \
      -s "enabled=true" \
      -s "emailVerified=true" >/dev/null
    echo "Keycloak permanent master admin reconciled: ${username}"
  fi

  kcadm set-password -r master --userid "${user_id}" --new-password "${password}" >/dev/null

  if ! user_has_realm_role master "${user_id}" admin; then
    kcadm add-roles -r master --uusername "${username}" --rolename admin >/dev/null
  fi
}

delete_bootstrap_admins_from_master() {
  local username user_id
  local candidates=("${bootstrap_admin_user}" "demo@admin.test")

  for username in "${candidates[@]}"; do
    [[ -n "${username}" ]] || continue
    [[ "${username}" != "${permanent_admin_user}" ]] || continue

    user_id="$(user_id_for_username_in_realm master "${username}")"
    [[ -n "${user_id}" ]] || continue

    kcadm delete "users/${user_id}" -r master >/dev/null
    echo "Keycloak bootstrap admin deleted from master realm: ${username}"
  done
}

ensure_master_admin
login_permanent_keycloak_admin

ensure_client_scope() {
  local scope_json="$1"
  local scope_name scope_id scope_payload

  scope_name="$(jq -r '.name' <<<"${scope_json}")"
  scope_id="$(client_scope_id_for_name "${scope_name}")"
  scope_payload="$(jq -c 'del(.id)' <<<"${scope_json}")"

  if [[ -z "${scope_id}" ]]; then
    printf '%s' "${scope_payload}" | kcadm_stdin create client-scopes -r "${KEYCLOAK_REALM}" -f - >/dev/null
    echo "Keycloak client scope created: ${scope_name}"
    return 0
  fi

  printf '%s' "${scope_payload}" | kcadm_stdin update "client-scopes/${scope_id}" -r "${KEYCLOAK_REALM}" -f - --merge >/dev/null
  echo "Keycloak client scope reconciled: ${scope_name}"
}

ensure_client_scope_attachment() {
  local client_uuid="$1"
  local scope_kind="$2"
  local scope_name="$3"
  local scope_id

  [[ -n "${scope_name}" ]] || return 0

  scope_id="$(client_scope_id_for_name "${scope_name}")"
  if [[ -z "${scope_id}" ]]; then
    echo "Keycloak client scope not found for client attachment: ${scope_name}" >&2
    exit 1
  fi

  if client_scope_is_attached "${client_uuid}" "${scope_kind}" "${scope_name}"; then
    return 0
  fi

  kcadm update "clients/${client_uuid}/${scope_kind}-client-scopes/${scope_id}" \
    -r "${KEYCLOAK_REALM}" \
    -s "realm=${KEYCLOAK_REALM}" \
    -s "client=${client_uuid}" \
    -s "clientScopeId=${scope_id}" \
    -n >/dev/null
}

detach_client_scope_attachment() {
  local client_uuid="$1"
  local scope_kind="$2"
  local scope_name="$3"
  local scope_id

  scope_id="$(client_scope_id_for_name "${scope_name}")"
  [[ -n "${scope_id}" ]] || return 0

  if ! client_scope_is_attached "${client_uuid}" "${scope_kind}" "${scope_name}"; then
    return 0
  fi

  kcadm delete "clients/${client_uuid}/${scope_kind}-client-scopes/${scope_id}" \
    -r "${KEYCLOAK_REALM}" >/dev/null
  echo "Keycloak client scope detached: ${scope_kind}:${scope_name}"
}

json_array_contains() {
  local json_array="$1"
  local value="$2"

  jq -e --arg value "${value}" 'any(.[]?; . == $value)' <<<"${json_array}" >/dev/null
}

reconcile_client_scope_attachments() {
  local client_uuid="$1"
  local scope_kind="$2"
  local desired_scopes_json="$3"
  local scope_name

  while IFS= read -r scope_name; do
    ensure_client_scope_attachment "${client_uuid}" "${scope_kind}" "${scope_name}"
  done < <(jq -r '.[]? // empty' <<<"${desired_scopes_json}")

  while IFS= read -r scope_name; do
    [[ -n "${scope_name}" ]] || continue
    if ! json_array_contains "${desired_scopes_json}" "${scope_name}"; then
      detach_client_scope_attachment "${client_uuid}" "${scope_kind}" "${scope_name}"
    fi
  done < <(kcadm get "clients/${client_uuid}/${scope_kind}-client-scopes" -r "${KEYCLOAK_REALM}" --fields name | jq -r '.[].name')
}

ensure_group() {
  local group_name="$1"
  local group_id

  group_id="$(group_id_for_name "${group_name}")"
  if [[ -n "${group_id}" ]]; then
    echo "Keycloak group present: ${group_name}"
    return 0
  fi

  kcadm create groups -r "${KEYCLOAK_REALM}" -s "name=${group_name}" >/dev/null
  echo "Keycloak group created: ${group_name}"
}

ensure_group_client_role() {
  local group_name="$1"
  local client_id="$2"
  local role_name="$3"
  local group_id client_uuid

  ensure_group "${group_name}" >/dev/null
  group_id="$(group_id_for_name "${group_name}")"
  client_uuid="$(client_id_for_client_id_in_realm "${KEYCLOAK_REALM}" "${client_id}")"

  if [[ -z "${group_id}" || -z "${client_uuid}" ]]; then
    echo "Could not resolve group ${group_name} or client ${client_id} for role mapping" >&2
    exit 1
  fi

  if group_has_client_role "${KEYCLOAK_REALM}" "${group_id}" "${client_uuid}" "${role_name}"; then
    echo "Keycloak group client role present: ${group_name} -> ${client_id}:${role_name}"
    return 0
  fi

  kcadm add-roles -r "${KEYCLOAK_REALM}" \
    --gid "${group_id}" \
    --cclientid "${client_id}" \
    --rolename "${role_name}" >/dev/null
  echo "Keycloak group client role added: ${group_name} -> ${client_id}:${role_name}"
}

ensure_client() {
  local client_json="$1"
  local client_name client_uuid client_payload scope_name

  client_name="$(jq -r '.clientId' <<<"${client_json}")"
  client_uuid="$(client_id_for_client_id "${client_name}")"
  client_payload="$(jq -c 'del(.id, .defaultClientScopes, .optionalClientScopes)' <<<"${client_json}")"

  if [[ -z "${client_uuid}" ]]; then
    printf '%s' "${client_payload}" | kcadm_stdin create clients -r "${KEYCLOAK_REALM}" -f - >/dev/null
    client_uuid="$(client_id_for_client_id "${client_name}")"
    echo "Keycloak client created: ${client_name}"
  else
    printf '%s' "${client_payload}" | kcadm_stdin update "clients/${client_uuid}" -r "${KEYCLOAK_REALM}" -f - --merge >/dev/null
    echo "Keycloak client reconciled: ${client_name}"
  fi

  if jq -e 'has("defaultClientScopes")' <<<"${client_json}" >/dev/null; then
    reconcile_client_scope_attachments "${client_uuid}" "default" "$(jq -c '.defaultClientScopes // []' <<<"${client_json}")"
  else
    while IFS= read -r scope_name; do
      ensure_client_scope_attachment "${client_uuid}" "default" "${scope_name}"
    done < <(jq -r '.defaultClientScopes[]? // empty' <<<"${client_json}")
  fi

  if jq -e 'has("optionalClientScopes")' <<<"${client_json}" >/dev/null; then
    reconcile_client_scope_attachments "${client_uuid}" "optional" "$(jq -c '.optionalClientScopes // []' <<<"${client_json}")"
  else
    while IFS= read -r scope_name; do
      ensure_client_scope_attachment "${client_uuid}" "optional" "${scope_name}"
    done < <(jq -r '.optionalClientScopes[]? // empty' <<<"${client_json}")
  fi
}

ensure_user() {
  local user_json="$1"
  local username user_id user_payload password temporary group_name group_id

  username="$(jq -r '.username' <<<"${user_json}")"
  user_id="$(user_id_for_username "${username}")"
  user_payload="$(jq -c 'del(.id, .credentials, .groups)' <<<"${user_json}")"

  if [[ -z "${user_id}" ]]; then
    printf '%s' "${user_payload}" | kcadm_stdin create users -r "${KEYCLOAK_REALM}" -f - >/dev/null
    user_id="$(user_id_for_username "${username}")"
    echo "Keycloak user created: ${username}"
  else
    printf '%s' "${user_payload}" | kcadm_stdin update "users/${user_id}" -r "${KEYCLOAK_REALM}" -f - --merge >/dev/null
    echo "Keycloak user reconciled: ${username}"
  fi

  password="$(jq -r '.credentials[0].value // empty' <<<"${user_json}")"
  temporary="$(jq -r '.credentials[0].temporary // false' <<<"${user_json}")"
  if [[ -n "${password}" ]]; then
    if [[ "${temporary}" == "true" ]]; then
      kcadm set-password -r "${KEYCLOAK_REALM}" --userid "${user_id}" --new-password "${password}" --temporary >/dev/null
    else
      kcadm set-password -r "${KEYCLOAK_REALM}" --userid "${user_id}" --new-password "${password}" >/dev/null
    fi
  fi

  while IFS= read -r group_name; do
    [[ -n "${group_name}" ]] || continue
    ensure_group "${group_name}" >/dev/null
    group_id="$(group_id_for_name "${group_name}")"
    if [[ -n "${group_id}" ]]; then
      kcadm update "users/${user_id}/groups/${group_id}" \
        -r "${KEYCLOAK_REALM}" \
        -s "realm=${KEYCLOAK_REALM}" \
        -s "userId=${user_id}" \
        -s "groupId=${group_id}" \
        -n >/dev/null
    fi
  done < <(jq -r '.groups[]? // empty' <<<"${user_json}")
}

while IFS= read -r scope_json; do
  [[ -n "${scope_json}" ]] || continue
  ensure_client_scope "${scope_json}"
done < <(jq -c '.clientScopes[]?' "${realm_file}")

while IFS= read -r group_name; do
  [[ -n "${group_name}" ]] || continue
  ensure_group "${group_name}"
done < <(jq -r '.groups[]?.name // empty' "${realm_file}")

while IFS= read -r client_json; do
  [[ -n "${client_json}" ]] || continue
  ensure_client "${client_json}"
done < <(jq -c '.clients[]?' "${realm_file}")

ensure_group_client_role "platform-admins" "realm-management" "realm-admin"

while IFS= read -r user_json; do
  [[ -n "${user_json}" ]] || continue
  ensure_user "${user_json}"
done < <(jq -c '.users[]?' "${realm_file}")

delete_bootstrap_admins_from_master

echo "Keycloak realm reconciled: ${KEYCLOAK_REALM}"
