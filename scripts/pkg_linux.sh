#!/usr/bin/env bash
set -euo pipefail

apt_update_once() {
  if [ -z "${APT_UPDATED:-}" ] || [ "${APT_UPDATED:-}" = "0" ]; then
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

prompt_yes_no() {
  local prompt default answer
  prompt="$1"
  default="$2" # y or n

  if [ ! -t 0 ]; then
    [ "${default}" = "y" ] && return 0 || return 1
  fi

  local hint="[y/n]"
  [ "${default}" = "y" ] && hint="[Y/n]"
  [ "${default}" = "n" ] && hint="[y/N]"

  while :; do
    read -rp "${prompt} ${hint} " answer
    answer="${answer:-${default}}"
    case "${answer}" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

select_linux_profile() {
  # Allow non-interactive override
  case "${LINUX_PROFILE:-}" in
    client|server|none) return ;;
  esac

  # Default to client when not attached to a TTY
  if [ ! -t 0 ]; then
    LINUX_PROFILE="client"
    return
  fi

  echo "Select Linux profile:"
  echo "  1) client (desktop/tools)"
  echo "  2) server (minimal)"
  echo "  3) none   (base only)"
  while :; do
    read -rp "Enter choice [1-3, default=1]: " choice
    case "${choice:-1}" in
      1) LINUX_PROFILE="client"; break ;;
      2) LINUX_PROFILE="server"; break ;;
      3) LINUX_PROFILE="none"; break ;;
      *) echo "Invalid choice: ${choice}" ;;
    esac
  done
  echo "Profile: ${LINUX_PROFILE}"
}

select_optional_tools() {
  # Defaults per profile
  local default_node_stack="n"
  local default_uv="n"
  local default_vscode="n"
  local default_alacritty="n"
  local default_cursor="n"

  case "${LINUX_PROFILE:-client}" in
    client)
      default_node_stack="y"
      default_uv="y"
      default_vscode="y"
      default_alacritty="y"
      default_cursor="n"
      ;;
    server)
      default_node_stack="n"
      default_uv="n"
      default_vscode="n"
      default_alacritty="n"
      default_cursor="n"
      ;;
    none)
      default_node_stack="n"
      default_uv="n"
      default_vscode="n"
      default_alacritty="n"
      default_cursor="n"
      ;;
  esac

  # Environment overrides
  if [ -n "${INSTALL_NODE_STACK:-}" ]; then
    default_node_stack=$([ "${INSTALL_NODE_STACK}" = "1" ] && echo "y" || echo "n")
  fi
  if [ -n "${INSTALL_UV:-}" ]; then
    default_uv=$([ "${INSTALL_UV}" = "1" ] && echo "y" || echo "n")
  fi
  if [ -n "${INSTALL_VSCODE:-}" ]; then
    default_vscode=$([ "${INSTALL_VSCODE}" = "1" ] && echo "y" || echo "n")
  fi
  if [ -n "${INSTALL_ALACRITTY:-}" ]; then
    default_alacritty=$([ "${INSTALL_ALACRITTY}" = "1" ] && echo "y" || echo "n")
  fi
  if [ -n "${INSTALL_CURSOR:-}" ]; then
    default_cursor=$([ "${INSTALL_CURSOR}" = "1" ] && echo "y" || echo "n")
  fi

  INSTALL_NODE_STACK="0"
  INSTALL_UV="0"
  INSTALL_VSCODE="0"
  INSTALL_ALACRITTY="0"
  INSTALL_CURSOR="0"

  if prompt_yes_no "Install Node.js/npm/yarn/pnpm?" "${default_node_stack}"; then
    INSTALL_NODE_STACK="1"
  fi
  if prompt_yes_no "Install uv (Python package manager)?" "${default_uv}"; then
    INSTALL_UV="1"
  fi
  if prompt_yes_no "Install VSCode (official repository)?" "${default_vscode}"; then
    INSTALL_VSCODE="1"
  fi
  if prompt_yes_no "Install Alacritty (apt/cargo)?" "${default_alacritty}"; then
    INSTALL_ALACRITTY="1"
  fi
  if prompt_yes_no "Install Cursor (official repository)?" "${default_cursor}"; then
    INSTALL_CURSOR="1"
  fi
}

install_neovim() {
  if neovim_is_modern; then
    return
  fi

  if is_ubuntu; then
    ensure_neovim_ppa
    install_pkg "neovim"
    if neovim_is_modern; then
      return
    fi
  fi

  install_neovim_release_tarball
}

install_rustup() {
  if command -v rustup >/dev/null 2>&1; then
    return
  fi
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --default-toolchain stable
}

install_node_stack() {
  install_pkg "nodejs"
  install_pkg "npm"
  if command -v npm >/dev/null 2>&1; then
    echo "npm install -g yarn pnpm"
    npm install -g yarn pnpm || echo "warn: npm global install (yarn/pnpm) failed."
  else
    echo "warn: npm not available; skipping yarn/pnpm install."
  fi
}

install_uv() {
  if command -v uv >/dev/null 2>&1; then
    return
  fi
  local downloader=()
  if command -v curl >/dev/null 2>&1; then
    downloader=(curl -fsSL https://astral.sh/uv/install.sh)
  elif command -v wget >/dev/null 2>&1; then
    downloader=(wget -qO- https://astral.sh/uv/install.sh)
  else
    echo "warn: cannot install uv (curl/wget missing)."
    return
  fi
  echo "installing uv..."
  if ! "${downloader[@]}" | sh; then
    echo "warn: uv installer failed."
  fi
}

install_vscode_official() {
  if command -v code >/dev/null 2>&1; then
    return
  fi
  install_pkg "wget"
  install_pkg "gpg"
  local keyring="/usr/share/keyrings/microsoft.gpg"
  local list_file="/etc/apt/sources.list.d/vscode.list"
  if [ ! -f "${keyring}" ]; then
    echo "adding Microsoft GPG key..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o "${keyring}"
  fi
  if [ ! -f "${list_file}" ]; then
    echo "adding VSCode apt repo..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://packages.microsoft.com/repos/code stable main" \
      | sudo tee "${list_file}" >/dev/null
    APT_UPDATED=0
  fi
  install_pkg "apt-transport-https"
  install_pkg "code"
}

install_cursor_official() {
  if command -v cursor >/dev/null 2>&1; then
    return
  fi
  install_pkg "wget"
  install_pkg "gpg"
  local keyring="/etc/apt/keyrings/cursor-archive-keyring.gpg"
  local list_file="/etc/apt/sources.list.d/cursor.list"
  sudo mkdir -p /etc/apt/keyrings
  if [ ! -f "${keyring}" ]; then
    echo "adding Cursor GPG key..."
    wget -qO- https://dl.cursor.sh/apt/pubkey.gpg | sudo gpg --dearmor -o "${keyring}"
  fi
  if [ ! -f "${list_file}" ]; then
    echo "adding Cursor apt repo..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://dl.cursor.sh/apt stable main" \
      | sudo tee "${list_file}" >/dev/null
    APT_UPDATED=0
  fi
  install_pkg "cursor"
}

install_alacritty() {
  if command -v alacritty >/dev/null 2>&1; then
    return
  fi
  if apt-cache show alacritty >/dev/null 2>&1; then
    install_pkg "alacritty"
    return
  fi
  echo "warn: alacritty package not available via apt-cache; install manually if needed."
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
  select_linux_profile
  select_optional_tools
  case "${LINUX_PROFILE:-client}" in
    client) install_from_list "${DOTFILES_DIR}/packages/linux_client.txt" ;;
    server) install_from_list "${DOTFILES_DIR}/packages/linux_server.txt" ;;
    none) ;; # base only
    *) echo "warn: unknown LINUX_PROFILE=${LINUX_PROFILE}, skipping profile packages" ;;
  esac

  if [ "${INSTALL_NODE_STACK}" = "1" ]; then
    install_node_stack
  fi
  if [ "${INSTALL_UV}" = "1" ]; then
    install_uv
  fi
  if [ "${INSTALL_VSCODE}" = "1" ]; then
    install_vscode_official
  fi
  if [ "${INSTALL_ALACRITTY}" = "1" ]; then
    install_alacritty
  fi
  if [ "${INSTALL_CURSOR}" = "1" ]; then
    install_cursor_official
  fi

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

neovim_is_modern() {
  if ! command -v nvim >/dev/null 2>&1; then
    return 1
  fi
  local ver
  ver="$(nvim --version | head -n1 | awk '{print $2}' | sed 's/^v//')"
  if dpkg --compare-versions "${ver}" ge "0.11.0"; then
    return 0
  fi
  return 1
}

is_ubuntu() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    [ "${ID:-}" = "ubuntu" ] && return 0
  fi
  return 1
}

ensure_neovim_ppa() {
  if [ -f /etc/apt/sources.list.d/neovim-ppa-ubuntu-stable.list ]; then
    return
  fi

  install_pkg "software-properties-common"
  sudo add-apt-repository -y ppa:neovim-ppa/stable
  APT_UPDATED=0  # force apt update after adding repo
}

install_neovim_release_tarball() {
  local tmp_dir url tag
  tmp_dir="$(mktemp -d /tmp/nvim.XXXXXX)"

  # Resolve the latest tag to avoid redirect flakiness.
  tag="$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest 2>/dev/null \
    | awk -F '\"' '/tag_name/ {print $4; exit}')"
  if [ -n "${tag}" ]; then
    url="https://github.com/neovim/neovim/releases/download/${tag}/nvim-linux-x86_64.tar.gz"
  else
    url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
  fi

  echo "installing latest Neovim release from ${url}..."
  if ! curl -fL --retry 3 --retry-delay 1 -o "${tmp_dir}/nvim.tar.gz" "${url}"; then
    echo "warn: failed to download Neovim release tarball."
    rm -rf "${tmp_dir}"
    return
  fi

  # Extract to /usr/local and symlink nvim.
  sudo tar -C /usr/local -xzf "${tmp_dir}/nvim.tar.gz"
  sudo ln -sfn /usr/local/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim

  rm -rf "${tmp_dir}"
}

install_eza() {
  # Install via the official Debian/Ubuntu repo with a registered keyring.
  if dpkg -s eza >/dev/null 2>&1; then
    return
  fi

  local keyring="/etc/apt/keyrings/gierens.gpg"
  local list_file="/etc/apt/sources.list.d/gierens.list"
  local arch tmp_key
  arch="$(dpkg --print-architecture)"

  # Ensure prerequisites for fetching keys exist.
  install_pkg "ca-certificates"
  install_pkg "curl"
  install_pkg "gnupg"

  sudo install -m 0755 -d /etc/apt/keyrings
  tmp_key="$(mktemp)"
  if curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc -o "${tmp_key}"; then
    sudo gpg --dearmor -o "${keyring}" "${tmp_key}"
    sudo chmod a+r "${keyring}"
  else
    echo "warn: failed to download eza repo key."
  fi
  rm -f "${tmp_key}"

  echo "deb [arch=${arch} signed-by=${keyring}] http://deb.gierens.de stable main" \
    | sudo tee "${list_file}" >/dev/null

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
