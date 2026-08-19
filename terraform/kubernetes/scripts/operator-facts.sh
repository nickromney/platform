#!/usr/bin/env bash
# Operator facts: one JSON object at the diagnostic seam.
#
# Load order:
#   1. OPERATOR_FACTS_FILE if set and present (Terraform-emitted contract)
#   2. Else merge TFVARS_FILES (later files win) into JSON
#
# Checkers then read with jq via operator_facts_get / operator_facts_bool.
# Keep kubeconfig and live host ports in the environment; feature flags and
# domains come from this object.
#
# shellcheck shell=bash

OPERATOR_FACTS_JSON="${OPERATOR_FACTS_JSON:-}"

operator_facts_scalar_from_file() {
  local file="$1"
  local key="$2"
  local value=""
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    printf '\n'
    return 0
  fi
  value="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 | \
    sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" || true)"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "${value}"
}

operator_facts_list_from_file() {
  local file="$1"
  local key="$2"
  local raw=""
  local entry=""

  [[ -n "${file}" && -f "${file}" ]] || return 0
  raw="$(
    awk -v key="${key}" '
      !capture && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { capture=1 }
      capture { print }
      capture && /\]/ { exit }
    ' "${file}" 2>/dev/null || true
  )"
  [[ -n "${raw}" ]] || return 0
  while IFS= read -r entry; do
    [[ -n "${entry}" ]] || continue
    printf '%s\n' "${entry}"
  done < <(printf '%s\n' "${raw}" | grep -oE '"[^"]+"' | sed 's/^"//;s/"$//' || true)
}

operator_facts_map_get() {
  local file="$1"
  local key="$2"
  local map_key="$3"
  local default_value="${4:-}"

  if [[ ! -f "${file}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  local value
  value="$(awk -v key="${key}" -v map_key="${map_key}" '
    BEGIN { in_map = 0 }
    {
      line = $0
      sub(/[[:space:]]*#.*/, "", line)
      if (!in_map) {
        pattern = "^[[:space:]]*" key "[[:space:]]*="
        if (line ~ pattern && line ~ /\{/) {
          in_map = 1
        }
        next
      }
      if (line ~ /^[[:space:]]*}/) {
        in_map = 0
        next
      }
      equals = index(line, "=")
      if (equals == 0) {
        next
      }
      found_key = substr(line, 1, equals - 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", found_key)
      gsub(/^"|"$/, "", found_key)
      if (found_key != map_key) {
        next
      }
      found_value = substr(line, equals + 1)
      sub(/[[:space:]]*#.*/, "", found_value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", found_value)
      sub(/,$/, "", found_value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", found_value)
      gsub(/^"|"$/, "", found_value)
      print found_value
    }
  ' "${file}" | tail -n 1)"

  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${default_value}"
  fi
}

operator_facts_json_from_tfvars() {
  local file key value json='{}'

  for file in ${TFVARS_FILES[@]+"${TFVARS_FILES[@]}"}; do
    [[ -n "${file}" && -f "${file}" ]] || continue
    while IFS= read -r key; do
      [[ -n "${key}" ]] || continue
      value="$(operator_facts_scalar_from_file "${file}" "${key}")"
      json="$(jq -c --arg k "${key}" --arg v "${value}" '.[$k]=$v' <<<"${json}")"
    done < <(grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' "${file}" 2>/dev/null | \
      sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*).*/\1/' | awk '!seen[$0]++' || true)
  done

  printf '%s\n' "${json}"
}

operator_facts_load() {
  local file
  if [[ -n "${OPERATOR_FACTS_FILE:-}" && -f "${OPERATOR_FACTS_FILE}" ]]; then
    OPERATOR_FACTS_JSON="$(cat "${OPERATOR_FACTS_FILE}")"
    return 0
  fi

  for file in ${TFVARS_FILES[@]+"${TFVARS_FILES[@]}"}; do
    if [[ -n "${file}" && ! -f "${file}" && -n "${STACK_DIR:-}" && -f "${STACK_DIR}/${file}" ]]; then
      :
    fi
  done

  OPERATOR_FACTS_JSON="$(operator_facts_json_from_tfvars)"
}

operator_facts_get() {
  local key="$1"
  local value=""

  if [[ -n "${OPERATOR_FACTS_JSON:-}" ]]; then
    value="$(jq -r --arg k "${key}" 'if has($k) then .[$k] | if type=="string" then . else tostring end else empty end' <<<"${OPERATOR_FACTS_JSON}")"
    if [[ -n "${value}" && "${value}" != "null" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  fi

  if declare -F tf_default_from_variables >/dev/null 2>&1; then
    value="$(tf_default_from_variables "${key}")"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  fi

  printf '\n'
}

operator_facts_bool() {
  local v
  v="$(operator_facts_get "$1")"
  case "$v" in
    true|false) printf '%s\n' "$v" ;;
    *) printf '\n' ;;
  esac
}

operator_facts_list() {
  local key="$1"
  local file
  local -a values=()
  local entry=""
  local raw=""

  if [[ -n "${OPERATOR_FACTS_JSON:-}" ]] && jq -e --arg k "${key}" 'has($k) and ((.[$k]|type)=="array")' <<<"${OPERATOR_FACTS_JSON}" >/dev/null 2>&1; then
    jq -r --arg k "${key}" '.[$k][]' <<<"${OPERATOR_FACTS_JSON}"
    return 0
  fi

  for file in ${TFVARS_FILES[@]+"${TFVARS_FILES[@]}"}; do
    [[ -n "${file}" && -f "${file}" ]] || continue
    raw="$(operator_facts_list_from_file "${file}" "${key}")"
    [[ -n "${raw}" ]] || continue
    values=()
    while IFS= read -r entry; do
      [[ -n "${entry}" ]] || continue
      values+=("${entry}")
    done <<<"${raw}"
  done

  if [[ "${#values[@]}" -gt 0 ]]; then
    printf '%s\n' "${values[@]}"
  fi
}

# Compatibility wrappers used while callers migrate.
tfvar_get() {
  if [[ $# -ge 2 && ( -z "${1}" || -f "${1}" ) ]]; then
    # Historic "file, key" or dummy-first-arg ("", key) call sites.
    operator_facts_get "$2"
    return
  fi
  operator_facts_get "$1"
}

tfvar_bool() {
  operator_facts_bool "$1"
}

tfvar_get_in_file() {
  operator_facts_scalar_from_file "$1" "$2"
}

tfvar_list_entries() {
  if [[ $# -ge 2 && ( -z "${1}" || -f "${1}" ) ]]; then
    operator_facts_list "$2"
    return
  fi
  operator_facts_list "$1"
}
