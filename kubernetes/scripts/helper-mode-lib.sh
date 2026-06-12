#!/usr/bin/env bash

helper_mode_enabled() {
  local mode="$1"
  local auto_threshold="$2"
  local stage_num="$3"

  case "${mode}" in
    on) return 0 ;;
    off) return 1 ;;
    auto) [ "${stage_num}" -ge "${auto_threshold}" ] ;;
    *)
      echo "Invalid helper mode: ${mode}" >&2
      exit 2
      ;;
  esac
}
