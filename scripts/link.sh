#!/usr/bin/env bash
set -euo pipefail

link_file() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "${dest}")"
  ln -sfn "${src}" "${dest}"
  echo "link ${dest} -> ${src}"
}

link_dotfiles() {
  local links=(
    ".zshrc"
    ".aliases"
    ".zsh_profile"
    ".tmux.conf"
    ".gitconfig"
    ".bashrc"
    ".config/nvim"
    ".config/alacritty"
    ".config/starship"
  )

  for item in "${links[@]}"; do
    local src="${DOTFILES_DIR}/${item}"
    local dest="${HOME}/${item}"
    if [ -e "${src}" ] || [ -d "${src}" ]; then
      link_file "${src}" "${dest}"
    fi
  done
}
