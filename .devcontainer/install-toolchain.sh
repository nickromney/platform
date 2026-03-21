#!/usr/bin/env bash
set -euo pipefail

username="${1:-vscode}"
brewfile_path="${2:-/tmp/devcontainer/Brewfile}"
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
