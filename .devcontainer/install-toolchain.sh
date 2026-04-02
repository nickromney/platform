#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHELL_CLI_SOURCE="${REPO_ROOT}/scripts/lib/shell-cli.sh"

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
fi

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

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would install the devcontainer toolchain for ${username}"
  exit 0
fi

run_as_user() {
  local command="$1"
  sudo -Hiu "${username}" env PATH="/usr/local/bin:/usr/bin:/bin" bash -lc "${command}"
}

install_arkade_tool() {
  local tool="$1"
  arkade get "${tool}" --path /usr/local/bin
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

install_lima() {
  local version=""

  version="$(curl -fsSL https://api.github.com/repos/lima-vm/lima/releases/latest | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

  if [[ -z "${version}" ]]; then
    echo "failed to resolve latest Lima release" >&2
    exit 1
  fi

  curl -fsSL "https://github.com/lima-vm/lima/releases/download/${version}/lima-${version#v}-$(uname -s)-$(uname -m).tar.gz" | tar -C /usr/local -xz
  curl -fsSL "https://github.com/lima-vm/lima/releases/download/${version}/lima-additional-guestagents-${version#v}-$(uname -s)-$(uname -m).tar.gz" | tar -C /usr/local -xz
}

install_starship() {
  if command -v starship >/dev/null 2>&1; then
    return 0
  fi

  curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir /usr/local/bin
}

install_step() {
  local os_name arch_name tmp_dir

  os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch_name="$(arch_for_go_tools)"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://dl.smallstep.com/cli/docs-cli-install/latest/step_${os_name}_${arch_name}.tar.gz" | tar -xz -C "${tmp_dir}"
  install "${tmp_dir}"/*/bin/step /usr/local/bin/step
  rm -rf "${tmp_dir}"
}

install_kyverno() {
  local os_name arch_name version archive tmp_dir

  os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch_name="$(arch_for_kyverno)"
  version="$(curl -fsSL https://api.github.com/repos/kyverno/kyverno/releases/latest | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  archive="kyverno-cli_${version}_${os_name}_${arch_name}.tar.gz"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/kyverno/kyverno/releases/download/${version}/${archive}" | tar -xz -C "${tmp_dir}" kyverno
  install "${tmp_dir}/kyverno" /usr/local/bin/kyverno
  rm -rf "${tmp_dir}"
}

if ! command -v arkade >/dev/null 2>&1; then
  curl -fsSL https://get.arkade.dev | sh
fi

install_starship
install_step
install_kyverno
install_lima
run_as_user "curl -fsSL https://bun.sh/install | bash"

arkade_tools=(
  cilium
  helm
  hubble
  jq
  k3sup
  kind
  kubectl
  kubie
  kubectx
  mkcert
  terragrunt
  tofu
  yq
)

for tool in "${arkade_tools[@]}"; do
  install_arkade_tool "${tool}"
done

arkade oci install ghcr.io/openfaasltd/slicer:latest --path /usr/local/bin

cat >/usr/local/bin/compose <<'EOF'
#!/usr/bin/env bash
exec docker compose "$@"
EOF
chmod +x /usr/local/bin/compose

if [[ -x "/home/${username}/.bun/bin/bun" ]]; then
  ln -sf "/home/${username}/.bun/bin/bun" /usr/local/bin/bun
fi

if [[ -x "/home/${username}/.bun/bin/bunx" ]]; then
  ln -sf "/home/${username}/.bun/bin/bunx" /usr/local/bin/bunx
fi
