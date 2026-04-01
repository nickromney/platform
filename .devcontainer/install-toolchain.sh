#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: install-toolchain.sh [--username NAME] [--brewfile-path PATH] [--dry-run] [--execute]

Installs the devcontainer host toolchain, Homebrew bundle, arkade tools, Lima,
and Node/Bun shims.

Positional compatibility:
  install-toolchain.sh [username] [brewfile_path]

$(shell_cli_standard_options)
EOF
}

username=""
brewfile_path=""
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
    --brewfile-path)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--brewfile-path"
        exit 1
      }
      brewfile_path="$2"
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
if [[ -z "${brewfile_path}" ]]; then
  brewfile_path="${positional[1]:-/tmp/devcontainer/Brewfile}"
fi
if [[ "${#positional[@]}" -gt 2 ]]; then
  shell_cli_unexpected_arg "$(shell_cli_script_name)" "${positional[2]}"
  exit 1
fi

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would install the devcontainer toolchain for ${username} using ${brewfile_path}"
  exit 0
fi

brew_prefix="${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}"
brew_bin="${brew_prefix}/bin/brew"

run_as_user() {
  local command="$1"
  sudo -Hiu "${username}" env \
    HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}" \
    HOMEBREW_NO_ENV_HINTS="${HOMEBREW_NO_ENV_HINTS:-1}" \
    HOMEBREW_NO_INSTALL_CLEANUP="${HOMEBREW_NO_INSTALL_CLEANUP:-1}" \
    PATH="${brew_prefix}/bin:${brew_prefix}/sbin:/usr/local/bin:/usr/bin:/bin" \
    bash -lc "${command}"
}

install_arkade_tool() {
  local tool="$1"
  arkade get "${tool}" --path /usr/local/bin
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

if [[ ! -x "${brew_bin}" ]]; then
  echo "brew not found at ${brew_bin}" >&2
  exit 1
fi

run_as_user "\"${brew_bin}\" bundle install --file \"${brewfile_path}\" --no-upgrade"
install_lima

if ! command -v arkade >/dev/null 2>&1; then
  curl -fsSL https://get.arkade.dev | sh
fi

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

if [[ -x "${brew_prefix}/opt/node@24/bin/node" ]]; then
  ln -sf "${brew_prefix}/opt/node@24/bin/node" /usr/local/bin/node
  ln -sf "${brew_prefix}/opt/node@24/bin/npm" /usr/local/bin/npm
  ln -sf "${brew_prefix}/opt/node@24/bin/npx" /usr/local/bin/npx
  if [[ -x "${brew_prefix}/opt/node@24/bin/corepack" ]]; then
    ln -sf "${brew_prefix}/opt/node@24/bin/corepack" /usr/local/bin/corepack
  fi
fi

if [[ -x "/home/${username}/.bun/bin/bun" ]]; then
  ln -sf "/home/${username}/.bun/bin/bun" /usr/local/bin/bun
fi

if [[ -x "/home/${username}/.bun/bin/bunx" ]]; then
  ln -sf "/home/${username}/.bun/bin/bunx" /usr/local/bin/bunx
fi
