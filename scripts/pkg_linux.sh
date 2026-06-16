#!/usr/bin/env bash
set -euo pipefail

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    ensure_sudo || return 1
    sudo -n "$@"
  else
    echo "warn: sudo is required to run $* as a non-root user."
    return 1
  fi
}

can_run_as_root() {
  [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1
}

ensure_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    return 1
  fi
  if sudo -n true 2>/dev/null; then
    return 0
  fi
  if { : </dev/tty >/dev/tty; } 2>/dev/null; then
    echo "sudo authentication is required." >/dev/tty
    if sudo -v </dev/tty >/dev/tty 2>&1; then
      return 0
    fi
    echo "warn: sudo authentication failed."
    return 1
  fi

  echo "warn: sudo authentication is required, but no TTY is available."
  return 1
}

FAILED_STEPS=()
SKIPPED_STEPS=()
APT_UPDATE_FAILED=0
APT_UPDATE_SKIP_NOTICE_SHOWN=0

record_failure() {
  local name="$1"
  local status="${2:-1}"
  FAILED_STEPS+=("${name} (exit ${status})")
}

record_skip() {
  local name="$1"
  local reason="$2"
  SKIPPED_STEPS+=("${name}: ${reason}")
}

run_step() {
  local name="$1"
  local status
  shift

  echo "==> ${name}"
  if "$@"; then
    return 0
  else
    status="$?"
  fi

  record_failure "${name}" "${status}"
  return 0
}

print_failed_steps() {
  if [ "${#FAILED_STEPS[@]}" -gt 0 ]; then
    echo
    echo "Setup completed with failed steps:"
    printf '  - %s\n' "${FAILED_STEPS[@]}"
  fi

  if [ "${#SKIPPED_STEPS[@]}" -gt 0 ]; then
    echo
    echo "Skipped steps:"
    printf '  - %s\n' "${SKIPPED_STEPS[@]}"
  fi

  if [ "${#FAILED_STEPS[@]}" -gt 0 ] && [ "${SETUP_STRICT:-0}" = "1" ]; then
    return 1
  fi
  return 0
}

run_apt_dependent_step() {
  local name="$1"
  shift

  if [ "${APT_UPDATE_FAILED}" = "1" ]; then
    record_skip "${name}" "apt update failed"
    return 0
  fi

  run_step "${name}" "$@"
}

ensure_apt_linux() {
  if ! can_run_as_root; then
    echo "warn: apt package setup requires root privileges or sudo."
    echo "warn: rerun as root, install sudo, or use a user with sudo privileges."
    record_failure "apt root privileges" 1
    return 1
  fi
  if ! ensure_sudo; then
    echo "warn: apt package setup requires sudo authentication."
    record_failure "sudo authentication" 1
    return 1
  fi

  if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
    return 0
  fi

  echo "warn: package setup currently supports Debian/Ubuntu-style apt systems only."
  echo "warn: skipping Linux package installation; dotfile links will still be created."
  record_skip "Linux package installation" "apt-get/dpkg not available"
  return 1
}

ubuntu_codename() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    printf '%s\n' "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  fi
}

url_exists() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsIL --retry 2 --retry-delay 1 "${url}" >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -q --spider "${url}" >/dev/null 2>&1
  else
    return 1
  fi
}

neovim_ppa_supports_current_ubuntu() {
  local codename
  codename="$(ubuntu_codename)"
  [ -n "${codename}" ] || return 1
  url_exists "https://ppa.launchpadcontent.net/neovim-ppa/stable/ubuntu/dists/${codename}/Release"
}

disable_apt_source() {
  local source_file="$1"
  local disabled="${source_file}.disabled"
  if [ ! -e "${source_file}" ]; then
    return 0
  fi
  if [ -e "${disabled}" ]; then
    disabled="${source_file}.disabled.$(date +%Y%m%d%H%M%S)"
  fi
  echo "Disabling unsupported apt source: ${source_file}"
  as_root mv "${source_file}" "${disabled}"
}

disable_unsupported_neovim_ppa() {
  local source_dir source_file
  if neovim_ppa_supports_current_ubuntu; then
    return 0
  fi

  source_dir="${APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
  for source_file in "${source_dir}"/*.list "${source_dir}"/*.sources; do
    [ -e "${source_file}" ] || continue
    grep -Eq 'ppa\.launchpadcontent\.net/neovim-ppa/stable|neovim-ppa' "${source_file}" || continue
    disable_apt_source "${source_file}" || true
  done
}

has_neovim_ppa_source() {
  local source_dir source_file
  source_dir="${APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
  for source_file in "${source_dir}"/*.list "${source_dir}"/*.sources; do
    [ -e "${source_file}" ] || continue
    if grep -Eq 'ppa\.launchpadcontent\.net/neovim-ppa/stable|neovim-ppa' "${source_file}"; then
      return 0
    fi
  done
  return 1
}

apt_update_once() {
  if [ "${APT_UPDATE_FAILED}" = "1" ]; then
    return 1
  fi

  if [ -z "${APT_UPDATED:-}" ] || [ "${APT_UPDATED:-}" = "0" ]; then
    disable_unsupported_neovim_ppa
    echo "Updating apt repositories..."
    if as_root apt-get update -qq; then
      APT_UPDATED=1
    else
      local status="$?"
      APT_UPDATE_FAILED=1
      APT_UPDATED=1
      record_failure "apt update" "${status}"
      echo "warn: apt update failed; skipping remaining apt package installs."
      return 1
    fi
  fi
}

install_pkg() {
  local pkg="$1"
  if ! apt_update_once; then
    if [ "${APT_UPDATE_SKIP_NOTICE_SHOWN}" = "0" ]; then
      echo "warn: apt package installs are skipped because apt update failed."
      APT_UPDATE_SKIP_NOTICE_SHOWN=1
    fi
    return 0
  fi
  echo "apt install/upgrade ${pkg}"
  if ! as_root apt-get install -y -qq "${pkg}"; then
    echo "warn: failed to install ${pkg}, continuing..."
    return 1
  fi
}

install_nodejs_from_nodesource() {
  if [ "${APT_UPDATE_FAILED}" = "1" ]; then
    return 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    install_pkg "curl" || return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "warn: curl is required to install Node.js from NodeSource."
    return 1
  fi
  if ! command -v bash >/dev/null 2>&1; then
    install_pkg "bash" || return 1
  fi
  if ! command -v bash >/dev/null 2>&1; then
    echo "warn: bash is required to install Node.js from NodeSource."
    return 1
  fi

  echo "installing Node.js LTS via NodeSource..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | as_root bash - || return 1
  APT_UPDATED=1
  install_pkg "nodejs" || return 1
}

ensure_node_npm() {
  if command -v npm >/dev/null 2>&1; then
    return 0
  fi

  if [ "${APT_UPDATE_FAILED}" = "1" ]; then
    return 1
  fi

  install_pkg "nodejs" || return 1
  install_pkg "npm" || return 1
  if [ "${APT_UPDATE_FAILED}" = "1" ]; then
    return 1
  fi
  if command -v npm >/dev/null 2>&1; then
    return 0
  fi

  echo "warn: npm is not available after apt nodejs/npm install; trying NodeSource LTS."
  install_nodejs_from_nodesource || return 1
  if command -v npm >/dev/null 2>&1; then
    return 0
  fi

  echo "warn: npm is still not available after NodeSource install."
  return 1
}

npm_global_install() {
  local npm_bin prefix
  npm_bin="$(command -v npm)" || return 1
  prefix="$(npm config get prefix 2>/dev/null || true)"

  case "${prefix}" in
    "${HOME}"/*) "${npm_bin}" install -g "$@" ;;
    *) as_root "${npm_bin}" install -g "$@" ;;
  esac
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
      eza) run_step "install eza" install_eza ;;
      starship) run_step "install starship" install_starship ;;
      *) run_step "install ${pkg}" install_pkg "${pkg}" ;;
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
  local default_ai_cli="y"
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
  if [ -n "${INSTALL_AI_CLI:-}" ]; then
    default_ai_cli=$([ "${INSTALL_AI_CLI}" = "1" ] && echo "y" || echo "n")
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
  INSTALL_AI_CLI="0"
  INSTALL_UV="0"
  INSTALL_VSCODE="0"
  INSTALL_ALACRITTY="0"
  INSTALL_CURSOR="0"

  if prompt_yes_no "Install Node.js/npm/yarn/pnpm?" "${default_node_stack}"; then
    INSTALL_NODE_STACK="1"
  fi
  if prompt_yes_no "Install Codex/Claude Code CLI?" "${default_ai_cli}"; then
    INSTALL_AI_CLI="1"
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
    if ensure_neovim_ppa; then
      install_pkg "neovim" || true
      if neovim_is_modern; then
        return
      fi
    else
      echo "warn: neovim PPA is unavailable for this Ubuntu release; using release tarball."
    fi
  fi

  install_neovim_release_tarball
}

install_rustup() {
  if command -v rustup >/dev/null 2>&1; then
    rustup update stable
    return
  fi
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --default-toolchain stable
}

ensure_rust_build_deps() {
  if command -v cc >/dev/null 2>&1; then
    return 0
  fi

  if [ "${APT_UPDATE_FAILED}" = "1" ]; then
    return 1
  fi

  install_pkg "build-essential" || return 1
  if command -v cc >/dev/null 2>&1; then
    return 0
  fi

  echo "warn: cc is still not available after installing build-essential."
  return 1
}

install_node_stack() {
  ensure_node_npm || return 1
  echo "npm install -g yarn@latest pnpm@latest"
  npm_global_install yarn@latest pnpm@latest || return 1
}

install_ai_clis() {
  ensure_node_npm || return 1
  echo "npm install -g @openai/codex@latest @anthropic-ai/claude-code@latest"
  npm_global_install @openai/codex@latest @anthropic-ai/claude-code@latest || return 1
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
  "${downloader[@]}" | sh
}

install_vscode_official() {
  if command -v code >/dev/null 2>&1; then
    return
  fi
  install_pkg "wget" || return 1
  install_pkg "gpg" || return 1
  local keyring="/usr/share/keyrings/microsoft.gpg"
  local list_file="/etc/apt/sources.list.d/vscode.list"
  if [ ! -f "${keyring}" ]; then
    echo "adding Microsoft GPG key..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | as_root gpg --dearmor -o "${keyring}" || return 1
  fi
  if [ ! -f "${list_file}" ]; then
    echo "adding VSCode apt repo..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://packages.microsoft.com/repos/code stable main" \
      | as_root tee "${list_file}" >/dev/null || return 1
    APT_UPDATED=0
  fi
  install_pkg "apt-transport-https" || return 1
  install_pkg "code"
}

install_cursor_official() {
  if command -v cursor >/dev/null 2>&1; then
    return
  fi
  install_pkg "wget" || return 1
  install_pkg "gpg" || return 1
  local keyring="/etc/apt/keyrings/cursor-archive-keyring.gpg"
  local list_file="/etc/apt/sources.list.d/cursor.list"
  as_root mkdir -p /etc/apt/keyrings || return 1
  if [ ! -f "${keyring}" ]; then
    echo "adding Cursor GPG key..."
    wget -qO- https://dl.cursor.sh/apt/pubkey.gpg | as_root gpg --dearmor -o "${keyring}" || return 1
  fi
  if [ ! -f "${list_file}" ]; then
    echo "adding Cursor apt repo..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://dl.cursor.sh/apt stable main" \
      | as_root tee "${list_file}" >/dev/null || return 1
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
  return 1
}

ensure_cargo_binstall() {
  if command -v cargo-binstall >/dev/null 2>&1; then
    return
  fi

  local arch os target tmp url ext downloaded=0
  arch="$(uname -m)"
  os="$(uname -s)"
  case "${arch}" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) echo "warn: unsupported arch for cargo-binstall: ${arch}"; return ;;
  esac
  case "${os}" in
    Linux) target="${arch}-unknown-linux-gnu" ;;
    Darwin) target="${arch}-apple-darwin" ;;
    *) echo "warn: unsupported OS for cargo-binstall: ${os}"; return ;;
  esac

  tmp="$(mktemp -d /tmp/cargo-binstall.XXXXXX)"
  for ext in tgz tar.gz; do
    url="https://github.com/cargo-bins/cargo-binstall/releases/latest/download/cargo-binstall-${target}.${ext}"
    echo "downloading cargo-binstall from ${url}..."
    if command -v curl >/dev/null 2>&1; then
      if curl -fL --retry 3 --retry-delay 1 -o "${tmp}/cargo-binstall.${ext}" "${url}"; then
        downloaded=1
        break
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -qO "${tmp}/cargo-binstall.${ext}" "${url}"; then
        downloaded=1
        break
      fi
    else
      echo "warn: cannot download cargo-binstall (curl/wget missing)."
      rm -rf "${tmp}"
      return
    fi
  done

  if [ "${downloaded}" != "1" ]; then
    echo "warn: failed to download cargo-binstall release."
    rm -rf "${tmp}"
    return
  fi

  if ! tar -xzf "${tmp}/cargo-binstall."* -C "${tmp}"; then
    echo "warn: failed to extract cargo-binstall."
    rm -rf "${tmp}"
    return
  fi

  mkdir -p "${HOME}/.cargo/bin"
  if install -m 0755 "${tmp}/cargo-binstall" "${HOME}/.cargo/bin/cargo-binstall"; then
    echo "cargo-binstall installed to ${HOME}/.cargo/bin"
  else
    echo "warn: failed to install cargo-binstall binary."
  fi
  rm -rf "${tmp}"
}

install_cargo_tools() {
  local list_file="${DOTFILES_DIR}/cargo-tools.txt"
  [ -f "${list_file}" ] || return 0
  command -v cargo >/dev/null 2>&1 || return 0

  ensure_cargo_binstall
  if ! command -v cargo-binstall >/dev/null 2>&1; then
    echo "warn: cargo-binstall unavailable; skipping cargo tools."
    return 0
  fi

  while IFS= read -r pkg; do
    case "${pkg}" in
      ""|\#*) continue ;;
    esac
    echo "cargo binstall -y --disable-strategies compile ${pkg}"
    if ! cargo binstall -y --disable-strategies compile "${pkg}"; then
      echo "warn: cargo-binstall failed for ${pkg} (skipping, no build fallback)."
    fi
  done < "${list_file}"
}

install_packages() {
  if ! ensure_apt_linux; then
    print_failed_steps
    return 0
  fi

  install_from_list "${DOTFILES_DIR}/packages/common.txt"
  install_from_list "${DOTFILES_DIR}/packages/linux.txt"
  run_step "select Linux profile" select_linux_profile
  run_step "select optional tools" select_optional_tools
  case "${LINUX_PROFILE:-client}" in
    client) install_from_list "${DOTFILES_DIR}/packages/linux_client.txt" ;;
    server) install_from_list "${DOTFILES_DIR}/packages/linux_server.txt" ;;
    none) ;; # base only
    *) echo "warn: unknown LINUX_PROFILE=${LINUX_PROFILE}, skipping profile packages" ;;
  esac

  if [ "${INSTALL_NODE_STACK}" = "1" ]; then
    run_apt_dependent_step "install Node.js/npm/yarn/pnpm" install_node_stack
  fi
  if [ "${INSTALL_AI_CLI}" = "1" ]; then
    run_apt_dependent_step "install Codex/Claude Code CLI" install_ai_clis
  fi
  if [ "${INSTALL_UV}" = "1" ]; then
    run_step "install uv" install_uv
  fi
  if [ "${INSTALL_VSCODE}" = "1" ]; then
    run_step "install VSCode" install_vscode_official
  fi
  if [ "${INSTALL_ALACRITTY}" = "1" ]; then
    run_step "install Alacritty" install_alacritty
  fi
  if [ "${INSTALL_CURSOR}" = "1" ]; then
    run_step "install Cursor" install_cursor_official
  fi

  run_step "install Neovim" install_neovim
  run_apt_dependent_step "install Rust build dependencies" ensure_rust_build_deps
  run_step "install rustup" install_rustup
  if command -v cc >/dev/null 2>&1; then
    run_step "install cargo tools" install_cargo_tools
    run_step "install Rust projects" install_rust_projects
  elif [ "${APT_UPDATE_FAILED}" = "1" ]; then
    record_skip "install cargo tools" "cc unavailable because apt update failed"
    record_skip "install Rust projects" "cc unavailable because apt update failed"
    echo "warn: skipping Rust CLI builds because cc is not available."
  else
    record_failure "install cargo tools" 1
    record_failure "install Rust projects" 1
    echo "warn: skipping Rust CLI builds because cc is not available."
  fi

  run_apt_dependent_step "ensure fd" ensure_fd_linux
  # Ensure common aliases exist when Debian/Ubuntu package names differ.
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    mkdir -p "${HOME}/.local/bin"
    ln -sfn "$(command -v batcat)" "${HOME}/.local/bin/bat"
  fi

  if [ "${INSTALL_TAILSCALE:-0}" = "1" ]; then
    run_step "install Tailscale" install_tailscale_linux
  fi

  print_failed_steps
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
  if ! neovim_ppa_supports_current_ubuntu; then
    disable_unsupported_neovim_ppa
    return 1
  fi

  if has_neovim_ppa_source; then
    return
  fi

  install_pkg "software-properties-common" || return 1
  as_root add-apt-repository -y ppa:neovim-ppa/stable || return 1
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
  as_root tar -C /usr/local -xzf "${tmp_dir}/nvim.tar.gz" || {
    rm -rf "${tmp_dir}"
    return 1
  }
  as_root ln -sfn /usr/local/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim || {
    rm -rf "${tmp_dir}"
    return 1
  }

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

  as_root install -m 0755 -d /etc/apt/keyrings
  tmp_key="$(mktemp)"
  if curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc -o "${tmp_key}"; then
    as_root gpg --dearmor -o "${keyring}" "${tmp_key}" || {
      rm -f "${tmp_key}"
      return 1
    }
    as_root chmod a+r "${keyring}" || {
      rm -f "${tmp_key}"
      return 1
    }
  else
    echo "warn: failed to download eza repo key."
    rm -f "${tmp_key}"
    return 1
  fi
  rm -f "${tmp_key}"

  echo "deb [arch=${arch} signed-by=${keyring}] http://deb.gierens.de stable main" \
    | as_root tee "${list_file}" >/dev/null || return 1

  # Repo was just added; ensure apt update runs before install.
  APT_UPDATED=0
  install_pkg "eza"
}

ensure_fd_linux() {
  if [ "${APT_UPDATE_FAILED}" = "1" ]; then
    return 1
  fi

  if command -v fd >/dev/null 2>&1; then
    return
  fi

  install_pkg "fd-find"

  # Provide fd alias for Debian/Ubuntu package name.
  if command -v fdfind >/dev/null 2>&1; then
    as_root mkdir -p /usr/local/bin || return 1
    as_root ln -sfn "$(command -v fdfind)" /usr/local/bin/fd || return 1
    return
  fi

  echo "warn: fd-find installation failed; fd not available."
  return 1
}

install_tailscale_linux() {
  if command -v tailscale >/dev/null 2>&1; then
    echo "tailscale already installed."
    return
  fi

  # Add Tailscale apt repo if missing
  if [ ! -f /etc/apt/sources.list.d/tailscale.list ]; then
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.gpg \
      | as_root tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null || return 1
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.list \
      | as_root tee /etc/apt/sources.list.d/tailscale.list >/dev/null || return 1
    APT_UPDATED=0  # force apt update after adding repo
  fi

  install_pkg tailscale
}
