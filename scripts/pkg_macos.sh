#!/usr/bin/env bash
set -euo pipefail

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "Homebrew installation failed."
    exit 1
  fi
}

install_from_list() {
  local list_file="$1"
  [ -f "${list_file}" ] || return 0

  while IFS= read -r pkg; do
    case "${pkg}" in
      ""|\#*) continue ;;
    esac
    if brew list --versions "${pkg}" >/dev/null 2>&1; then
      continue
    fi
    echo "brew install ${pkg}"
    brew install "${pkg}"
  done < "${list_file}"
}

install_rustup() {
  if [ -d "${HOME}/.rustup" ]; then
    return
  fi

  if command -v rustup-init >/dev/null 2>&1; then
    rustup-init -y --no-modify-path --default-toolchain stable
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --default-toolchain stable
  fi
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
  ensure_homebrew

  echo "Updating Homebrew..."
  brew update

  # Prefer Brewfile if present for full environment parity.
  if [ -f "${DOTFILES_DIR}/Brewfile" ]; then
    echo "Applying Brewfile..."
    brew bundle --file "${DOTFILES_DIR}/Brewfile"
  fi

  install_from_list "${DOTFILES_DIR}/packages/common.txt"
  install_from_list "${DOTFILES_DIR}/packages/macos.txt"

  install_rustup
  install_cargo_tools
  install_rust_projects

  if [ "${INSTALL_TAILSCALE:-0}" = "1" ]; then
    install_tailscale_macos
  fi
}

install_tailscale_macos() {
  if command -v tailscale >/dev/null 2>&1; then
    echo "tailscale already installed."
    return
  fi
  echo "Installing tailscale via Homebrew..."
  brew install tailscale
}
