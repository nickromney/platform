#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHELL_CLI_SOURCE="${REPO_ROOT}/scripts/lib/shell-cli.sh"
TOOLCHAIN_VERSIONS_FILE="${TOOLCHAIN_VERSIONS_FILE:-${SCRIPT_DIR}/toolchain-versions.sh}"

if [[ -f "${SHELL_CLI_SOURCE}" ]]; then
  # shellcheck source=/dev/null
  source "${SHELL_CLI_SOURCE}"
else
  shell_cli_script_name() {
    basename "$0"
  }

  shell_cli_unknown_flag() {
    local script_name="$1"
    local flag="$2"

    printf '%s: unknown flag: %s\n' "${script_name}" "${flag}" >&2
  }

  shell_cli_unexpected_arg() {
    local script_name="$1"
    local arg="$2"

    printf '%s: unexpected argument: %s\n' "${script_name}" "${arg}" >&2
  }

  shell_cli_missing_value() {
    local script_name="$1"
    local flag="$2"

    printf '%s: missing value for %s\n' "${script_name}" "${flag}" >&2
  }

  shell_cli_print_dry_run_summary() {
    printf 'INFO dry-run: %s\n' "$*"
  }

  shell_cli_standard_options() {
    cat <<'EOF'
Options:
  --dry-run  Show a summary and exit before side effects
  --execute  Execute the script body; without it the script prints help and/or preview output
  -h, --help Show this message
EOF
  }

  shell_cli_init_standard_flags() {
    SHELL_CLI_DRY_RUN=0
    SHELL_CLI_EXECUTE=0
  }

  shell_cli_handle_standard_flag() {
    local usage_fn="$1"
    local arg="$2"

    case "${arg}" in
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

  shell_cli_maybe_execute_or_preview_summary() {
    local usage_fn="$1"
    local dry_run_summary="$2"

    if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
      shell_cli_print_dry_run_summary "${dry_run_summary}"
      exit 0
    fi

    if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
      "${usage_fn}"
      shell_cli_print_dry_run_summary "${dry_run_summary}"
      exit 0
    fi
  }
fi

if [[ ! -f "${TOOLCHAIN_VERSIONS_FILE}" ]]; then
  printf 'missing required toolchain version file: %s\n' "${TOOLCHAIN_VERSIONS_FILE}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${TOOLCHAIN_VERSIONS_FILE}"

usage() {
  cat <<EOF
Usage: install-toolchain.sh [--username NAME] [--dry-run] [--execute]

Installs the devcontainer toolchain using Linux-native package sources plus
upstream installers for the tools not carried by apt.

Positional compatibility:
  install-toolchain.sh [username]

$(shell_cli_standard_options)
EOF
}

username=""
positional=()
shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --username)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--username"
        exit 1
      }
      username="$2"
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        positional+=("$1")
        shift
      done
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${username}" ]]; then
  username="${positional[0]:-vscode}"
fi
if [[ "${#positional[@]}" -gt 1 ]]; then
  shell_cli_unexpected_arg "$(shell_cli_script_name)" "${positional[1]}"
  exit 1
fi

OPENTOFU_INSTALL_DIR="${OPENTOFU_INSTALL_DIR:-/usr/local/lib/opentofu/${OPENTOFU_VERSION}}"
OPENTOFU_INSTALLER_URL="${OPENTOFU_INSTALLER_URL:-https://get.opentofu.org/install-opentofu.sh}"

shell_cli_maybe_execute_or_preview_summary usage \
  "would install the devcontainer toolchain for ${username}"

run_as_user() {
  local command="$1"
  sudo -Hiu "${username}" env PATH="/usr/local/bin:/usr/bin:/bin" bash -lc "${command}"
}

install_arkade_tool() {
  local tool="$1"
  local version="$2"

  arkade get "${tool}" --version "${version}" --path /usr/local/bin
}

arch_for_go_tools() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'amd64\n'
      ;;
    aarch64|arm64)
      printf 'arm64\n'
      ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

arch_for_kyverno() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'x86_64\n'
      ;;
    aarch64|arm64)
      printf 'arm64\n'
      ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

linux_arch_for_bun() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'x64\n'
      ;;
    aarch64|arm64)
      printf 'aarch64\n'
      ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

linux_arch_for_lima() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'x86_64\n'
      ;;
    aarch64|arm64)
      printf 'aarch64\n'
      ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

linux_arch_for_mkcert() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'amd64\n'
      ;;
    aarch64|arm64)
      printf 'arm64\n'
      ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

starship_release_asset() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'starship-x86_64-unknown-linux-gnu.tar.gz\n'
      ;;
    aarch64|arm64)
      printf 'starship-aarch64-unknown-linux-musl.tar.gz\n'
      ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

arkade_release_asset() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'arkade\n'
      ;;
    aarch64|arm64)
      printf 'arkade-arm64\n'
      ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

install_arkade() {
  local asset

  asset="$(arkade_release_asset)"
  curl -fsSL "https://github.com/alexellis/arkade/releases/download/${ARKADE_VERSION}/${asset}" -o /usr/local/bin/arkade
  chmod +x /usr/local/bin/arkade
}

install_bun() {
  local arch_name tmp_dir

  arch_name="$(linux_arch_for_bun)"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/oven-sh/bun/releases/download/${BUN_VERSION}/bun-linux-${arch_name}.zip" -o "${tmp_dir}/bun.zip"
  unzip -q "${tmp_dir}/bun.zip" -d "${tmp_dir}"
  install "${tmp_dir}/bun-linux-${arch_name}/bun" /usr/local/bin/bun
  ln -sf /usr/local/bin/bun /usr/local/bin/bunx
  mkdir -p "/home/${username}/.bun/bin"
  ln -sf /usr/local/bin/bun "/home/${username}/.bun/bin/bun"
  ln -sf /usr/local/bin/bunx "/home/${username}/.bun/bin/bunx"
  chown -R "${username}:${username}" "/home/${username}/.bun"
  rm -rf "${tmp_dir}"
}

install_lima() {
  local arch_name

  arch_name="$(linux_arch_for_lima)"
  curl -fsSL "https://github.com/lima-vm/lima/releases/download/${LIMA_VERSION}/lima-${LIMA_VERSION#v}-Linux-${arch_name}.tar.gz" | tar -C /usr/local -xz
  curl -fsSL "https://github.com/lima-vm/lima/releases/download/${LIMA_VERSION}/lima-additional-guestagents-${LIMA_VERSION#v}-Linux-${arch_name}.tar.gz" | tar -C /usr/local -xz
}

install_starship() {
  local asset tmp_dir

  asset="$(starship_release_asset)"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}/${asset}" -o "${tmp_dir}/starship.tgz"
  tar -xzf "${tmp_dir}/starship.tgz" -C "${tmp_dir}"
  install "${tmp_dir}/starship" /usr/local/bin/starship
  rm -rf "${tmp_dir}"
}

install_step() {
  local arch_name tmp_dir package_name

  arch_name="$(linux_arch_for_mkcert)"
  tmp_dir="$(mktemp -d)"
  package_name="step-cli_${STEP_VERSION#v}-1_${arch_name}.deb"
  curl -fsSL "https://github.com/smallstep/cli/releases/download/v${STEP_VERSION#v}/${package_name}" -o "${tmp_dir}/${package_name}"
  apt-get install -y "${tmp_dir}/${package_name}"
  rm -rf "${tmp_dir}"
}

install_kyverno() {
  local os_name arch_name archive tmp_dir

  os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch_name="$(arch_for_kyverno)"
  archive="kyverno-cli_${KYVERNO_VERSION}_${os_name}_${arch_name}.tar.gz"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/${archive}" | tar -xz -C "${tmp_dir}" kyverno
  install "${tmp_dir}/kyverno" /usr/local/bin/kyverno
  rm -rf "${tmp_dir}"
}

install_mkcert() {
  local arch_name tmp_dir

  arch_name="$(linux_arch_for_mkcert)"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VERSION}/mkcert-${MKCERT_VERSION}-linux-${arch_name}" -o "${tmp_dir}/mkcert"
  install "${tmp_dir}/mkcert" /usr/local/bin/mkcert
  rm -rf "${tmp_dir}"
}

install_opentofu() {
  local tmp_dir installer

  tmp_dir="$(mktemp -d)"
  installer="${tmp_dir}/install-opentofu.sh"
  curl -fsSL "${OPENTOFU_INSTALLER_URL}" -o "${installer}"
  chmod +x "${installer}"
  "${installer}" \
    --install-method standalone \
    --opentofu-version "${OPENTOFU_VERSION}" \
    --install-path "${OPENTOFU_INSTALL_DIR}" \
    --symlink-path /usr/local/bin
  rm -rf "${tmp_dir}"
}

install_playwright_chromium() {
  # Bake the browser runtime dependencies that the stage-900 SSO harness needs.
  run_as_user "bun x playwright install --with-deps chromium"
}

install_arkade
install_bun
install_starship
install_step
install_kyverno
install_lima
install_mkcert

for entry in "${DEVCONTAINER_ARKADE_TOOLS[@]}"; do
  install_arkade_tool "${entry%%=*}" "${entry#*=}"
done

install_opentofu

arkade oci install "${SLICER_IMAGE_REF}" --path /usr/local/bin

cat >/usr/local/bin/compose <<'EOF'
#!/usr/bin/env bash
exec docker compose "$@"
EOF
chmod +x /usr/local/bin/compose

install_playwright_chromium
