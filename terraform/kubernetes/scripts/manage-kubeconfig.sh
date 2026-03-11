#!/usr/bin/env bash
set -euo pipefail

write_empty_kubeconfig() {
  local kubeconfig_path="$1"

  mkdir -p "$(dirname "${kubeconfig_path}")"
  umask 077
  cat >"${kubeconfig_path}" <<'EOF'
apiVersion: v1
kind: Config
preferences: {}
clusters: []
contexts: []
users: []
current-context: ""
EOF
}

is_empty_null_kubeconfig() {
  local raw_config="$1"

  grep -Eq '^clusters: null$' <<<"${raw_config}" && \
    grep -Eq '^contexts: null$' <<<"${raw_config}" && \
    grep -Eq '^users: null$' <<<"${raw_config}"
}

ensure_valid_kubeconfig() {
  local kubeconfig_path="$1"
  local create_if_missing="${2:-1}"
  local raw_config=""
  local current_context=""

  if [[ ! -e "${kubeconfig_path}" ]]; then
    if [[ "${create_if_missing}" == "1" ]]; then
      write_empty_kubeconfig "${kubeconfig_path}"
    fi
    return 0
  fi

  if [[ ! -s "${kubeconfig_path}" ]]; then
    write_empty_kubeconfig "${kubeconfig_path}"
    return 0
  fi

  raw_config="$(cat "${kubeconfig_path}" 2>/dev/null || true)"
  if [[ -n "${raw_config}" ]] && is_empty_null_kubeconfig "${raw_config}"; then
    write_empty_kubeconfig "${kubeconfig_path}"
    return 0
  fi

  current_context="$(KUBECONFIG="${kubeconfig_path}" kubectl config view --raw -o jsonpath='{.current-context}' 2>/dev/null || true)"
  if [[ -n "${raw_config}" ]]; then
    if [[ -z "${current_context}" ]] || KUBECONFIG="${kubeconfig_path}" kubectl config get-contexts "${current_context}" >/dev/null 2>&1; then
      return 0
    fi
  fi

  local backup_path
  backup_path="${kubeconfig_path}.broken.$(date +%Y%m%d%H%M%S)"
  mv "${kubeconfig_path}" "${backup_path}"
  echo "WARN kubeconfig ${kubeconfig_path} was invalid; backed up to ${backup_path}" >&2
  write_empty_kubeconfig "${kubeconfig_path}"
}

count_contexts() {
  local kubeconfig_path="$1"

  ensure_valid_kubeconfig "${kubeconfig_path}" 1
  KUBECONFIG="${kubeconfig_path}" kubectl config get-contexts -o name 2>/dev/null | wc -l | tr -d ' '
}

merge_kubeconfig() {
  local source_kubeconfig="$1"
  local target_kubeconfig="$2"
  local target_context="${3:-}"

  ensure_valid_kubeconfig "${source_kubeconfig}" 0
  [[ -f "${source_kubeconfig}" ]] || {
    echo "Source kubeconfig not found: ${source_kubeconfig}" >&2
    exit 1
  }

  ensure_valid_kubeconfig "${target_kubeconfig}" 1

  if [[ "${source_kubeconfig}" == "${target_kubeconfig}" ]]; then
    if [[ -n "${target_context}" ]]; then
      KUBECONFIG="${target_kubeconfig}" kubectl config use-context "${target_context}" >/dev/null 2>&1 || true
    fi
    return 0
  fi

  local tmp_file
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/kubeconfig.XXXXXX")"
  KUBECONFIG="${target_kubeconfig}:${source_kubeconfig}" kubectl config view --flatten >"${tmp_file}"
  chmod 600 "${tmp_file}"

  if [[ -n "${target_context}" ]]; then
    KUBECONFIG="${tmp_file}" kubectl config use-context "${target_context}" >/dev/null 2>&1 || true
  fi

  mv "${tmp_file}" "${target_kubeconfig}"
}

delete_context() {
  local kubeconfig_path="$1"
  local context_name="$2"
  local cluster_name="${3:-${context_name}}"
  local user_name="${4:-${context_name}}"
  local delete_file_if_empty="${5:-0}"

  if [[ ! -e "${kubeconfig_path}" ]]; then
    return 0
  fi

  ensure_valid_kubeconfig "${kubeconfig_path}" 1

  if command -v kubectx >/dev/null 2>&1 && [[ "${kubeconfig_path}" == "${HOME}/.kube/config" ]]; then
    KUBECONFIG="${kubeconfig_path}" kubectx -d "${context_name}" >/dev/null 2>&1 || true
  fi

  KUBECONFIG="${kubeconfig_path}" kubectl config delete-context "${context_name}" >/dev/null 2>&1 || true
  KUBECONFIG="${kubeconfig_path}" kubectl config delete-cluster "${cluster_name}" >/dev/null 2>&1 || true
  KUBECONFIG="${kubeconfig_path}" kubectl config delete-user "${user_name}" >/dev/null 2>&1 || true

  if [[ "${delete_file_if_empty}" == "1" ]]; then
    local remaining_contexts
    remaining_contexts="$(count_contexts "${kubeconfig_path}")"
    if [[ "${remaining_contexts}" == "0" ]]; then
      rm -f "${kubeconfig_path}"
    fi
  fi
}

usage() {
  cat <<'EOF'
Usage:
  manage-kubeconfig.sh ensure-valid <kubeconfig>
  manage-kubeconfig.sh count-contexts <kubeconfig>
  manage-kubeconfig.sh merge <source-kubeconfig> <target-kubeconfig> [context]
  manage-kubeconfig.sh delete-context <kubeconfig> <context> [cluster] [user] [delete_file_if_empty]
EOF
}

main() {
  local command="${1:-}"
  shift || true

  case "${command}" in
    ensure-valid)
      [[ $# -eq 1 ]] || { usage >&2; exit 1; }
      ensure_valid_kubeconfig "$1" 1
      ;;
    count-contexts)
      [[ $# -eq 1 ]] || { usage >&2; exit 1; }
      count_contexts "$1"
      ;;
    merge)
      [[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 1; }
      merge_kubeconfig "$1" "$2" "${3:-}"
      ;;
    delete-context)
      [[ $# -ge 2 && $# -le 5 ]] || { usage >&2; exit 1; }
      delete_context "$1" "$2" "${3:-$2}" "${4:-$2}" "${5:-0}"
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
