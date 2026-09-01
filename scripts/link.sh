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

install_gitconfig_wrapper() {
  local shared="${DOTFILES_DIR}/.gitconfig"
  local dest="${HOME}/.gitconfig"
  local local_config="${HOME}/.gitconfig.local"
  local marker="# Managed by dotfiles install.sh; machine-specific settings stay in this file."
  local backup=""
  local tmp

  if [ -f "${dest}" ] && grep -Fqx "${marker}" "${dest}"; then
    echo "gitconfig wrapper ${dest} already installed"
    return
  fi

  if [ -e "${dest}" ] || [ -L "${dest}" ]; then
    backup="$(next_backup_path "${dest}")"
    mv "${dest}" "${backup}"
    echo "backup ${dest} -> ${backup}"

    # The old installer linked ~/.gitconfig directly to the shared file.
    # Including that backup would include the shared file twice.
    if [ -L "${backup}" ] && [ "$(readlink "${backup}")" = "${shared}" ]; then
      backup=""
    fi
  fi

  tmp="$(mktemp "${dest}.tmp.XXXXXX")"
  printf '%s\n' "${marker}" >"${tmp}"
  git config --file "${tmp}" --add include.path "${shared}"
  if [ -n "${backup}" ]; then
    git config --file "${tmp}" --add include.path "${backup}"
  fi
  git config --file "${tmp}" --add include.path "${local_config}"
  chmod 0600 "${tmp}"
  mv "${tmp}" "${dest}"
  echo "install gitconfig wrapper ${dest} (shared: ${shared})"
}

link_dotfiles() {
  local links=(
    ".zshrc"
    ".aliases"
    ".zsh_profile"
    ".tmux.conf"
    ".bashrc"
    ".config/nvim"
    ".config/alacritty"
    ".config/omniwm"
    ".config/starship"
    ".local/bin/rclone-r2-mount"
    "Library/LaunchAgents/dev.asuto153.rclone-r2-mount.plist"
  )

  for item in "${links[@]}"; do
    local src="${DOTFILES_DIR}/${item}"
    local dest="${HOME}/${item}"
    if [ -e "${src}" ] || [ -d "${src}" ]; then
      link_file "${src}" "${dest}"
    fi
  done

  install_gitconfig_wrapper
}
