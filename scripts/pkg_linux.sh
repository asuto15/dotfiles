#!/usr/bin/env bash
set -euo pipefail

apt_update_once() {
  if [ -z "${APT_UPDATED:-}" ]; then
    echo "Updating apt repositories..."
    sudo apt-get update -qq
    APT_UPDATED=1
  fi
}

install_pkg() {
  local pkg="$1"
  if dpkg -s "${pkg}" >/dev/null 2>&1; then
    return
  fi
  apt_update_once
  echo "apt install ${pkg}"
  if ! sudo apt-get install -y -qq "${pkg}"; then
    echo "warn: failed to install ${pkg}, continuing..."
  fi
}

install_from_list() {
  local list_file="$1"
  [ -f "${list_file}" ] || return 0

  while IFS= read -r pkg; do
    case "${pkg}" in
      ""|\#*) continue ;;
    esac
    install_pkg "${pkg}"
  done < "${list_file}"
}

install_neovim() {
  if command -v nvim >/dev/null 2>&1; then
    return
  fi
  install_pkg "neovim"
}

install_rustup() {
  if command -v rustup >/dev/null 2>&1; then
    return
  fi
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --default-toolchain stable
}

install_cargo_tools() {
  local list_file="${DOTFILES_DIR}/cargo-tools.txt"
  [ -f "${list_file}" ] || return 0
  command -v cargo >/dev/null 2>&1 || return 0

  while IFS= read -r pkg; do
    case "${pkg}" in
      ""|\#*) continue ;;
    esac
    echo "cargo install ${pkg}"
    cargo install "${pkg}" || true
  done < "${list_file}"
}

install_packages() {
  install_from_list "${DOTFILES_DIR}/packages/common.txt"
  install_from_list "${DOTFILES_DIR}/packages/linux.txt"

  install_neovim
  install_rustup
  install_cargo_tools

  # Ensure common aliases exist when Debian/Ubuntu package names differ.
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    mkdir -p "${HOME}/.local/bin"
    ln -sfn "$(command -v batcat)" "${HOME}/.local/bin/bat"
  fi

  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    mkdir -p "${HOME}/.local/bin"
    ln -sfn "$(command -v fdfind)" "${HOME}/.local/bin/fd"
  fi
}
