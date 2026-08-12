#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Ordered by upgrade story, not convenience. mise, brew, pacman, and apt all
# have a one-command upgrade path (mise upgrade, brew upgrade, pacman -Syu,
# apt upgrade), so they come first; mise leads because it installs the same
# versions on macOS and Linux. arkade pins a binary and offers no upgrade
# sweep, so it sits just above raw curl as the fallback for tools the managers
# above do not carry.
INSTALL_TOOL_HINTS_MANAGERS="${INSTALL_TOOL_HINTS_MANAGERS:-mise brew pacman apt arkade curl}"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--plain] [--tool TOOL]... [--dry-run] [--execute]

Print install commands for missing tools using this preference order:
  1. mise      (cross-platform, "mise upgrade")
  2. Homebrew  ("brew upgrade")
  3. pacman    ("pacman -Syu")
  4. apt       ("apt upgrade")
  5. arkade    (pinned binary, no upgrade sweep)
  6. curl      (last resort)

Only managers present on PATH are used. Override the order (or narrow it to a
single manager) with INSTALL_TOOL_HINTS_MANAGERS, for example:
  INSTALL_TOOL_HINTS_MANAGERS="pacman curl" @SCRIPT_NAME@ --execute docker

Options:
  --plain      suppress the environment header
  --tool TOOL  add a requested tool (repeatable)
  --dry-run    show the requested tool set and exit before emitting hints
  --execute    emit install hints
  -h, --help   show this help
EOF
}

normalize_tool() {
  case "$1" in
    k3sup-pro|k3sup|'k3sup-pro|k3sup')
      echo "k3sup"
      ;;
    bats-core)
      echo "bats"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

# Verified against `arkade get -o list`. Tools arkade does not carry (bats,
# node, shellcheck) fall through to the next manager in the chain.
tool_supports_arkade_get() {
  case "$1" in
    argocd|bun|cilium|gh|helm|hubble|jq|k3sup|k9s|kind|kubectl|kubie|kubectx|kyverno|mkcert|starship|step|terragrunt|tofu|trivy|yq)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

tool_supports_arkade_system() {
  case "$1" in
    node|npm|npx)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

arkade_hint() {
  local tool="$1"
  local pinned=""

  if tool_supports_arkade_get "${tool}"; then
    pinned="$(pinned_version_for_tool "${tool}" || true)"
    # No sudo, no /usr/local/bin: installing into the arkade-owned user
    # directory keeps the platform out of system-wide PATH.
    if [[ -n "${pinned}" ]]; then
      printf 'arkade get %s@%s\n' "${tool}" "${pinned}"
    else
      printf 'arkade get %s\n' "${tool}"
    fi
    return 0
  fi

  if tool_supports_arkade_system "${tool}"; then
    printf 'sudo arkade system install node\n'
    return 0
  fi

  return 1
}

# .devcontainer/toolchain-versions.sh is the repo's single source of truth for
# tool versions. Hints must reproduce those pins rather than resolving
# "latest", so that a fresh host lands on the same versions the repo was
# validated against, and so that no install bypasses the release-age cooldown
# that governs when those pins move.
TOOLCHAIN_VERSIONS_FILE="${TOOLCHAIN_VERSIONS_FILE:-${SCRIPT_DIR}/../.devcontainer/toolchain-versions.sh}"
toolchain_pins_loaded=0

load_toolchain_pins() {
  [[ "${toolchain_pins_loaded}" -eq 0 ]] || return 0
  toolchain_pins_loaded=1
  [[ -r "${TOOLCHAIN_VERSIONS_FILE}" ]] || return 0
  # shellcheck source=/dev/null
  source "${TOOLCHAIN_VERSIONS_FILE}" 2>/dev/null || true
}

# Pins carry tool-specific prefixes (v0.19.7, jq-1.8.2, bun-v1.3.14). Reduce
# them to the bare version that mise and arkade both accept.
normalize_pin() {
  local raw="$1"

  raw="${raw#jq-}"
  raw="${raw#bun-}"
  raw="${raw#v}"
  printf '%s\n' "${raw}"
}

pinned_version_for_tool() {
  local tool="$1"
  local entry="" name="" value="" var_name=""

  load_toolchain_pins

  for entry in "${DEVCONTAINER_ARKADE_TOOLS[@]-}"; do
    name="${entry%%=*}"
    if [[ "${name}" == "${tool}" ]]; then
      normalize_pin "${entry#*=}"
      return 0
    fi
  done

  case "${tool}" in
    bun|kyverno|lima|limactl|mkcert|starship|step) ;;
    tofu) var_name="OPENTOFU_VERSION" ;;
    node|npm|npx) var_name="DEVCONTAINER_NODE_VERSION" ;;
    *) return 1 ;;
  esac

  if [[ -z "${var_name}" ]]; then
    case "${tool}" in
      limactl) var_name="LIMA_VERSION" ;;
      *) var_name="$(printf '%s' "${tool}" | tr '[:lower:]' '[:upper:]')_VERSION" ;;
    esac
  fi

  value="${!var_name-}"
  [[ -n "${value}" ]] || return 1
  normalize_pin "${value}"
}

mise_tool() {
  case "$1" in
    bats|bun|gh|go|helm|jq|k3sup|kind|kubectl|kubectx|kyverno|mkcert|node|shellcheck|starship|step|terragrunt|yamllint|yq)
      printf '%s\n' "$1"
      ;;
    cilium)
      printf 'cilium-cli\n'
      ;;
    hubble)
      printf 'github:cilium/hubble\n'
      ;;
    limactl)
      printf 'lima\n'
      ;;
    npm|npx)
      printf 'node\n'
      ;;
    tofu)
      printf 'opentofu\n'
      ;;
    *)
      return 1
      ;;
  esac
}

mise_hint() {
  local tool="$1"
  local mise_name="" pinned=""

  mise_name="$(mise_tool "${tool}" || true)"
  [[ -n "${mise_name}" ]] || return 1
  pinned="$(pinned_version_for_tool "${tool}" || true)"
  # Deliberately NOT "mise use -g": the global config is the engineer's own
  # (often dotfiles-managed) file. This writes ./mise.toml in the repo instead,
  # so the platform's pins stay scoped to the platform.
  printf 'mise use %s@%s\n' "${mise_name}" "${pinned:-latest}"
}

brew_formula() {
  local tool="$1"
  local os_name="$2"

  case "${tool}" in
    bats)
      printf 'bats-core\n'
      ;;
    bun)
      printf 'bun\n'
      ;;
    cilium|hubble)
      printf 'cilium-cli\n'
      ;;
    curl|gh|git|helm|jq|k3sup|kind|kubie|kubectx|kyverno|mkcert|podman|podman-compose|shellcheck|starship|step|terragrunt|yamllint|yq)
      printf '%s\n' "${tool}"
      ;;
    docker)
      if [[ "${os_name}" == "Darwin" ]]; then
        printf '%s\n' '--cask docker'
      else
        printf '%s\n' 'docker'
      fi
      ;;
    kubectl)
      printf 'kubernetes-cli\n'
      ;;
    limactl)
      printf 'lima\n'
      ;;
    node|npm|npx)
      printf 'node\n'
      ;;
    ssh|ssh-keygen)
      printf 'openssh\n'
      ;;
    tofu)
      printf 'opentofu\n'
      ;;
    *)
      return 1
      ;;
  esac
}

brew_hint() {
  local tool="$1"
  local os_name="$2"
  local formula=""

  formula="$(brew_formula "${tool}" "${os_name}" || true)"
  [[ -n "${formula}" ]] || return 1
  printf 'brew install %s\n' "${formula}"
}

pacman_packages() {
  case "$1" in
    bats)
      printf 'bats\n'
      ;;
    bun)
      printf 'bun\n'
      ;;
    cilium|hubble)
      printf 'cilium-cli\n'
      ;;
    curl|docker|git|helm|jq|kind|kubectl|kubectx|podman|podman-compose|shellcheck|starship|terragrunt|yamllint)
      printf '%s\n' "$1"
      ;;
    gh)
      printf 'github-cli\n'
      ;;
    mkcert)
      printf 'mkcert nss\n'
      ;;
    node|npm|npx)
      printf 'nodejs npm\n'
      ;;
    ssh|ssh-keygen)
      printf 'openssh\n'
      ;;
    step)
      printf 'step-cli\n'
      ;;
    tofu)
      printf 'opentofu\n'
      ;;
    # Arch ships kislyuk/yq as "yq"; the repo uses mikefarah/yq syntax.
    yq)
      printf 'go-yq\n'
      ;;
    *)
      return 1
      ;;
  esac
}

pacman_hint() {
  local tool="$1"
  local packages=""

  packages="$(pacman_packages "${tool}" || true)"
  [[ -n "${packages}" ]] || return 1
  printf 'sudo pacman -S --needed %s\n' "${packages}"
}

apt_packages() {
  case "$1" in
    bats)
      printf 'bats\n'
      ;;
    curl)
      printf 'curl\n'
      ;;
    docker)
      printf 'docker.io\n'
      ;;
    git)
      printf 'git\n'
      ;;
    jq)
      printf 'jq\n'
      ;;
    yq)
      printf 'yq\n'
      ;;
    mkcert)
      printf 'mkcert libnss3-tools\n'
      ;;
    ssh|ssh-keygen)
      printf 'openssh-client\n'
      ;;
    node|npm|npx)
      printf 'nodejs npm\n'
      ;;
    podman)
      printf 'podman\n'
      ;;
    podman-compose)
      printf 'podman-compose\n'
      ;;
    shellcheck)
      printf 'shellcheck\n'
      ;;
    yamllint)
      printf 'yamllint\n'
      ;;
    *)
      return 1
      ;;
  esac
}

apt_hint() {
  local tool="$1"
  local packages=""

  case "${tool}" in
    step)
      printf '%s\n' 'sudo apt-get update && sudo apt-get install -y --no-install-recommends ca-certificates curl gpg && sudo install -d -m 0755 /etc/apt/keyrings && curl -fsSL https://packages.smallstep.com/keys/apt/repo-signing-key.gpg | sudo tee /etc/apt/keyrings/smallstep.asc >/dev/null && printf "%s\n" "Types: deb" "URIs: https://packages.smallstep.com/stable/debian" "Suites: debs" "Components: main" "Signed-By: /etc/apt/keyrings/smallstep.asc" | sudo tee /etc/apt/sources.list.d/smallstep.sources >/dev/null && sudo apt-get update && sudo apt-get install -y step-cli'
      return 0
      ;;
  esac

  packages="$(apt_packages "${tool}" || true)"
  [[ -n "${packages}" ]] || return 1
  printf 'sudo apt-get update && sudo apt-get install -y %s\n' "${packages}"
}

curl_hint() {
  local tool="$1"
  local os_name="$2"

  case "${tool}" in
    bun)
      printf '%s\n' 'curl -fsSL https://bun.sh/install | bash'
      return 0
      ;;
    docker)
      if [[ "${os_name}" == "Linux" ]]; then
        printf 'curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh\n'
        return 0
      fi
      if [[ "${os_name}" == "Darwin" ]]; then
        # shellcheck disable=SC2016
        printf '%s\n' \
          'arch=$(uname -m) && case "$arch" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) echo "unsupported architecture: $arch" >&2; exit 1 ;; esac && curl -fL "https://desktop.docker.com/mac/main/${arch}/Docker.dmg" -o Docker.dmg && open Docker.dmg'
        return 0
      fi
      ;;
    limactl)
      # shellcheck disable=SC2016
      printf '%s\n' \
        'VERSION=$(curl -fsSL https://api.github.com/repos/lima-vm/lima/releases/latest | sed -n '\''s/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p'\'' | head -n 1) && curl -fsSL "https://github.com/lima-vm/lima/releases/download/${VERSION}/lima-${VERSION#v}-$(uname -s)-$(uname -m).tar.gz" | sudo tar Cxzv /usr/local && curl -fsSL "https://github.com/lima-vm/lima/releases/download/${VERSION}/lima-additional-guestagents-${VERSION#v}-$(uname -s)-$(uname -m).tar.gz" | sudo tar Cxzv /usr/local'
      return 0
      ;;
    step)
      # shellcheck disable=SC2016
      printf '%s\n' \
        'os=$(uname -s | tr '\''[:upper:]'\'' '\''[:lower:]'\'') && arch=$(uname -m) && case "$arch" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) echo "unsupported architecture: $arch" >&2; exit 1 ;; esac && tmp=$(mktemp -d) && curl -fsSL "https://dl.smallstep.com/cli/docs-cli-install/latest/step_${os}_${arch}.tar.gz" | tar -xz -C "$tmp" && sudo install "$tmp"/*/bin/step /usr/local/bin/step && rm -rf "$tmp"'
      return 0
      ;;
    kyverno)
      # shellcheck disable=SC2016
      printf '%s\n' \
        'os=$(uname -s | tr '\''[:upper:]'\'' '\''[:lower:]'\'') && arch=$(uname -m) && case "$arch" in x86_64|amd64) arch=x86_64 ;; aarch64|arm64) arch=arm64 ;; *) echo "unsupported architecture: $arch" >&2; exit 1 ;; esac && version=$(curl -fsSL https://api.github.com/repos/kyverno/kyverno/releases/latest | sed -n '\''s/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p'\'' | head -n 1) && archive="kyverno-cli_${version}_${os}_${arch}.tar.gz" && curl -fLO "https://github.com/kyverno/kyverno/releases/download/${version}/${archive}" && tar -xzf "${archive}" kyverno && sudo install kyverno /usr/local/bin/kyverno'
      return 0
      ;;
    yamllint)
      printf '%s\n' 'uv tool install yamllint'
      return 0
      ;;
  esac

  if tool_supports_arkade_get "${tool}"; then
    # shellcheck disable=SC2016
    printf 'curl -sLS https://get.arkade.dev | sudo -E sh && sudo arkade get %s --path /usr/local/bin\n' "${tool}"
    return 0
  fi

  if tool_supports_arkade_system "${tool}"; then
    printf 'curl -sLS https://get.arkade.dev | sudo -E sh && sudo arkade system install node\n'
    return 0
  fi

  return 1
}

manager_available() {
  case "$1" in
    mise) [[ "${have_mise}" == "1" ]] ;;
    arkade) [[ "${have_arkade}" == "1" ]] ;;
    brew) [[ "${have_brew}" == "1" ]] ;;
    pacman) [[ "${have_pacman}" == "1" ]] ;;
    apt) [[ "${have_apt}" == "1" ]] ;;
    curl) [[ "${have_curl}" == "1" ]] ;;
    *) return 1 ;;
  esac
}

manager_hint() {
  local manager="$1"
  local tool="$2"
  local os_name="$3"

  case "${manager}" in
    mise) mise_hint "${tool}" ;;
    arkade) arkade_hint "${tool}" ;;
    brew) brew_hint "${tool}" "${os_name}" ;;
    pacman) pacman_hint "${tool}" ;;
    apt) apt_hint "${tool}" ;;
    curl) curl_hint "${tool}" "${os_name}" ;;
    *) return 1 ;;
  esac
}

hint_for_tool() {
  local tool="$1"
  local os_name="$2"
  local manager=""

  for manager in ${INSTALL_TOOL_HINTS_MANAGERS}; do
    manager_available "${manager}" || continue
    manager_hint "${manager}" "${tool}" "${os_name}" && return 0
  done

  return 1
}

plain_output=0
requested_tools=()

shell_cli_init_standard_flags
while [[ "$#" -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --plain)
      plain_output=1
      ;;
    --tool)
      shift
      [[ "$#" -gt 0 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--tool" >&2; exit 1; }
      requested_tools+=("$1")
      ;;
    --)
      shift
      break
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 2
      ;;
    *)
      requested_tools+=("$1")
      ;;
  esac
  shift
done

while [[ "$#" -gt 0 ]]; do
  requested_tools+=("$1")
  shift
done

if [[ "${#requested_tools[@]}" -gt 0 ]]; then
  shell_cli_maybe_execute_or_preview_summary usage \
    "would print install hints for ${#requested_tools[@]} tool(s)"
else
  shell_cli_maybe_execute_or_preview_summary usage \
    "would print install hints for the requested tool set"
fi

if [[ "${#requested_tools[@]}" -lt 1 ]]; then
  usage >&2
  exit 2
fi

os_name="$(uname -s 2>/dev/null || echo "OS not reported")"
arch_name="$(uname -m 2>/dev/null || echo "architecture not reported")"
platform_label="${os_name}"
if [[ "${os_name}" == "Linux" ]] && grep -Eiq '(microsoft|wsl)' /proc/version 2>/dev/null; then
  platform_label="Linux (WSL)"
fi

have_mise=0
have_arkade=0
have_brew=0
have_pacman=0
have_apt=0
have_curl=0

have_cmd mise && have_mise=1
have_cmd arkade && have_arkade=1
have_cmd brew && have_brew=1
have_cmd pacman && have_pacman=1
have_cmd apt-get && have_apt=1
have_cmd curl && have_curl=1

if [[ "${plain_output}" != "1" ]]; then
  printf 'Install hints for %s %s (mise=%s, arkade=%s, brew=%s, pacman=%s, apt=%s, curl=%s):\n' \
    "${platform_label}" \
    "${arch_name}" \
    "${have_mise}" \
    "${have_arkade}" \
    "${have_brew}" \
    "${have_pacman}" \
    "${have_apt}" \
    "${have_curl}"
fi

for requested_tool in "${requested_tools[@]}"; do
  tool="$(normalize_tool "${requested_tool}")"
  if hint="$(hint_for_tool "${tool}" "${os_name}" 2>/dev/null)"; then
    if [[ "${plain_output}" == "1" ]]; then
      printf '%s: %s\n' "${requested_tool}" "${hint}"
    else
      printf '  %s: %s\n' "${requested_tool}" "${hint}"
    fi
  else
    if [[ "${plain_output}" == "1" ]]; then
      printf '%s: no install hint available; use the official installation docs for this tool\n' "${requested_tool}"
    else
      printf '  %s: no install hint available; use the official installation docs for this tool\n' "${requested_tool}"
    fi
  fi
done
