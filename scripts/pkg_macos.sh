#!/usr/bin/env bash
set -euo pipefail

FAILED_STEPS=()

record_failure() {
  local name="$1"
  local status="${2:-1}"
  FAILED_STEPS+=("${name} (exit ${status})")
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
  if [ "${#FAILED_STEPS[@]}" -eq 0 ]; then
    return 0
  fi

  echo
  echo "Setup completed with failed steps:"
  printf '  - %s\n' "${FAILED_STEPS[@]}"
  if [ "${SETUP_STRICT:-0}" = "1" ]; then
    return 1
  fi
  return 0
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

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to install Homebrew."
    exit 1
  fi
  if [ ! -x /bin/bash ]; then
    echo "/bin/bash is required to install Homebrew."
    exit 1
  fi

  echo "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

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
  local pkg status
  [ -f "${list_file}" ] || return 0

  while IFS= read -r pkg; do
    case "${pkg}" in
      ""|\#*) continue ;;
    esac
    if brew list --versions "${pkg}" >/dev/null 2>&1; then
      echo "brew upgrade ${pkg}"
      if brew upgrade "${pkg}"; then
        :
      else
        status="$?"
        record_failure "brew upgrade ${pkg}" "${status}"
      fi
      continue
    fi
    echo "brew install ${pkg}"
    if brew install "${pkg}"; then
      :
    else
      status="$?"
      record_failure "brew install ${pkg}" "${status}"
    fi
  done < "${list_file}"
}

install_rustup() {
  if [ -d "${HOME}/.rustup" ]; then
    rustup update stable
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

install_ai_clis() {
  if [ "${INSTALL_AI_CLI:-1}" != "1" ]; then
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    echo "npm unavailable; installing node via Homebrew..."
    brew install node
  fi

  if command -v npm >/dev/null 2>&1; then
    echo "npm install -g @openai/codex@latest @anthropic-ai/claude-code@latest"
    npm install -g @openai/codex@latest @anthropic-ai/claude-code@latest \
      || return 1
  else
    echo "warn: npm not available; skipping codex/claude-code install."
    return 1
  fi
}

install_packages() {
  ensure_homebrew

  echo "Updating Homebrew..."
  if brew update; then
    :
  else
    record_failure "brew update" "$?"
  fi

  # Prefer Brewfile if present for full environment parity.
  if [ -f "${DOTFILES_DIR}/Brewfile" ]; then
    echo "Applying Brewfile..."
    if brew bundle --file "${DOTFILES_DIR}/Brewfile"; then
      :
    else
      record_failure "brew bundle" "$?"
    fi
  fi

  run_step "install common Homebrew packages" install_from_list "${DOTFILES_DIR}/packages/common.txt"
  run_step "install macOS Homebrew packages" install_from_list "${DOTFILES_DIR}/packages/macos.txt"

  run_step "install Codex/Claude Code CLI" install_ai_clis
  run_step "install rustup" install_rustup
  run_step "install cargo tools" install_cargo_tools
  run_step "install Rust projects" install_rust_projects

  if [ "${INSTALL_TAILSCALE:-0}" = "1" ]; then
    run_step "install Tailscale" install_tailscale_macos
  fi

  print_failed_steps
}

install_tailscale_macos() {
  if command -v tailscale >/dev/null 2>&1; then
    echo "tailscale already installed."
    return
  fi
  echo "Installing tailscale via Homebrew..."
  brew install tailscale
}
