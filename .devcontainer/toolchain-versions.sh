#!/usr/bin/env bash

DEVCONTAINER_DOCKER_FEATURE_REF="${DEVCONTAINER_DOCKER_FEATURE_REF:-ghcr.io/devcontainers/features/docker-outside-of-docker:1.9.1}"
DEVCONTAINER_DOCKER_CLI_VERSION="${DEVCONTAINER_DOCKER_CLI_VERSION:-29.4.1}"
DEVCONTAINER_DOCKER_BUILDX_VERSION="${DEVCONTAINER_DOCKER_BUILDX_VERSION:-0.33.0}"
DEVCONTAINER_DOCKER_COMPOSE_CHANNEL="${DEVCONTAINER_DOCKER_COMPOSE_CHANNEL:-v2}"
DEVCONTAINER_NODE_FEATURE_REF="${DEVCONTAINER_NODE_FEATURE_REF:-ghcr.io/devcontainers/features/node:1.7.1}"
DEVCONTAINER_NODE_VERSION="${DEVCONTAINER_NODE_VERSION:-24.15.0}"
DEVCONTAINER_NODE_PNPM_VERSION="${DEVCONTAINER_NODE_PNPM_VERSION:-none}"
DEVCONTAINER_NODE_NVM_VERSION="${DEVCONTAINER_NODE_NVM_VERSION:-0.40.4}"

ARKADE_VERSION="${ARKADE_VERSION:-0.11.116}"
BUN_VERSION="${BUN_VERSION:-bun-v1.3.14}"
KYVERNO_VERSION="${KYVERNO_VERSION:-v1.18.2}"
LEFTHOOK_VERSION="${LEFTHOOK_VERSION:-v2.1.10}"
# The linter itself was the only lint tool here with no pinned version, in any
# environment: brew on macOS, apt in the devcontainer, and whatever
# ubuntu-latest happened to ship in CI. That is how PR #201 passed locally on
# 0.11.0 and failed CI on 0.9.0 with 449 SC2317 findings -- a check 0.9.0 emits
# and later versions do not.
#
# Note the wording above: a comment starting with the word "shellcheck" right
# after the hash is parsed as a DIRECTIVE, not prose, and fails with SC1073.
# This comment said exactly that and broke the file it documents.
SHELLCHECK_VERSION="${SHELLCHECK_VERSION:-v0.11.0}"
LIMA_VERSION="${LIMA_VERSION:-v2.2.0}"
MKCERT_VERSION="${MKCERT_VERSION:-v1.4.4}"
OPENTOFU_VERSION="${OPENTOFU_VERSION:-1.12.5}"
# Pinned because CI installs it from the GitHub release rather than apt:
# ripgrep is the one tool ten gated Bats files need that the ubuntu-latest
# image does not ship, and reaching for apt to get it made every CI run pay
# for apt-get update -- over six minutes when the Azure mirror stalls.
# Tags are bare, with no leading v.
RIPGREP_VERSION="${RIPGREP_VERSION:-15.2.0}"
STARSHIP_VERSION="${STARSHIP_VERSION:-v1.26.0}"
STEP_VERSION="${STEP_VERSION:-v0.30.6}"
VIM_SENSIBLE_REF="${VIM_SENSIBLE_REF:-0ce2d843d6f588bb0c8c7eec6449171615dc56d9}"

# Host lint/format toolchain. These are resolved per platform by
# scripts/install-tool-hints.sh (mise/brew/pacman/...), not by this
# devcontainer's arkade sweep, so they need explicit pins to land the whole
# support matrix (macOS, Ubuntu, Arch, and the cloud VM host) on the same
# cooldown-cleared version rather than "@latest". ruff and deno resolve their
# newest cooldown-eligible release through the github source in
# toolchain-sources.tsv; biome and markdownlint-cli2 are audit-only there
# because biome tags carry an "@biomejs/biome@" prefix and markdownlint-cli2
# ships on npm, neither of which the github release resolver understands.
RUFF_VERSION="${RUFF_VERSION:-0.16.2}"
DENO_VERSION="${DENO_VERSION:-v2.9.5}"
BIOME_VERSION="${BIOME_VERSION:-2.5.8}"
MARKDOWNLINT_CLI2_VERSION="${MARKDOWNLINT_CLI2_VERSION:-0.23.2}"

# shellcheck disable=SC2034 # sourced by install/check scripts that consume the version matrix
DEVCONTAINER_ARKADE_TOOLS=(
  "cilium=v0.19.7"
  "helm=v4.2.3"
  "hubble=v1.19.4"
  "jq=jq-1.8.2"
  "k3sup=0.13.12"
  "kind=v0.32.0"
  "kubectl=v1.36.3"
  "kubie=v0.28.0"
  "kubectx=v0.11.0"
  "terragrunt=v1.1.2"
  "yq=v4.53.3"
)
