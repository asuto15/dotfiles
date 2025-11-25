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

install_starship() {
  if command -v starship >/dev/null 2>&1; then
    return
  fi

  # Prefer apt if the package is available.
  if apt-cache show starship >/dev/null 2>&1; then
    install_pkg "starship"
    if command -v starship >/dev/null 2>&1; then
      return
    fi
  fi

  # Fallback to the official installer (non-interactive).
  local downloader=()
  if command -v curl >/dev/null 2>&1; then
    downloader=(curl -fsSL https://starship.rs/install.sh)
  elif command -v wget >/dev/null 2>&1; then
    downloader=(wget -qO- https://starship.rs/install.sh)
  else
    echo "warn: cannot install starship (curl/wget missing)."
    return
  fi

  mkdir -p "${HOME}/.local/bin"
  echo "installing starship via official installer..."
  if ! "${downloader[@]}" | sh -s -- -y -b "${HOME}/.local/bin"; then
    echo "warn: starship installer failed."
  fi
}

install_from_list() {
  local list_file="$1"
  [ -f "${list_file}" ] || return 0

  while IFS= read -r pkg; do
    case "${pkg}" in
      ""|\#*) continue ;;
      eza) install_eza ;;
      starship) install_starship ;;
      *) install_pkg "${pkg}" ;;
    esac
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
  install_rust_projects

  ensure_fd_linux
  # Ensure common aliases exist when Debian/Ubuntu package names differ.
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    mkdir -p "${HOME}/.local/bin"
    ln -sfn "$(command -v batcat)" "${HOME}/.local/bin/bat"
  fi

  if [ "${INSTALL_TAILSCALE:-0}" = "1" ]; then
    install_tailscale_linux
  fi
}

install_eza() {
  # Install via the official Debian/Ubuntu repo with a registered keyring.
  if dpkg -s eza >/dev/null 2>&1; then
    return
  fi

  local keyring="/etc/apt/keyrings/gierens.gpg"
  local list_file="/etc/apt/sources.list.d/gierens.list"

  if [ ! -f "${keyring}" ]; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
      | gpg --dearmor | sudo tee "${keyring}" >/dev/null
  fi

  if [ ! -f "${list_file}" ]; then
    echo "deb [signed-by=${keyring}] http://deb.gierens.de stable main" \
      | sudo tee "${list_file}" >/dev/null
  fi

  # Repo was just added; ensure apt update runs before install.
  APT_UPDATED=0
  install_pkg "eza"
}

ensure_fd_linux() {
  if command -v fd >/dev/null 2>&1; then
    return
  fi

  install_pkg "fd-find"

  # Provide fd alias for Debian/Ubuntu package name.
  if command -v fdfind >/dev/null 2>&1; then
    sudo mkdir -p /usr/local/bin
    sudo ln -sfn "$(command -v fdfind)" /usr/local/bin/fd
    return
  fi

  echo "warn: fd-find installation failed; fd not available."
}

install_tailscale_linux() {
  if command -v tailscale >/dev/null 2>&1; then
    echo "tailscale already installed."
    return
  fi

  # Add Tailscale apt repo if missing
  if [ ! -f /etc/apt/sources.list.d/tailscale.list ]; then
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.list | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
    APT_UPDATED=0  # force apt update after adding repo
  fi

  install_pkg tailscale
}
