#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

usage() {
  cat <<'EOF'
Usage: install-tool-hints.sh [--plain] [--tool TOOL]... [--dry-run] [--execute]

Print install commands for missing tools using this preference order:
  1. arkade
  2. Homebrew
  3. apt
  4. curl

Options:
  --plain      suppress the environment header
  --tool TOOL  add a requested tool (repeatable)
  --dry-run    show the requested tool set and exit before emitting hints
  --execute    emit install hints (preferred explicit form for query workflows)
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

tool_supports_arkade_get() {
  case "$1" in
    cilium|gh|helm|hubble|jq|k3sup|kind|kubectl|kubie|kubectx|mkcert|terragrunt|tofu|yq)
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

  if tool_supports_arkade_get "${tool}"; then
    printf 'sudo arkade get %s --path /usr/local/bin\n' "${tool}"
    return 0
  fi

  if tool_supports_arkade_system "${tool}"; then
    printf 'sudo arkade system install node\n'
    return 0
  fi

  return 1
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
    slicer)
      printf '%s\n' \
        'curl -sLS https://get.arkade.dev | sudo -E sh && sudo -E arkade oci install ghcr.io/openfaasltd/slicer:latest --path /usr/local/bin'
      return 0
      ;;
    slicer-mac)
      printf 'Install slicer first, then run: slicer install slicer-mac ~/slicer-mac\n'
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
      printf '%s\n' 'python3 -m pip install --user yamllint'
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

hint_for_tool() {
  local tool="$1"
  local os_name="$2"

  if [[ "${have_arkade}" == "1" ]]; then
    arkade_hint "${tool}" && return 0
  fi

  if [[ "${have_brew}" == "1" ]]; then
    brew_hint "${tool}" "${os_name}" && return 0
  fi

  if [[ "${have_apt}" == "1" ]]; then
    apt_hint "${tool}" && return 0
  fi

  if [[ "${have_curl}" == "1" ]]; then
    curl_hint "${tool}" "${os_name}" && return 0
  fi

  return 1
}

plain_output=0
dry_run=0
requested_tools=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --plain)
      plain_output=1
      ;;
    --tool)
      shift
      [[ "$#" -gt 0 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--tool" >&2; exit 1; }
      requested_tools+=("$1")
      ;;
    --dry-run)
      dry_run=1
      ;;
    --execute)
      ;;
    -h|--help)
      usage
      exit 0
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

if [[ "${dry_run}" == "1" ]]; then
  if [[ "${#requested_tools[@]}" -gt 0 ]]; then
    shell_cli_print_dry_run_summary "would print install hints for ${#requested_tools[@]} tool(s)"
  else
    shell_cli_print_dry_run_summary "would print install hints for the requested tool set"
  fi
  exit 0
fi

if [[ "${#requested_tools[@]}" -lt 1 ]]; then
  usage >&2
  exit 2
fi

os_name="$(uname -s 2>/dev/null || echo unknown)"
arch_name="$(uname -m 2>/dev/null || echo unknown)"
platform_label="${os_name}"
if [[ "${os_name}" == "Linux" ]] && grep -Eiq '(microsoft|wsl)' /proc/version 2>/dev/null; then
  platform_label="Linux (WSL)"
fi

have_arkade=0
have_brew=0
have_apt=0
have_curl=0

have_cmd arkade && have_arkade=1
have_cmd brew && have_brew=1
have_cmd apt-get && have_apt=1
have_cmd curl && have_curl=1

if [[ "${plain_output}" != "1" ]]; then
  printf 'Install hints for %s %s (arkade=%s, brew=%s, apt=%s, curl=%s):\n' \
    "${platform_label}" \
    "${arch_name}" \
    "${have_arkade}" \
    "${have_brew}" \
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
