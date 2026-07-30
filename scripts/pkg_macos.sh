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
    Linux)
      target="${arch}-unknown-linux-gnu"
      set -- tgz tar.gz
      ;;
    Darwin)
      target="${arch}-apple-darwin"
      set -- zip full.zip
      ;;
    *) echo "warn: unsupported OS for cargo-binstall: ${os}"; return ;;
  esac

  tmp="$(mktemp -d /tmp/cargo-binstall.XXXXXX)"
  for ext in "$@"; do
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

  case "${ext}" in
    tgz|tar.gz)
      tar -xzf "${tmp}/cargo-binstall.${ext}" -C "${tmp}" || {
        echo "warn: failed to extract cargo-binstall."
        rm -rf "${tmp}"
        return
      }
      ;;
    zip|full.zip)
      unzip -q "${tmp}/cargo-binstall.${ext}" -d "${tmp}" || {
        echo "warn: failed to extract cargo-binstall."
        rm -rf "${tmp}"
        return
      }
      ;;
  esac

  if [ ! -x "${tmp}/cargo-binstall" ]; then
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

  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return
  fi
  if [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
    return
  fi

  if [ "${DOTFILES_ROLE:-primary}" = "secondary" ]; then
    echo "DOTFILES_ROLE=secondary requires an existing Homebrew installation."
    return 1
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

ensure_homebrew_bundle_trust() {
  if ! brew trust --help >/dev/null 2>&1; then
    return 0
  fi

  local formula cask
  for formula in \
    cloudflare/cloudflare/cf-terraforming \
    xcodesorg/made/xcodes
  do
    brew trust --formula "${formula}" || return 1
  done

  for cask in \
    beutton/brew/wattsec \
    nikitabobko/tap/aerospace
  do
    brew trust --cask "${cask}" || return 1
  done
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
  ensure_cargo_path
  if command -v rustup >/dev/null 2>&1; then
    rustup update stable
    return
  fi

  if command -v rustup-init >/dev/null 2>&1; then
    rustup-init -y --no-modify-path --default-toolchain stable
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --default-toolchain stable
  fi
  ensure_cargo_path
}

install_cargo_tools() {
  local list_file="${DOTFILES_DIR}/cargo-tools.txt"
  [ -f "${list_file}" ] || return 0
  ensure_cargo_path
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
    if [ "${DOTFILES_ROLE:-primary}" = "secondary" ]; then
      echo "warn: npm is unavailable; the secondary role will not install node via Homebrew."
      return 1
    fi
    echo "npm unavailable; installing node via Homebrew..."
    brew install node
  fi

  if command -v npm >/dev/null 2>&1; then
    ensure_npm_global_prefix || return 1
    echo "npm install -g @openai/codex@latest @anthropic-ai/claude-code@latest"
    npm install -g @openai/codex@latest @anthropic-ai/claude-code@latest \
      || return 1
  else
    echo "warn: npm not available; skipping codex/claude-code install."
    return 1
  fi
}

install_vscode_extensions() {
  local extension extensions_dir status=0

  if ! command -v code >/dev/null 2>&1; then
    echo "warn: VS Code CLI is unavailable; skipping user extensions."
    return 1
  fi

  extensions_dir="${VSCODE_EXTENSIONS_DIR:-${HOME}/.vscode/extensions}"
  mkdir -p "${extensions_dir}"

  while IFS= read -r extension; do
    [ -n "${extension}" ] || continue
    echo "code --install-extension ${extension}"
    if ! code --extensions-dir "${extensions_dir}" --install-extension "${extension}"; then
      echo "warn: failed to install VS Code extension ${extension}."
      status=1
    fi
  done < <(sed -nE 's/^vscode "([^"]+)".*/\1/p' "${DOTFILES_DIR}/Brewfile")

  return "${status}"
}

font_casks_from_brewfile() {
  sed -nE 's/^cask "(font-[^"]+)".*/\1/p' "${DOTFILES_DIR}/Brewfile"
}

ensure_shared_homebrew_fonts() {
  local cask config shared_font_dir
  local casks=()
  local status=0 migrated=0

  if [ -z "${BREW_PREFIX:-}" ]; then
    echo "warn: Homebrew prefix is unavailable; cannot migrate shared fonts."
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "warn: jq is unavailable; cannot inspect Homebrew font metadata."
    return 1
  fi

  shared_font_dir="${DOTFILES_SHARED_FONT_DIR:-/Library/Fonts}"

  while IFS= read -r cask; do
    [ -n "${cask}" ] && casks+=("${cask}")
  done < <(font_casks_from_brewfile)

  if [ "${#casks[@]}" -eq 0 ]; then
    return 0
  fi

  for cask in "${casks[@]}"; do
    config="${BREW_PREFIX}/Caskroom/${cask}/.metadata/config.json"
    if [ -f "${config}" ] &&
       jq -e --arg fontdir "${shared_font_dir}" \
         '(.explicit.fontdir // .env.fontdir // .default.fontdir) == $fontdir' \
         "${config}" >/dev/null; then
      continue
    fi

    if ! brew list --cask "${cask}" >/dev/null 2>&1; then
      echo "warn: Homebrew font cask ${cask} is not installed; skipping migration."
      status=1
      continue
    fi

    echo "migrate ${cask} fonts to ${shared_font_dir}"
    if brew reinstall --cask --no-ask --fontdir="${shared_font_dir}" "${cask}"; then
      migrated=$((migrated + 1))
    else
      echo "warn: failed to migrate ${cask} fonts to ${shared_font_dir}."
      status=1
    fi
  done

  echo "Shared Homebrew font migration complete (${migrated} casks migrated)."
  return "${status}"
}

verify_shared_homebrew_fonts() {
  local cask font_file metadata shared_font_dir
  local casks=()
  local checked=0 missing=0

  if ! command -v jq >/dev/null 2>&1; then
    echo "warn: jq is unavailable; cannot verify shared fonts."
    return 1
  fi

  shared_font_dir="${DOTFILES_SHARED_FONT_DIR:-/Library/Fonts}"

  while IFS= read -r cask; do
    [ -n "${cask}" ] && casks+=("${cask}")
  done < <(font_casks_from_brewfile)

  if [ "${#casks[@]}" -eq 0 ]; then
    return 0
  fi

  if ! metadata="$(HOMEBREW_NO_AUTO_UPDATE=1 brew info --cask --json=v2 "${casks[@]}")"; then
    echo "warn: failed to inspect shared Homebrew font casks."
    return 1
  fi

  while IFS=$'\t' read -r cask font_file; do
    [ -n "${font_file}" ] || continue
    checked=$((checked + 1))
    if [ ! -f "${shared_font_dir}/${font_file}" ]; then
      echo "warn: shared font is missing for ${cask}: ${shared_font_dir}/${font_file}"
      missing=$((missing + 1))
    fi
  done < <(
    printf '%s\n' "${metadata}" |
      jq -r '
        .casks[] |
        .token as $cask |
        .artifacts[] |
        select(.font) |
        [$cask, (.font[0] | split("/") | last)] |
        @tsv
      '
  )

  if [ "${missing}" -ne 0 ]; then
    echo "warn: ${missing} of ${checked} shared fonts are unavailable."
    echo "Run ./install.sh once as the primary Homebrew owner to migrate them."
    return 1
  fi

  echo "Shared Homebrew fonts verified (${checked} files in ${shared_font_dir})."
}

configure_secondary_user_scope() {
  local home_real dotfiles_real

  if [ -z "${HOME:-}" ] || [ ! -d "${HOME}" ]; then
    echo "secondary setup requires an existing HOME directory." >&2
    return 1
  fi

  home_real="$(cd "${HOME}" && pwd -P)"
  dotfiles_real="$(cd "${DOTFILES_DIR}" && pwd -P)"
  if [ "${home_real}" = "/" ]; then
    echo "secondary setup refuses HOME=/." >&2
    return 1
  fi

  case "${dotfiles_real}" in
    "${home_real}"|"${home_real}"/*) ;;
    *)
      cat >&2 <<EOF
Secondary setup requires the dotfiles checkout to be inside this user's HOME.
Move or clone it below ${home_real}, then rerun ./install.sh.
Current checkout: ${dotfiles_real}
EOF
      return 1
      ;;
  esac

  HOME="${home_real}"
  DOTFILES_DIR="${dotfiles_real}"
  CARGO_HOME="${home_real}/.cargo"
  CARGO_INSTALL_ROOT="${CARGO_HOME}"
  CARGO_TARGET_DIR="${home_real}/.cache/cargo-target"
  RUSTUP_HOME="${home_real}/.rustup"
  RUST_PROJECTS_DIR="${home_real}/.local/src"
  NPM_CONFIG_PREFIX="${home_real}/.npm-global"
  NPM_CONFIG_CACHE="${home_real}/.npm"
  NPM_CONFIG_USERCONFIG="${home_real}/.npmrc"
  XDG_CACHE_HOME="${home_real}/.cache"
  XDG_CONFIG_HOME="${home_real}/.config"
  XDG_DATA_HOME="${home_real}/.local/share"
  XDG_STATE_HOME="${home_real}/.local/state"
  HOMEBREW_CACHE="${home_real}/Library/Caches/Homebrew"
  HOMEBREW_LOGS="${home_real}/Library/Logs/Homebrew"
  VSCODE_EXTENSIONS_DIR="${home_real}/.vscode/extensions"
  unset VSCODE_PORTABLE

  export \
    HOME DOTFILES_DIR \
    CARGO_HOME CARGO_INSTALL_ROOT CARGO_TARGET_DIR \
    RUSTUP_HOME RUST_PROJECTS_DIR \
    NPM_CONFIG_PREFIX NPM_CONFIG_CACHE NPM_CONFIG_USERCONFIG \
    XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME \
    HOMEBREW_CACHE HOMEBREW_LOGS VSCODE_EXTENSIONS_DIR
}

write_secondary_install_receipt() {
  local receipt_dir="${XDG_STATE_HOME}/dotfiles"
  local receipt="${receipt_dir}/secondary-install-paths"
  local tmp

  mkdir -p "${receipt_dir}"
  tmp="$(mktemp "${receipt}.XXXXXX")"
  {
    printf 'role=secondary\n'
    printf 'home=%q\n' "${HOME}"
    printf 'dotfiles=%q\n' "${DOTFILES_DIR}"
    printf 'npm_prefix=%q\n' "${NPM_CONFIG_PREFIX}"
    printf 'npm_cache=%q\n' "${NPM_CONFIG_CACHE}"
    printf 'npm_userconfig=%q\n' "${NPM_CONFIG_USERCONFIG}"
    printf 'cargo_home=%q\n' "${CARGO_HOME}"
    printf 'cargo_target=%q\n' "${CARGO_TARGET_DIR}"
    printf 'rustup_home=%q\n' "${RUSTUP_HOME}"
    printf 'rust_projects=%q\n' "${RUST_PROJECTS_DIR}"
    printf 'vscode_extensions=%q\n' "${VSCODE_EXTENSIONS_DIR}"
    printf 'xdg_cache=%q\n' "${XDG_CACHE_HOME}"
    printf 'xdg_config=%q\n' "${XDG_CONFIG_HOME}"
    printf 'xdg_data=%q\n' "${XDG_DATA_HOME}"
    printf 'xdg_state=%q\n' "${XDG_STATE_HOME}"
    printf 'homebrew_cache=%q\n' "${HOMEBREW_CACHE}"
    printf 'homebrew_logs=%q\n' "${HOMEBREW_LOGS}"
  } >"${tmp}"
  chmod 0600 "${tmp}"
  mv "${tmp}" "${receipt}"
  echo "Secondary install scope recorded in ${receipt}."
}

install_secondary_user_environment() {
  configure_secondary_user_scope
  write_secondary_install_receipt

  echo "Secondary role: reusing ${BREW_PREFIX} without modifying Homebrew."
  export HOMEBREW_NO_AUTO_UPDATE=1

  if [ "${INSTALL_AI_CLI:-1}" = "1" ]; then
    run_step "install user-scoped Codex/Claude Code CLI" install_ai_clis
  fi
  if [ "${INSTALL_RUST_TOOLS:-1}" = "1" ]; then
    run_step "install user-scoped rustup toolchain" install_rustup
    run_step "install user-scoped cargo tools" install_cargo_tools
  fi
  if [ "${INSTALL_RUST_PROJECTS:-1}" = "1" ]; then
    run_step "install user-scoped Rust projects" install_rust_projects
  fi
  if [ "${INSTALL_VSCODE_EXTENSIONS:-1}" = "1" ]; then
    run_step "install user-scoped VS Code extensions" install_vscode_extensions
  fi
  if [ "${INSTALL_FONTS:-1}" = "1" ]; then
    run_step "verify shared Homebrew fonts" verify_shared_homebrew_fonts
  fi

  print_failed_steps
}

install_packages() {
  ensure_homebrew
  if ! command -v ensure_brew_prefix >/dev/null 2>&1; then
    source "${DOTFILES_DIR}/shell/path_helpers.sh"
  fi
  ensure_brew_prefix

  if [ "${DOTFILES_ROLE:-primary}" = "secondary" ]; then
    install_secondary_user_environment
    return
  fi

  echo "Updating Homebrew..."
  if brew update; then
    :
  else
    record_failure "brew update" "$?"
  fi

  # Prefer Brewfile if present for full environment parity.
  if [ -f "${DOTFILES_DIR}/Brewfile" ]; then
    echo "Trusting Brewfile third-party entries..."
    if ensure_homebrew_bundle_trust; then
      :
    else
      record_failure "brew trust Brewfile entries" "$?"
    fi

    echo "Applying Brewfile..."
    if brew bundle --file "${DOTFILES_DIR}/Brewfile"; then
      :
    else
      record_failure "brew bundle" "$?"
    fi

    if [ "${INSTALL_FONTS:-1}" = "1" ]; then
      run_step "migrate Homebrew fonts to shared directory" ensure_shared_homebrew_fonts
    fi
  fi

  run_step "install common Homebrew packages" install_from_list "${DOTFILES_DIR}/packages/common.txt"
  run_step "install macOS Homebrew packages" install_from_list "${DOTFILES_DIR}/packages/macos.txt"

  run_step "install Codex/Claude Code CLI" install_ai_clis
  if [ "${INSTALL_RUST_TOOLS:-1}" = "1" ]; then
    run_step "install rustup" install_rustup
    run_step "install cargo tools" install_cargo_tools
  fi
  if [ "${INSTALL_RUST_PROJECTS:-1}" = "1" ]; then
    run_step "install Rust projects" install_rust_projects
  fi

  if [ "${INSTALL_TAILSCALE:-0}" = "1" ]; then
    run_step "install Tailscale" install_tailscale_macos
  fi

  print_failed_steps
}

print_platform_post_install_notes() {
  if [ "${DOTFILES_ROLE:-primary}" != "secondary" ]; then
    return
  fi

  cat <<'EOF'
Secondary user follow-up:
  - Run `gh auth login` and `gh auth setup-git` for this macOS user.
  - The shared Git config enables commit.gpgsign. Provision this user's GPG
    secret key, or override commit.gpgsign in ~/.gitconfig.local.
EOF
}

install_tailscale_macos() {
  if command -v tailscale >/dev/null 2>&1; then
    echo "tailscale already installed."
    return
  fi
  echo "Installing tailscale via Homebrew..."
  brew install tailscale
}
