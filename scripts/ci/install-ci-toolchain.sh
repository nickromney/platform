#!/usr/bin/env bash
set -euo pipefail

# The pinned toolchain the Linux CI job needs. macOS still runs the
# host-portable subset with brew; this script is written so that job can share
# the same pins later without copying a hundred-line YAML block.
#
# It lives here rather than inline in ci.yml because that is the shape this
# repo keeps finding defects in: the copies drift, and the one nobody looks at
# is the one that breaks. Every version comes from
# .devcontainer/toolchain-versions.sh, the single pin source, except the few
# noted below that are pinned literally here because they have no devcontainer
# equivalent. Nothing is taken from the runner image: that is how CI ended up
# on shellcheck 0.9.0 emitting 449 SC2317 findings that no local run could
# reproduce.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

INSTALL_DIR="${INSTALL_CI_TOOLCHAIN_PREFIX:-/usr/local/bin}"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Install the pinned lint and Bats toolchain for CI on Linux or macOS.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage \
  "would install the pinned CI toolchain into ${INSTALL_DIR}" "$@"

cd "${REPO_ROOT}"

# shellcheck source=/dev/null
source .devcontainer/toolchain-versions.sh

tool_version() {
  local requested="$1" entry
  for entry in "${DEVCONTAINER_ARKADE_TOOLS[@]}"; do
    if [[ "${entry%%=*}" == "${requested}" ]]; then
      printf '%s\n' "${entry#*=}"
      return 0
    fi
  done
  printf 'missing devcontainer tool version: %s\n' "${requested}" >&2
  exit 1
}

case "$(uname -s)" in
  Linux) os_name="linux" ;;
  Darwin) os_name="darwin" ;;
  *)
    printf 'unsupported operating system: %s\n' "$(uname -s)" >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64 | amd64)
    go_arch="amd64"
    kyverno_arch="x86_64"
    uv_arch="x86_64"
    shellcheck_arch="x86_64"
    ;;
  aarch64 | arm64)
    go_arch="arm64"
    kyverno_arch="arm64"
    uv_arch="aarch64"
    shellcheck_arch="aarch64"
    ;;
  *)
    printf 'unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

# Release-asset naming differs per project far more than it agrees, so the
# per-OS triples are spelled out rather than derived.
if [[ "${os_name}" == "darwin" ]]; then
  uv_triple="${uv_arch}-apple-darwin"
  ripgrep_target="${uv_arch}-apple-darwin"
  jq_asset="jq-macos-${go_arch}"
  yq_asset="yq_darwin_${go_arch}"
  deno_triple="${uv_arch}-apple-darwin"
else
  uv_triple="${uv_arch}-unknown-linux-gnu"
  # musl on x86_64 so rg does not depend on the image's glibc; ripgrep ships no
  # aarch64 musl build with the same guarantee, so arm64 takes gnu.
  if [[ "${uv_arch}" == "x86_64" ]]; then
    ripgrep_target="x86_64-unknown-linux-musl"
  else
    ripgrep_target="aarch64-unknown-linux-gnu"
  fi
  jq_asset="jq-linux-${go_arch}"
  yq_asset="yq_linux_${go_arch}"
  deno_triple="${uv_arch}-unknown-linux-gnu"
fi

# apt is the fallback, not the path. ubuntu-latest ships all of these, and
# ripgrep -- the one tool the image lacks that the gate needs -- comes from its
# pinned GitHub release below like shellcheck and kyverno. That matters because
# `apt-get update` alone has taken over six minutes here when the Azure mirror
# Ign:s and the run falls back to archive.ubuntu.com.
#
# The check stays so a changed runner image surfaces as a named install rather
# than a confusing failure later. Package names match command names for every
# tool here, so there is no separate map.
if [[ "${os_name}" == "linux" ]]; then
  missing_packages=()
  for command_name in curl git gzip make tar unzip; do
    command -v "${command_name}" >/dev/null 2>&1 ||
      missing_packages+=("${command_name}")
  done
  [[ -s /etc/ssl/certs/ca-certificates.crt ]] ||
    missing_packages+=(ca-certificates)

  if ((${#missing_packages[@]})); then
    printf 'installing missing base tools: %s\n' "${missing_packages[*]}"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends "${missing_packages[@]}"
    sudo rm -rf /var/lib/apt/lists/*
  else
    echo "OK   base tools already present on the runner image; skipping apt"
  fi
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

install_binary() {
  sudo install -m 0755 "$1" "${INSTALL_DIR}/$2"
}

# uv's pin lives in the devcontainer Dockerfile rather than toolchain-versions.sh.
uv_version="$(
  sed -nE 's#^COPY --from=ghcr.io/astral-sh/uv:([^ ]+).*#\1#p' .devcontainer/Dockerfile
)"
# Empty or multi-line: a second COPY --from=uv line would concatenate into a
# broken URL rather than a loud parse failure.
if [[ -z "${uv_version}" || "${uv_version}" == *$'\n'* ]]; then
  printf 'could not parse uv version from .devcontainer/Dockerfile\n' >&2
  exit 1
fi
curl -fsSL \
  "https://github.com/astral-sh/uv/releases/download/${uv_version}/uv-${uv_triple}.tar.gz" \
  | tar -xz -C "${tmp_dir}"
install_binary "${tmp_dir}/uv-${uv_triple}/uv" uv

export PATH="${INSTALL_DIR}:${HOME}/.local/bin:${PATH}"

# bats installs from source, so one asset serves both platforms. Pinned here
# because bats has no devcontainer pin: the devcontainer takes it from apt.
bats_version="1.13.0"
curl -fsSL \
  "https://github.com/bats-core/bats-core/archive/refs/tags/v${bats_version}.tar.gz" \
  | tar -xz -C "${tmp_dir}"
sudo "${tmp_dir}/bats-core-${bats_version}/install.sh" "$(dirname "${INSTALL_DIR}")"

kubectl_version="$(tool_version kubectl)"
curl -fsSL \
  "https://dl.k8s.io/release/${kubectl_version}/bin/${os_name}/${go_arch}/kubectl" \
  -o "${tmp_dir}/kubectl"
install_binary "${tmp_dir}/kubectl" kubectl

jq_version="$(tool_version jq)"
curl -fsSL \
  "https://github.com/jqlang/jq/releases/download/${jq_version}/${jq_asset}" \
  -o "${tmp_dir}/jq"
install_binary "${tmp_dir}/jq" jq

yq_version="$(tool_version yq)"
curl -fsSL \
  "https://github.com/mikefarah/yq/releases/download/${yq_version}/${yq_asset}.tar.gz" \
  | tar -xz -C "${tmp_dir}" "./${yq_asset}"
install_binary "${tmp_dir}/${yq_asset}" yq

# Pinned rather than installed from a package manager so no CI run pays for an
# apt-get update. Ten gated Bats files call rg.
ripgrep_dir="ripgrep-${RIPGREP_VERSION}-${ripgrep_target}"
curl -fsSL \
  "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/${ripgrep_dir}.tar.gz" \
  | tar -xz -C "${tmp_dir}" --strip-components=1 "${ripgrep_dir}/rg"
install_binary "${tmp_dir}/rg" rg

# Left to the runner image this was 0.9.0, which emits SC2317 ("Command appears
# to be unreachable") where 0.11.0 does not -- 449 findings no local run could
# reproduce.
shellcheck_archive="shellcheck-${SHELLCHECK_VERSION}.${os_name}.${shellcheck_arch}.tar.xz"
curl -fsSL \
  "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/${shellcheck_archive}" \
  | tar -xJ -C "${tmp_dir}" --strip-components=1 \
    "shellcheck-${SHELLCHECK_VERSION}/shellcheck"
install_binary "${tmp_dir}/shellcheck" shellcheck

kyverno_archive="kyverno-cli_${KYVERNO_VERSION}_${os_name}_${kyverno_arch}.tar.gz"
curl -fsSL \
  "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/${kyverno_archive}" \
  | tar -xz -C "${tmp_dir}" kyverno
install_binary "${tmp_dir}/kyverno" kyverno

uv tool install "yamllint==${YAMLLINT_VERSION}"
# make lint runs ruff over tests/app_contracts.py. Pinned rather than tracking
# latest so the rule set cannot change under a PR, the same reason ruff.toml
# states its selection explicitly.
uv tool install "ruff==${RUFF_VERSION}"
npm install --global "markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}"
# biome and deno are what apps/*/Makefile js-check calls. Neither was installed
# anywhere, so the browser JavaScript contracts skipped in CI and could only be
# exercised on a workstation that happened to have them.
npm install --global "@biomejs/biome@${BIOME_VERSION}"

# shellcheck disable=SC2153 # DENO_VERSION comes from toolchain-versions.sh
deno_version="${DENO_VERSION#v}"
curl -fsSL \
  "https://github.com/denoland/deno/releases/download/v${deno_version}/deno-${deno_triple}.zip" \
  -o "${tmp_dir}/deno.zip"
unzip -q -o "${tmp_dir}/deno.zip" -d "${tmp_dir}"
install_binary "${tmp_dir}/deno" deno

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${HOME}/.local/bin" >>"${GITHUB_PATH}"
fi

bats --version
kubectl version --client=true
jq --version
yq --version
rg --version
kyverno version
yamllint --version
ruff --version
shellcheck --version | sed -n 's/^version: /shellcheck /p'
markdownlint-cli2 --version
biome --version
deno --version
