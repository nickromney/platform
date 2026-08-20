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
VIM_SENSIBLE_INSTALL_DIR="${VIM_SENSIBLE_INSTALL_DIR:-/usr/local/share/platform-devcontainer/vendor/vim-sensible}"

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

# ripgrep publishes Rust target triples rather than amd64/arm64. musl on x86_64
# so the binary does not depend on the image's glibc; there is no aarch64 musl
# build with the same guarantees, so arm64 takes the gnu one.
linux_target_for_ripgrep() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'x86_64-unknown-linux-musl\n'
      ;;
    aarch64|arm64)
      printf 'aarch64-unknown-linux-gnu\n'
      ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

linux_arch_for_lefthook() {
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

install_lefthook() {
  local arch_name asset tmp_dir

  arch_name="$(linux_arch_for_lefthook)"
  asset="lefthook_${LEFTHOOK_VERSION#v}_Linux_${arch_name}.gz"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/evilmartians/lefthook/releases/download/${LEFTHOOK_VERSION}/${asset}" -o "${tmp_dir}/lefthook.gz"
  gunzip -c "${tmp_dir}/lefthook.gz" >"${tmp_dir}/lefthook"
  install "${tmp_dir}/lefthook" /usr/local/bin/lefthook
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

# Pinned rather than apt-installed so every host -- devcontainer, Ubuntu on
# slicer-mac, Arch on omarchy, and CI -- runs the same ripgrep. Ten gated Bats
# files call rg, and distro packages drift by years between them.
install_ripgrep() {
  local target tmp_dir

  target="$(linux_target_for_ripgrep)"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-${target}.tar.gz" \
    | tar -xz -C "${tmp_dir}" --strip-components=1 "ripgrep-${RIPGREP_VERSION}-${target}/rg"
  install "${tmp_dir}/rg" /usr/local/bin/rg
  rm -rf "${tmp_dir}"
}

# Go was absent entirely, so tests/go-tests.bats -- 17 modules, ~9.5k lines --
# could never run in the devcontainer even though `make test-ci` claims to.
# GO_VERSION restates the modules' `go` directive because the image build sees
# only .devcontainer/ and cannot read go.mod; a test holds the two equal.
install_go() {
  local arch_name tmp_dir go_version

  # shellcheck disable=SC2153 # GO_VERSION comes from toolchain-versions.sh
  go_version="${GO_VERSION}"

  arch_name="$(linux_arch_for_mkcert)"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://go.dev/dl/go${go_version}.linux-${arch_name}.tar.gz" \
    -o "${tmp_dir}/go.tar.gz"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "${tmp_dir}/go.tar.gz"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  rm -rf "${tmp_dir}"
}

# Was apt's 0.9.0, which emits SC2317 ("Command appears to be unreachable")
# where 0.11.0 does not. #202 pinned CI away from exactly this and left the
# devcontainer on it, so `make lint` disagreed between the two.
install_shellcheck() {
  local arch_name tmp_dir

  case "$(uname -m)" in
    x86_64 | amd64) arch_name="x86_64" ;;
    aarch64 | arm64) arch_name="aarch64" ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac

  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.${arch_name}.tar.xz" \
    | tar -xJ -C "${tmp_dir}" --strip-components=1 "shellcheck-${SHELLCHECK_VERSION}/shellcheck"
  install "${tmp_dir}/shellcheck" /usr/local/bin/shellcheck
  rm -rf "${tmp_dir}"
}

# Was apt's 1.33.0 against CI's 1.38.0. uv is already in the image.
install_yamllint() {
  # The build runs as root but the container runs as vscode, so uv's defaults
  # (~/.local under root) leave the tool present and unreachable -- which is
  # exactly how the first attempt at this "installed" yamllint and still had
  # `command -v yamllint` fail. Put both the venv and the shim on system paths.
  UV_TOOL_DIR=/usr/local/share/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install --force "yamllint==${YAMLLINT_VERSION}"
  chmod -R a+rX /usr/local/share/uv
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

install_vim_sensible_source() {
  local tmp_dir archive_path

  tmp_dir="$(mktemp -d)"
  archive_path="${tmp_dir}/vim-sensible.tar.gz"
  curl -fsSL "https://github.com/tpope/vim-sensible/archive/${VIM_SENSIBLE_REF}.tar.gz" -o "${archive_path}"
  rm -rf "${VIM_SENSIBLE_INSTALL_DIR}"
  mkdir -p "${VIM_SENSIBLE_INSTALL_DIR}"
  tar -xzf "${archive_path}" --strip-components=1 -C "${VIM_SENSIBLE_INSTALL_DIR}"
  chmod -R a+rX "${VIM_SENSIBLE_INSTALL_DIR}"
  rm -rf "${tmp_dir}"
}

install_playwright_runtime_deps() {
  # Bake the Linux runtime packages only; tests still install the browser binary on demand.
  HOME="/home/${username}" XDG_CACHE_HOME="/home/${username}/.cache" bun x playwright install-deps chromium
}

cleanup_toolchain_caches() {
  apt-get clean
  rm -rf \
    /var/lib/apt/lists/* \
    /var/cache/apt/archives/* \
    /var/cache/apt/*.bin \
    "/home/${username}/.arkade" \
    "/home/${username}/.bun/install/cache" \
    "/home/${username}/.cache" \
    "/home/${username}/.npm" \
    /root/.arkade \
    /root/.cache \
    /root/.npm
}

install_arkade
install_bun
install_starship
install_step
install_kyverno
install_lefthook
install_lima
install_mkcert
install_ripgrep
install_go
install_shellcheck
install_yamllint
install_vim_sensible_source

for entry in "${DEVCONTAINER_ARKADE_TOOLS[@]}"; do
  install_arkade_tool "${entry%%=*}" "${entry#*=}"
done

install_opentofu

cat >/usr/local/bin/compose <<'EOF'
#!/usr/bin/env bash
exec docker compose "$@"
EOF
chmod +x /usr/local/bin/compose

install_playwright_runtime_deps
cleanup_toolchain_caches
