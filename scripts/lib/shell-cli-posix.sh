#!/bin/sh

shell_cli_script_name() {
  basename "$0"
}

shell_cli_unknown_flag() {
  printf '%s: unknown flag: %s\n' "$(shell_cli_script_name)" "$1" >&2
}

shell_cli_unexpected_arg() {
  printf '%s: unexpected argument: %s\n' "$(shell_cli_script_name)" "$1" >&2
}

shell_cli_missing_value() {
  printf '%s: missing value for %s\n' "$(shell_cli_script_name)" "$1" >&2
}

shell_cli_standard_options() {
  cat <<'EOF'
Options:
  --dry-run  Show a summary and exit before side effects
  --execute  Execute the script body; without it the script prints help and/or preview output
  -h, --help Show this message
EOF
}

shell_cli_print_dry_run_summary() {
  printf 'INFO dry-run: %s\n' "$*"
}

shell_cli_init_standard_flags() {
  SHELL_CLI_DRY_RUN=0
  SHELL_CLI_EXECUTE=0
}

shell_cli_handle_standard_flag() {
  usage_fn="$1"
  arg="$2"

  case "$arg" in
    -h|--help)
      "${usage_fn}"
      exit 0
      ;;
    --dry-run)
      SHELL_CLI_DRY_RUN=1
      return 0
      ;;
    --execute)
      SHELL_CLI_EXECUTE=1
      return 0
      ;;
  esac

  return 1
}

shell_cli_parse_standard_only() {
  usage_fn="$1"
  shift

  shell_cli_init_standard_flags
  SHELL_CLI_ARGS=

  while [ "$#" -gt 0 ]; do
    if shell_cli_handle_standard_flag "${usage_fn}" "$1"; then
      shift
      continue
    fi

    case "$1" in
      --)
        shift
        break
        ;;
      -*)
        shell_cli_unknown_flag "$1"
        return 1
        ;;
      *)
        break
        ;;
    esac
    shift
  done

  SHELL_CLI_ARGS="$*"
}

shell_cli_maybe_execute_or_preview() {
  usage_fn="$1"
  preview_fn="$2"

  if [ "${SHELL_CLI_DRY_RUN}" = "1" ]; then
    "${preview_fn}"
    exit 0
  fi

  if [ "${SHELL_CLI_EXECUTE}" != "1" ]; then
    "${usage_fn}"
    "${preview_fn}"
    exit 0
  fi
}

shell_cli_maybe_execute_or_preview_summary() {
  usage_fn="$1"
  dry_run_summary="$2"

  if [ "${SHELL_CLI_DRY_RUN}" = "1" ]; then
    shell_cli_print_dry_run_summary "${dry_run_summary}"
    exit 0
  fi

  if [ "${SHELL_CLI_EXECUTE}" != "1" ]; then
    "${usage_fn}"
    shell_cli_print_dry_run_summary "${dry_run_summary}"
    exit 0
  fi
}

shell_cli_handle_standard_no_args() {
  usage_fn="$1"
  dry_run_summary="$2"
  shift 2

  shell_cli_parse_standard_only "${usage_fn}" "$@" || exit 1
  if [ -n "${SHELL_CLI_ARGS}" ]; then
    set -- ${SHELL_CLI_ARGS}
    shell_cli_unexpected_arg "$1"
    exit 1
  fi

  shell_cli_maybe_execute_or_preview_summary "${usage_fn}" "${dry_run_summary}"
}
