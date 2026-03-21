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

list_context_refs() {
  local kubeconfig_path="$1"

  KUBECONFIG="${kubeconfig_path}" kubectl config view --raw -o jsonpath='{range .contexts[*]}{.name}{"\t"}{.context.cluster}{"\t"}{.context.user}{"\n"}{end}' 2>/dev/null || true
}

get_current_context() {
  local kubeconfig_path="$1"
  local current_context=""

  current_context="$(KUBECONFIG="${kubeconfig_path}" kubectl config view --raw -o jsonpath='{.current-context}' 2>/dev/null || true)"
  if [[ -n "${current_context}" ]]; then
    printf '%s\n' "${current_context}"
    return 0
  fi

  current_context="$(grep -E '^current-context:' "${kubeconfig_path}" 2>/dev/null | head -n1 | sed -E 's/^current-context:[[:space:]]*"?([^"]*)"?.*$/\1/' || true)"
  if [[ "${current_context}" == "null" ]]; then
    current_context=""
  fi
  printf '%s\n' "${current_context}"
}

is_repo_owned_context() {
  local context_name="$1"
  local repo_contexts_csv="${KUBECONFIG_REPO_CONTEXTS:-kind-kind-local,limavm-k3s,slicer-k3s}"
  local repo_context

  IFS=',' read -r -a repo_contexts <<<"${repo_contexts_csv}"
  for repo_context in "${repo_contexts[@]}"; do
    if [[ "${repo_context}" == "${context_name}" ]]; then
      return 0
    fi
  done

  return 1
}

find_repo_owned_singleton_context() {
  local kubeconfig_path="$1"
  local context_refs=""
  local current_context=""
  local candidate_context=""
  local context_name=""

  context_refs="$(list_context_refs "${kubeconfig_path}")"
  while IFS=$'\t' read -r context_name _ _; do
    [[ -n "${context_name}" ]] || continue
    if [[ -z "${candidate_context}" ]]; then
      candidate_context="${context_name}"
      continue
    fi
    if [[ "${candidate_context}" != "${context_name}" ]]; then
      return 1
    fi
  done <<<"${context_refs}"

  current_context="$(get_current_context "${kubeconfig_path}")"
  if [[ -n "${current_context}" ]]; then
    if [[ -z "${candidate_context}" ]]; then
      candidate_context="${current_context}"
    elif [[ "${candidate_context}" != "${current_context}" ]]; then
      return 1
    fi
  fi

  [[ -n "${candidate_context}" ]] || return 1
  is_repo_owned_context "${candidate_context}" || return 1

  printf '%s\n' "${candidate_context}"
}

backup_invalid_kubeconfig() {
  local kubeconfig_path="$1"
  local recreate_file="${2:-1}"
  local backup_path=""

  backup_path="${kubeconfig_path}.broken.$(date +%Y%m%d%H%M%S)"
  mv "${kubeconfig_path}" "${backup_path}"
  echo "WARN kubeconfig ${kubeconfig_path} was invalid; backed up to ${backup_path}" >&2

  if [[ "${recreate_file}" == "1" ]]; then
    write_empty_kubeconfig "${kubeconfig_path}"
  fi
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

  backup_invalid_kubeconfig "${kubeconfig_path}" "${create_if_missing}"
}

count_contexts() {
  local kubeconfig_path="$1"

  ensure_valid_kubeconfig "${kubeconfig_path}" 1
  list_context_refs "${kubeconfig_path}" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

prepare_reset_kubeconfig() {
  local kubeconfig_path="$1"
  local raw_config=""
  local current_context=""
  local repo_owned_context=""
  local confirm=""

  if [[ ! -e "${kubeconfig_path}" ]]; then
    return 0
  fi

  if [[ ! -s "${kubeconfig_path}" ]]; then
    rm -f "${kubeconfig_path}"
    return 0
  fi

  raw_config="$(cat "${kubeconfig_path}" 2>/dev/null || true)"
  if [[ -n "${raw_config}" ]] && is_empty_null_kubeconfig "${raw_config}"; then
    rm -f "${kubeconfig_path}"
    return 0
  fi

  current_context="$(get_current_context "${kubeconfig_path}")"
  if [[ -n "${raw_config}" ]]; then
    if [[ -z "${current_context}" ]] || KUBECONFIG="${kubeconfig_path}" kubectl config get-contexts "${current_context}" >/dev/null 2>&1; then
      return 0
    fi
  fi

  repo_owned_context="$(find_repo_owned_singleton_context "${kubeconfig_path}" || true)"
  if [[ -n "${repo_owned_context}" ]]; then
    if [[ "${KUBECONFIG_RESET_AUTO_APPROVE:-0}" == "1" ]]; then
      rm -f "${kubeconfig_path}"
      echo "WARN kubeconfig ${kubeconfig_path} was invalid and only contained repo-owned context ${repo_owned_context}; deleted it instead of backing it up" >&2
      return 0
    fi

    if [[ -t 0 ]]; then
      printf 'WARN kubeconfig %s is invalid and only contains repo-owned context %s. Delete it instead of backing it up? [y/N] ' "${kubeconfig_path}" "${repo_owned_context}" >&2
      read -r confirm || true
      if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
        rm -f "${kubeconfig_path}"
        echo "OK   Deleted stale kubeconfig ${kubeconfig_path}" >&2
        return 0
      fi
    fi
  fi

  backup_invalid_kubeconfig "${kubeconfig_path}" 0
}

extract_context_kubeconfig() {
  local source_kubeconfig="$1"
  local target_context="$2"
  local output_kubeconfig="$3"

  if [[ -n "${target_context}" ]]; then
    KUBECONFIG="${source_kubeconfig}" kubectl config view --raw --minify --context "${target_context}" >"${output_kubeconfig}"
  else
    cat "${source_kubeconfig}" >"${output_kubeconfig}"
  fi

  chmod 600 "${output_kubeconfig}"
}

normalize_repo_context_refs() {
  local kubeconfig_path="$1"
  local target_context="$2"
  local resolved_context=""
  local resolved_cluster=""
  local resolved_user=""
  local new_cluster=""
  local new_user=""
  local tmp_file=""

  [[ -n "${target_context}" ]] || return 0
  is_repo_owned_context "${target_context}" || return 0

  resolved_context="$(awk -F '\t' -v ctx="${target_context}" '$1 == ctx {print; exit}' <<<"$(list_context_refs "${kubeconfig_path}")")"
  [[ -n "${resolved_context}" ]] || return 0
  IFS=$'\t' read -r _ resolved_cluster resolved_user <<<"${resolved_context}"

  new_cluster="${resolved_cluster}"
  new_user="${resolved_user}"
  if [[ "${resolved_cluster}" == "default" ]]; then
    new_cluster="${target_context}-cluster"
  fi
  if [[ "${resolved_user}" == "default" ]]; then
    new_user="${target_context}-user"
  fi

  if [[ "${new_cluster}" == "${resolved_cluster}" && "${new_user}" == "${resolved_user}" ]]; then
    return 0
  fi

  tmp_file="$(mktemp "${TMPDIR:-/tmp}/kubeconfig-normalized.XXXXXX")"
  awk \
    -v old_cluster="${resolved_cluster}" \
    -v new_cluster="${new_cluster}" \
    -v old_user="${resolved_user}" \
    -v new_user="${new_user}" '
    /^clusters:$/ { section = "clusters"; print; next }
    /^contexts:$/ { section = "contexts"; print; next }
    /^users:$/ { section = "users"; print; next }
    {
      line = $0
      trimmed = $0
      sub(/^[[:space:]]+/, "", trimmed)

      if (section == "clusters" && trimmed == "name: " old_cluster) {
        match(line, /^[[:space:]]*/)
        line = substr(line, RSTART, RLENGTH) "name: " new_cluster
      } else if (section == "contexts" && trimmed == "cluster: " old_cluster) {
        match(line, /^[[:space:]]*/)
        line = substr(line, RSTART, RLENGTH) "cluster: " new_cluster
      } else if (section == "contexts" && trimmed == "user: " old_user) {
        match(line, /^[[:space:]]*/)
        line = substr(line, RSTART, RLENGTH) "user: " new_user
      } else if (section == "users" && trimmed == "- name: " old_user) {
        match(line, /^[[:space:]]*/)
        line = substr(line, RSTART, RLENGTH) "- name: " new_user
      }

      print line
    }' "${kubeconfig_path}" >"${tmp_file}"
  chmod 600 "${tmp_file}"
  mv "${tmp_file}" "${kubeconfig_path}"
}

merge_kubeconfig() {
  local source_kubeconfig="$1"
  local target_kubeconfig="$2"
  local target_context="${3:-}"
  local source_for_merge=""
  local target_for_merge=""
  local tmp_file=""

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

  source_for_merge="$(mktemp "${TMPDIR:-/tmp}/kubeconfig-source.XXXXXX")"
  target_for_merge="$(mktemp "${TMPDIR:-/tmp}/kubeconfig-target.XXXXXX")"
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/kubeconfig.XXXXXX")"

  extract_context_kubeconfig "${source_kubeconfig}" "${target_context}" "${source_for_merge}"
  normalize_repo_context_refs "${source_for_merge}" "${target_context}"

  cp "${target_kubeconfig}" "${target_for_merge}"
  chmod 600 "${target_for_merge}"
  if [[ -n "${target_context}" ]]; then
    delete_context "${target_for_merge}" "${target_context}" "${target_context}" "${target_context}" 0
  fi

  KUBECONFIG="${target_for_merge}:${source_for_merge}" kubectl config view --flatten >"${tmp_file}"
  chmod 600 "${tmp_file}"

  if [[ -n "${target_context}" ]]; then
    KUBECONFIG="${tmp_file}" kubectl config use-context "${target_context}" >/dev/null 2>&1 || true
  fi

  mv "${tmp_file}" "${target_kubeconfig}"
  rm -f "${source_for_merge}" "${target_for_merge}"
}

delete_context() {
  local kubeconfig_path="$1"
  local context_name="$2"
  local cluster_name="${3:-${context_name}}"
  local user_name="${4:-${context_name}}"
  local delete_file_if_empty="${5:-0}"
  local context_refs=""
  local resolved_context=""
  local resolved_cluster=""
  local resolved_user=""
  local current_context=""
  local remaining_context_refs=""
  local cluster_candidates=()
  local user_candidates=()
  local candidate=""

  if [[ ! -e "${kubeconfig_path}" ]]; then
    return 0
  fi

  ensure_valid_kubeconfig "${kubeconfig_path}" 1

  context_refs="$(list_context_refs "${kubeconfig_path}")"
  resolved_context="$(awk -F '\t' -v ctx="${context_name}" '$1 == ctx {print; exit}' <<<"${context_refs}")"
  if [[ -n "${resolved_context}" ]]; then
    IFS=$'\t' read -r _ resolved_cluster resolved_user <<<"${resolved_context}"
  fi

  current_context="$(get_current_context "${kubeconfig_path}")"
  if [[ "${current_context}" == "${context_name}" ]]; then
    KUBECONFIG="${kubeconfig_path}" kubectl config unset current-context >/dev/null 2>&1 || true
  fi

  if command -v kubectx >/dev/null 2>&1 && [[ "${kubeconfig_path}" == "${HOME}/.kube/config" ]]; then
    KUBECONFIG="${kubeconfig_path}" kubectx -d "${context_name}" >/dev/null 2>&1 || true
  fi

  KUBECONFIG="${kubeconfig_path}" kubectl config delete-context "${context_name}" >/dev/null 2>&1 || true

  if [[ -n "${resolved_cluster}" ]]; then
    cluster_candidates+=("${resolved_cluster}")
  fi
  if [[ -n "${cluster_name}" && "${cluster_name}" != "${resolved_cluster}" ]]; then
    cluster_candidates+=("${cluster_name}")
  fi

  if [[ -n "${resolved_user}" ]]; then
    user_candidates+=("${resolved_user}")
  fi
  if [[ -n "${user_name}" && "${user_name}" != "${resolved_user}" ]]; then
    user_candidates+=("${user_name}")
  fi

  remaining_context_refs="$(list_context_refs "${kubeconfig_path}")"

  for candidate in "${cluster_candidates[@]}"; do
    [[ -n "${candidate}" ]] || continue
    if ! awk -F '\t' -v cluster="${candidate}" '$2 == cluster {found = 1} END {exit(found ? 0 : 1)}' <<<"${remaining_context_refs}"; then
      KUBECONFIG="${kubeconfig_path}" kubectl config delete-cluster "${candidate}" >/dev/null 2>&1 || true
    fi
  done

  for candidate in "${user_candidates[@]}"; do
    [[ -n "${candidate}" ]] || continue
    if ! awk -F '\t' -v user="${candidate}" '$3 == user {found = 1} END {exit(found ? 0 : 1)}' <<<"${remaining_context_refs}"; then
      KUBECONFIG="${kubeconfig_path}" kubectl config delete-user "${candidate}" >/dev/null 2>&1 || true
    fi
  done

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
  manage-kubeconfig.sh prepare-for-reset <kubeconfig>
  manage-kubeconfig.sh count-contexts <kubeconfig>
  manage-kubeconfig.sh lint
  manage-kubeconfig.sh merge <source-kubeconfig> <target-kubeconfig> [context]
  manage-kubeconfig.sh delete-context <kubeconfig> <context> [cluster] [user] [delete_file_if_empty]
EOF
}

lint_with_kubie() {
  if ! command -v kubie >/dev/null 2>&1; then
    return 0
  fi

  kubie lint
}

main() {
  local command="${1:-}"
  shift || true

  case "${command}" in
    ensure-valid)
      [[ $# -eq 1 ]] || { usage >&2; exit 1; }
      ensure_valid_kubeconfig "$1" 1
      ;;
    prepare-for-reset)
      [[ $# -eq 1 ]] || { usage >&2; exit 1; }
      prepare_reset_kubeconfig "$1"
      ;;
    count-contexts)
      [[ $# -eq 1 ]] || { usage >&2; exit 1; }
      count_contexts "$1"
      ;;
    lint)
      [[ $# -eq 0 ]] || { usage >&2; exit 1; }
      lint_with_kubie
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
