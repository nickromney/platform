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
  [[ "${output}" == *"make lint-cilium-live"* ]]
  [[ "${output}" == *"make lint-kyverno-live"* ]]
  [[ "${output}" == *"make prereqs"* ]]
  [[ "${output}" == *"make test"* ]]
  [[ "${output}" == *"make kubernetes"* ]]
  [[ "${output}" == *"make apps"* ]]
  [[ "${output}" == *"make sdwan"* ]]
}

@test "root bare make defaults to informational help" {
  run make -C "${REPO_ROOT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Platform workspace Makefile guide"* ]]
  [[ "${output}" == *"This root Makefile is primarily informational."* ]]
}

@test "root prereqs and test are informational entrypoints" {
  run make -C "${REPO_ROOT}" prereqs

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Root prereqs is informational."* ]]
  [[ "${output}" == *"make -C kubernetes/kind prereqs"* ]]

  run make -C "${REPO_ROOT}" test

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Root test is informational."* ]]
  [[ "${output}" == *"make -C sd-wan/lima test"* ]]
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
