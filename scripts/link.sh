#!/usr/bin/env bash
set -euo pipefail

next_backup_path() {
  local dest="$1"
  local base="${dest}.backup.$(date +%Y%m%d%H%M%S)"
  local candidate="${base}"
  local index=1

  while [ -e "${candidate}" ] || [ -L "${candidate}" ]; do
    candidate="${base}.${index}"
    index=$((index + 1))
  done

  printf '%s\n' "${candidate}"
}

link_file() {
  local src="$1"
  local dest="$2"
  local backup

  mkdir -p "$(dirname "${dest}")"

  if [ -L "${dest}" ]; then
    if [ "$(readlink "${dest}")" = "${src}" ]; then
      echo "link ${dest} -> ${src}"
      return
    fi
    backup="$(next_backup_path "${dest}")"
    mv "${dest}" "${backup}"
    echo "backup ${dest} -> ${backup}"
  elif [ -e "${dest}" ]; then
    backup="$(next_backup_path "${dest}")"
    mv "${dest}" "${backup}"
    echo "backup ${dest} -> ${backup}"
  fi

  ln -s "${src}" "${dest}"
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
