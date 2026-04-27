#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
toolchain_versions_file="${workspace_root}/.devcontainer/toolchain-versions.sh"
starship_source="${workspace_root}/.devcontainer/starship.toml"
starship_target="${HOME}/.config/starship.toml"
managed_bashrc_source="${workspace_root}/.devcontainer/bashrc"
managed_zshrc_source="${workspace_root}/.devcontainer/zshrc"
platform_config_dir="${HOME}/.config/platform-devcontainer"
managed_bashrc_target="${platform_config_dir}/bashrc"
managed_zshrc_target="${platform_config_dir}/zshrc"
bashrc_path="${HOME}/.bashrc"
zshrc_path="${HOME}/.zshrc"
completion_root="${HOME}/.local/share/platform-devcontainer/completions"
normalize_node_toolchain_script="${workspace_root}/.devcontainer/normalize-node-toolchain.sh"
vim_sensible_repo_url="https://github.com/tpope/vim-sensible.git"
if [[ -f "${toolchain_versions_file}" ]]; then
  # shellcheck source=/dev/null
  source "${toolchain_versions_file}"
fi
vim_sensible_ref="${VIM_SENSIBLE_REF:-0ce2d843d6f588bb0c8c7eec6449171615dc56d9}"
vim_sensible_source_dir="${VIM_SENSIBLE_SOURCE_DIR:-/usr/local/share/platform-devcontainer/vendor/vim-sensible}"
vim_sensible_checkout_dir="${HOME}/.local/share/platform-devcontainer/vendor/vim-sensible"

ensure_source_line() {
  local shell_rc="$1"
  local source_line="$2"

  touch "${shell_rc}"
  if ! grep -Fqx "${source_line}" "${shell_rc}"; then
    printf '\n%s\n' "${source_line}" >>"${shell_rc}"
  fi
}

remove_exact_line() {
  local shell_rc="$1"
  local line="$2"
  local tmp_file=""

  [[ -f "${shell_rc}" ]] || return 0
  if ! grep -Fqx "${line}" "${shell_rc}"; then
    return 0
  fi

  tmp_file="$(mktemp)"
  grep -Fvx "${line}" "${shell_rc}" >"${tmp_file}" || true
  mv "${tmp_file}" "${shell_rc}"
}

write_completion() {
  local output_path="$1"
  shift

  if "$@" >"${output_path}"; then
    chmod 0644 "${output_path}"
  else
    rm -f "${output_path}"
    return 1
  fi
}

generate_completions() {
  local bash_dir="${completion_root}/bash"
  local zsh_dir="${completion_root}/zsh"

  mkdir -p "${bash_dir}" "${zsh_dir}"
  rm -f "${bash_dir}"/*.bash "${zsh_dir}"/*.zsh

  if command -v kubectl >/dev/null 2>&1; then
    write_completion "${bash_dir}/kubectl.bash" kubectl completion bash
    write_completion "${zsh_dir}/kubectl.zsh" kubectl completion zsh
  fi

  if command -v kubie >/dev/null 2>&1; then
    write_completion "${bash_dir}/kubie.bash" kubie generate-completion bash
    write_completion "${zsh_dir}/kubie.zsh" kubie generate-completion zsh
  fi

  if command -v kind >/dev/null 2>&1; then
    write_completion "${bash_dir}/kind.bash" kind completion bash
    write_completion "${zsh_dir}/kind.zsh" kind completion zsh
  fi

  if command -v helm >/dev/null 2>&1; then
    write_completion "${bash_dir}/helm.bash" helm completion bash
    write_completion "${zsh_dir}/helm.zsh" helm completion zsh
  fi

  if command -v cilium >/dev/null 2>&1; then
    write_completion "${bash_dir}/cilium.bash" cilium completion bash
    write_completion "${zsh_dir}/cilium.zsh" cilium completion zsh
  fi

  if command -v hubble >/dev/null 2>&1; then
    write_completion "${bash_dir}/hubble.bash" hubble completion bash
    write_completion "${zsh_dir}/hubble.zsh" hubble completion zsh
  fi
}

install_vim_sensible() {
  local current_ref=""
  local source_dir="${vim_sensible_source_dir}"
  local vim_pack_dir="${HOME}/.vim/pack/tpope/start"
  local nvim_pack_dir="${HOME}/.local/share/nvim/site/pack/tpope/start"

  if [[ ! -d "${source_dir}" ]]; then
    mkdir -p "$(dirname "${vim_sensible_checkout_dir}")"

    if [[ ! -d "${vim_sensible_checkout_dir}/.git" ]]; then
      rm -rf "${vim_sensible_checkout_dir}"
      git clone "${vim_sensible_repo_url}" "${vim_sensible_checkout_dir}"
    fi

    current_ref="$(git -C "${vim_sensible_checkout_dir}" rev-parse HEAD 2>/dev/null || true)"
    if [[ "${current_ref}" != "${vim_sensible_ref}" ]]; then
      git -C "${vim_sensible_checkout_dir}" fetch --depth 1 origin "${vim_sensible_ref}"
      git -C "${vim_sensible_checkout_dir}" checkout --detach "${vim_sensible_ref}"
    fi

    source_dir="${vim_sensible_checkout_dir}"
  fi

  mkdir -p "${vim_pack_dir}" "${nvim_pack_dir}"
  ln -sfn "${source_dir}" "${vim_pack_dir}/sensible"
  ln -sfn "${source_dir}" "${nvim_pack_dir}/sensible"
}

git config --global --add safe.directory "${workspace_root}"
mkdir -p "${HOME}/.config" "${HOME}/.kube" "${platform_config_dir}"

install -m 0644 "${starship_source}" "${starship_target}"
install -m 0644 "${managed_bashrc_source}" "${managed_bashrc_target}"
install -m 0644 "${managed_zshrc_source}" "${managed_zshrc_target}"
touch "${bashrc_path}" "${zshrc_path}"

remove_exact_line "${bashrc_path}" "eval \"\$(starship init bash)\""
remove_exact_line "${zshrc_path}" "eval \"\$(starship init zsh)\""
ensure_source_line "${bashrc_path}" "[ -f \"\${HOME}/.config/platform-devcontainer/bashrc\" ] && . \"\${HOME}/.config/platform-devcontainer/bashrc\""
ensure_source_line "${zshrc_path}" "[ -f \"\${HOME}/.config/platform-devcontainer/zshrc\" ] && . \"\${HOME}/.config/platform-devcontainer/zshrc\""

generate_completions
if [[ -x "${normalize_node_toolchain_script}" ]]; then
  "${normalize_node_toolchain_script}" --execute
fi
install_vim_sensible
