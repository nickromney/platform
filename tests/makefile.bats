#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "root make help is informational and points to focused Makefiles" {
  run make -C "${REPO_ROOT}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"This root Makefile is primarily informational."* ]]
  [[ "${output}" == *"make lint"* ]]
  [[ "${output}" == *"make lint-bash32"* ]]
  [[ "${output}" == *"make lint-shell"* ]]
  [[ "${output}" == *"make fmt"* ]]
  [[ "${output}" == *"make check-version"* ]]
  [[ "${output}" == *"make release"* ]]
  [[ "${output}" == *"make release-dry-run"* ]]
  [[ "${output}" == *"make release-tag VERSION=0.3.0"* ]]
  [[ "${output}" == *"make lint-cilium-live"* ]]
  [[ "${output}" == *"make lint-kyverno-live"* ]]
  [[ "${output}" == *"make prereqs"* ]]
  [[ "${output}" == *"make status [STATUS_FORMAT=text|json]"* ]]
  [[ "${output}" == *"make test"* ]]
  [[ "${output}" == *"make tui"* ]]
  [[ "${output}" == *"make kubernetes"* ]]
  [[ "${output}" == *"make docker"* ]]
  [[ "${output}" == *"make apps"* ]]
  [[ "${output}" == *"make sdwan"* ]]
}

@test "root make help prints aligned alphabetised shortcuts" {
  run make -C "${REPO_ROOT}" help

  [ "${status}" -eq 0 ]

  printf '%s\n' "${output}" | grep -Eq '^  make apps[[:space:]]+Show the app/frontend Makefiles$'
  printf '%s\n' "${output}" | grep -Eq '^  make status \[STATUS_FORMAT=text\|json\][[:space:]]+Show root local-runtime status across kind/Lima/Slicer/SD-WAN$'

  apps_line="$(printf '%s\n' "${output}" | grep -n '^  make apps' | cut -d: -f1)"
  check_version_line="$(printf '%s\n' "${output}" | grep -n '^  make check-version' | cut -d: -f1)"
  docker_line="$(printf '%s\n' "${output}" | grep -n '^  make docker' | cut -d: -f1)"
  fmt_line="$(printf '%s\n' "${output}" | grep -n '^  make fmt' | cut -d: -f1)"
  kubernetes_line="$(printf '%s\n' "${output}" | grep -n '^  make kubernetes' | cut -d: -f1)"
  lint_line="$(printf '%s\n' "${output}" | grep -n '^  make lint[[:space:]]' | cut -d: -f1)"
  status_line="$(printf '%s\n' "${output}" | grep -n '^  make status ' | cut -d: -f1)"
  tui_line="$(printf '%s\n' "${output}" | grep -n '^  make tui' | cut -d: -f1)"

  [ "${apps_line}" -lt "${check_version_line}" ]
  [ "${check_version_line}" -lt "${docker_line}" ]
  [ "${docker_line}" -lt "${fmt_line}" ]
  [ "${fmt_line}" -lt "${kubernetes_line}" ]
  [ "${kubernetes_line}" -lt "${lint_line}" ]
  [ "${lint_line}" -lt "${status_line}" ]
  [ "${status_line}" -lt "${tui_line}" ]
}

@test "root bare make defaults to informational help" {
  run make -C "${REPO_ROOT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Platform workspace Makefile guide"* ]]
  [[ "${output}" == *"This root Makefile is primarily informational."* ]]
}

@test "root bare make in a tty prints help then status" {
  command -v script >/dev/null 2>&1 || skip "script not available"

  status_stub="${BATS_TEST_TMPDIR}/platform-status.sh"

  cat >"${status_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'status %s\n' "$*"
EOF
  chmod +x "${status_stub}"

  run script -q /dev/null env PLATFORM_STATUS_SCRIPT="${status_stub}" make -C "${REPO_ROOT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Platform workspace Makefile guide"* ]]
  [[ "${output}" == *"status --execute --output text"* ]]
}

@test "root status delegates to the platform status helper in text mode by default" {
  status_stub="${BATS_TEST_TMPDIR}/platform-status.sh"
  log_file="${BATS_TEST_TMPDIR}/platform-status.log"

  cat >"${status_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'status %s\n' "\$*" >>"${log_file}"
printf 'platform status text\n'
EOF
  chmod +x "${status_stub}"

  run make -C "${REPO_ROOT}" status PLATFORM_STATUS_SCRIPT="${status_stub}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"platform status text"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'status --execute --output text' ]
}

@test "root status supports json output without requiring platform env" {
  status_stub="${BATS_TEST_TMPDIR}/platform-status.sh"
  log_file="${BATS_TEST_TMPDIR}/platform-status-json.log"

  cat >"${status_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'status %s\n' "\$*" >>"${log_file}"
printf '{"overall_state":"idle"}\n'
EOF
  chmod +x "${status_stub}"

  run env PLATFORM_ENV_FILE="${BATS_TEST_TMPDIR}/missing.env" make -C "${REPO_ROOT}" status STATUS_FORMAT=json PLATFORM_STATUS_SCRIPT="${status_stub}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == '{"overall_state":"idle"}' ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'status --execute --output json' ]
}

@test "root tui delegates to the platform tui helper" {
  tui_stub="${BATS_TEST_TMPDIR}/platform-tui.sh"
  log_file="${BATS_TEST_TMPDIR}/platform-tui.log"

  cat >"${tui_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'tui %s\n' "\$*" >>"${log_file}"
printf 'platform tui\n'
EOF
  chmod +x "${tui_stub}"

  run make -C "${REPO_ROOT}" tui PLATFORM_TUI_SCRIPT="${tui_stub}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"platform tui"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'tui --execute' ]
}

@test "root prereqs and test are informational entrypoints" {
  run make -C "${REPO_ROOT}" prereqs

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Root prereqs is informational."* ]]
  [[ "${output}" == *"make -C .devcontainer prereqs"* ]]
  [[ "${output}" == *"make -C docker/compose prereqs"* ]]
  [[ "${output}" == *"make -C kubernetes/kind prereqs"* ]]

  run make -C "${REPO_ROOT}" test

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Root test is informational."* ]]
  [[ "${output}" == *"make -C docker/compose test"* ]]
  [[ "${output}" == *"make -C sd-wan/lima test"* ]]
}

@test "docker compose test resolves the backend helper in execute mode" {
  compose_backend_stub="${BATS_TEST_TMPDIR}/compose-backend.sh"
  compose_cmd_stub="${BATS_TEST_TMPDIR}/compose-cmd.sh"
  log_file="${BATS_TEST_TMPDIR}/compose.log"

  cat >"${compose_backend_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'backend %s\n' "\$*" >>"${log_file}"
if [ "\${1:-}" = "--print" ] && [ "\${2:-}" = "--execute" ]; then
  printf '%s\n' "${compose_cmd_stub}"
  exit 0
fi
printf 'unexpected backend args: %s\n' "\$*" >&2
exit 1
EOF
  chmod +x "${compose_backend_stub}"

  cat >"${compose_cmd_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'compose %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${compose_cmd_stub}"

  run make -C "${REPO_ROOT}/docker/compose" test \
    COMPOSE_BACKEND_SCRIPT="${compose_backend_stub}"

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'backend --print --execute\nbackend --print --execute\ncompose -f compose.yml --profile dev --profile uat config -q' ]
}

@test "root lint delegates to the repo validation scripts" {
  lint_yaml_stub="${BATS_TEST_TMPDIR}/lint-yaml.sh"
  lint_markdown_stub="${BATS_TEST_TMPDIR}/lint-markdown.sh"
  lint_bash32_stub="${BATS_TEST_TMPDIR}/lint-bash32.sh"
  lint_shell_stub="${BATS_TEST_TMPDIR}/lint-shell.sh"
  lint_cilium_stub="${BATS_TEST_TMPDIR}/lint-cilium.sh"
  lint_kyverno_stub="${BATS_TEST_TMPDIR}/lint-kyverno.sh"
  log_file="${BATS_TEST_TMPDIR}/lint.log"

  cat >"${lint_yaml_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'yaml %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${lint_yaml_stub}"

  cat >"${lint_cilium_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'cilium %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${lint_cilium_stub}"

  cat >"${lint_markdown_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'markdown %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${lint_markdown_stub}"

  cat >"${lint_bash32_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'bash32 %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${lint_bash32_stub}"

  cat >"${lint_shell_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'shell-audit %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${lint_shell_stub}"

  cat >"${lint_kyverno_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'kyverno %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${lint_kyverno_stub}"

  run make -C "${REPO_ROOT}" lint \
    LINT_YAML_SCRIPT="${lint_yaml_stub}" \
    LINT_MARKDOWN_SCRIPT="${lint_markdown_stub}" \
    LINT_BASH32_SCRIPT="${lint_bash32_stub}" \
    AUDIT_SHELL_SCRIPTS_SCRIPT="${lint_shell_stub}" \
    VALIDATE_CILIUM_POLICIES_SCRIPT="${lint_cilium_stub}" \
    VALIDATE_KYVERNO_POLICIES_SCRIPT="${lint_kyverno_stub}"

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'yaml --execute\nmarkdown --execute\nbash32 --execute\nshell-audit --execute\ncilium --mode static --execute\nkyverno --mode static --execute' ]
}

@test "root lint-bash32 delegates directly to the Bash 3.2 audit script" {
  lint_bash32_stub="${BATS_TEST_TMPDIR}/lint-bash32.sh"
  log_file="${BATS_TEST_TMPDIR}/lint-bash32.log"

  cat >"${lint_bash32_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'bash32 %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${lint_bash32_stub}"

  run make -C "${REPO_ROOT}" lint-bash32 \
    LINT_BASH32_SCRIPT="${lint_bash32_stub}"

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'bash32 --execute' ]
}

@test "root lint-shell delegates directly to the shell audit script" {
  lint_shell_stub="${BATS_TEST_TMPDIR}/lint-shell.sh"
  log_file="${BATS_TEST_TMPDIR}/lint-shell.log"

  cat >"${lint_shell_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'shell-audit %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${lint_shell_stub}"

  run make -C "${REPO_ROOT}" lint-shell \
    AUDIT_SHELL_SCRIPTS_SCRIPT="${lint_shell_stub}"

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'shell-audit --execute' ]
}

@test "root fmt delegates to the repo formatter scripts" {
  fmt_markdown_stub="${BATS_TEST_TMPDIR}/fmt-markdown.sh"
  log_file="${BATS_TEST_TMPDIR}/fmt.log"

  cat >"${fmt_markdown_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'fmt-markdown %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${fmt_markdown_stub}"

  run make -C "${REPO_ROOT}" fmt \
    FMT_MARKDOWN_SCRIPT="${fmt_markdown_stub}"

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'fmt-markdown --execute' ]
}

@test "root check-version delegates to the repo version checker" {
  check_version_stub="${BATS_TEST_TMPDIR}/check-version.sh"
  log_file="${BATS_TEST_TMPDIR}/check-version.log"

  cat >"${check_version_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'check-version %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${check_version_stub}"

  run make -C "${REPO_ROOT}" check-version \
    CHECK_VERSION_SCRIPT="${check_version_stub}"

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'check-version --execute' ]
}

@test "root release helpers delegate to the release and tag scripts" {
  release_stub="${BATS_TEST_TMPDIR}/release.sh"
  release_tag_stub="${BATS_TEST_TMPDIR}/release-tag.sh"
  log_file="${BATS_TEST_TMPDIR}/release.log"

  cat >"${release_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'release %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${release_stub}"

  cat >"${release_tag_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'tag %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${release_tag_stub}"

  run make -C "${REPO_ROOT}" release-dry-run VERSION=0.3.0 \
    RELEASE_SCRIPT="${release_stub}"

  [ "${status}" -eq 0 ]

  run make -C "${REPO_ROOT}" release-preview VERSION=0.3.0 \
    RELEASE_SCRIPT="${release_stub}"

  [ "${status}" -eq 0 ]

  run make -C "${REPO_ROOT}" release-tag-dry-run VERSION=0.3.0 \
    RELEASE_TAG_SCRIPT="${release_tag_stub}"

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'release --dry-run 0.3.0\nrelease --dry-run 0.3.0\ntag --dry-run 0.3.0' ]
}
