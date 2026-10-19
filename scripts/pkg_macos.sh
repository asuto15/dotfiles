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

# A component is an intentionally small, independently selectable part of the
# macOS environment. `app-store` is internal: it is selected automatically
# whenever an App Store application group needs the `mas` command.
MACOS_PUBLIC_COMPONENTS=(
  core
  development
  infrastructure
  editors
  vscode
  vscode-extensions
  work
  personal
  desktop
  japanese
  fonts
  ai
  rust-tools
  rust-projects
  tailscale
)
MACOS_SELECTED_COMPONENTS=""
MACOS_SAVED_COMPONENTS=""
MACOS_STATE_LOADED=0

macos_component_is_valid() {
  case "$1" in
    core|development|infrastructure|editors|vscode|vscode-extensions|work|personal|desktop|japanese|fonts|ai|rust-tools|rust-projects|tailscale|app-store)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

macos_components_contain() {
  local components="$1"
  local component="$2"

  case " ${components} " in
    *" ${component} "*) return 0 ;;
    *) return 1 ;;
  esac
}

macos_component_selected() {
  macos_components_contain "${MACOS_SELECTED_COMPONENTS:-}" "$1"
}

add_macos_component() {
  local component="$1"

  if ! macos_component_is_valid "${component}"; then
    echo "warn: unknown macOS component: ${component}" >&2
    return 1
  fi
  if ! macos_component_selected "${component}"; then
    MACOS_SELECTED_COMPONENTS="${MACOS_SELECTED_COMPONENTS}${MACOS_SELECTED_COMPONENTS:+ }${component}"
  fi
}

remove_macos_component() {
  local component="$1"
  local selected=""
  local item

  for item in ${MACOS_SELECTED_COMPONENTS:-}; do
    [ "${item}" = "${component}" ] && continue
    selected="${selected}${selected:+ }${item}"
  done
  MACOS_SELECTED_COMPONENTS="${selected}"
}

macos_public_selected_components() {
  local component
  local selected=""

  for component in "${MACOS_PUBLIC_COMPONENTS[@]}"; do
    if macos_component_selected "${component}"; then
      selected="${selected}${selected:+ }${component}"
    fi
  done
  printf '%s\n' "${selected}"
}

parse_macos_components() {
  local requested="$1"
  local component
  local -a requested_components=()
  local IFS=','

  MACOS_SELECTED_COMPONENTS=""
  case "${requested}" in
    none)
      return 0
      ;;
    all)
      for component in "${MACOS_PUBLIC_COMPONENTS[@]}"; do
        add_macos_component "${component}"
      done
      return 0
      ;;
  esac

  read -r -a requested_components <<<"${requested}"
  if [ "${#requested_components[@]}" -eq 0 ]; then
    echo "DOTFILES_MACOS_COMPONENTS must name one or more components, all, or none." >&2
    return 1
  fi

  for component in "${requested_components[@]}"; do
    case "${component}" in
      ""|all|none)
        echo "DOTFILES_MACOS_COMPONENTS cannot mix ${component:-an empty value} with named components." >&2
        return 1
        ;;
    esac
    if macos_component_is_valid "${component}" && [ "${component}" != "app-store" ]; then
      add_macos_component "${component}"
    else
        echo "Unknown macOS component: ${component}" >&2
        echo "Available components: ${MACOS_PUBLIC_COMPONENTS[*]}, all, none" >&2
        return 1
    fi
  done
}

macos_install_state_file() {
  printf '%s\n' "${DOTFILES_MACOS_STATE_FILE:-${XDG_CONFIG_HOME:-${HOME}/.config}/dotfiles/macos-install.env}"
}

load_macos_install_state() {
  local file key value

  file="$(macos_install_state_file)"
  [ -f "${file}" ] || return 0

  while IFS='=' read -r key value; do
    [ "${key}" = "MACOS_COMPONENTS" ] || continue
    if parse_macos_components "${value}"; then
      MACOS_SAVED_COMPONENTS="${MACOS_SELECTED_COMPONENTS}"
      MACOS_SELECTED_COMPONENTS=""
      MACOS_STATE_LOADED=1
    else
      echo "warn: ignoring invalid macOS selection in ${file}." >&2
      MACOS_SELECTED_COMPONENTS=""
    fi
    return 0
  done < "${file}"
}

save_macos_install_state() {
  local file dir tmp selected

  file="$(macos_install_state_file)"
  dir="$(dirname "${file}")"
  selected="$(macos_public_selected_components)"
  if [ -n "${selected}" ]; then
    selected="${selected// /,}"
  else
    selected="none"
  fi

  mkdir -p "${dir}" || return 1
  tmp="$(mktemp "${dir}/macos-install.env.XXXXXX")" || return 1
  printf 'MACOS_COMPONENTS=%s\n' "${selected}" > "${tmp}" || {
    rm -f "${tmp}"
    return 1
  }
  chmod 0600 "${tmp}"
  mv "${tmp}" "${file}"
}

macos_selection_default() {
  local component="$1"

  if [ "${MACOS_STATE_LOADED}" = "1" ]; then
    if macos_components_contain "${MACOS_SAVED_COMPONENTS}" "${component}"; then
      printf '%s\n' y
    else
      printf '%s\n' n
    fi
    return
  fi

  if [ "${component}" = "core" ]; then
    printf '%s\n' y
  else
    printf '%s\n' n
  fi
}

prompt_macos_yes_no() {
  local prompt="$1"
  local default="$2"
  local answer hint

  [ "${default}" = "y" ] && hint="[Y/n]" || hint="[y/N]"
  while :; do
    if ! read -r -p "${prompt} ${hint} " answer; then
      return 1
    fi
    answer="${answer:-${default}}"
    case "${answer}" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

prompt_for_macos_components() {
  local component description default index
  local -a components=(
    core
    development
    infrastructure
    editors
    vscode
    vscode-extensions
    work
    personal
    desktop
    japanese
    fonts
    ai
    rust-tools
    rust-projects
    tailscale
  )
  local -a descriptions=(
    "core command-line tools"
    "language runtimes, compilers, and development tools"
    "containers, networking, server, and virtual-machine tools"
    "Alacritty, Neovim, and Zed"
    "Visual Studio Code"
    "the curated Visual Studio Code extensions"
    "work applications, credentials, cloud storage, and Office apps"
    "personal Mac App Store applications"
    "window management and desktop utilities"
    "Japanese input methods"
    "shared programming and Japanese fonts"
    "Ollama plus Codex and Claude Code CLIs"
    "the Rust toolchain and Cargo CLI tools"
    "personal Rust project checkouts and binaries"
    "Tailscale"
  )

  echo "Select macOS software components. Unselected components are not installed."
  for index in "${!components[@]}"; do
    component="${components[${index}]}"
    description="${descriptions[${index}]}"
    default="$(macos_selection_default "${component}")"
    if prompt_macos_yes_no "Install ${description}?" "${default}"; then
      add_macos_component "${component}"
    fi
  done
}

apply_macos_component_flag() {
  local variable_name="$1"
  local component="$2"
  local value="$3"

  case "${value}" in
    1) add_macos_component "${component}" ;;
    0) remove_macos_component "${component}" ;;
    *)
      echo "${variable_name} must be 0 or 1 (got: ${value})." >&2
      return 1
      ;;
  esac
}

apply_legacy_macos_component_flags() {
  if [ "${INSTALL_AI_CLI+x}" = x ]; then
    apply_macos_component_flag INSTALL_AI_CLI ai "${INSTALL_AI_CLI}"
  fi
  if [ "${INSTALL_RUST_TOOLS+x}" = x ]; then
    apply_macos_component_flag INSTALL_RUST_TOOLS rust-tools "${INSTALL_RUST_TOOLS}"
  fi
  if [ "${INSTALL_RUST_PROJECTS+x}" = x ]; then
    apply_macos_component_flag INSTALL_RUST_PROJECTS rust-projects "${INSTALL_RUST_PROJECTS}"
  fi
  if [ "${INSTALL_VSCODE_EXTENSIONS+x}" = x ]; then
    apply_macos_component_flag INSTALL_VSCODE_EXTENSIONS vscode-extensions "${INSTALL_VSCODE_EXTENSIONS}"
  fi
  if [ "${INSTALL_FONTS+x}" = x ]; then
    apply_macos_component_flag INSTALL_FONTS fonts "${INSTALL_FONTS}"
  fi
  if [ "${INSTALL_TAILSCALE+x}" = x ]; then
    apply_macos_component_flag INSTALL_TAILSCALE tailscale "${INSTALL_TAILSCALE}"
  fi
}

resolve_macos_component_dependencies() {
  if macos_component_selected vscode-extensions; then
    add_macos_component vscode
  fi
  if macos_component_selected rust-projects; then
    add_macos_component rust-tools
  fi
  if macos_component_selected work || macos_component_selected personal; then
    add_macos_component app-store
  fi
}

select_macos_components() {
  local interaction="${DOTFILES_MACOS_INTERACTIVE:-auto}"

  # Minimal is an explicit ceiling, including saved choices and legacy flags.
  if [ "${DOTFILES_MINIMAL:-0}" = "1" ]; then
    MACOS_SELECTED_COMPONENTS=""
    MACOS_SAVED_COMPONENTS=""
    MACOS_STATE_LOADED=0
    if ! save_macos_install_state; then
      echo "warn: failed to save the macOS component selection." >&2
    fi
    echo "Minimal setup: only dotfiles will be linked; no software will be installed."
    return 0
  fi

  case "${interaction}" in
    auto|0|1) ;;
    *)
      echo "DOTFILES_MACOS_INTERACTIVE must be auto, 0, or 1 (got: ${interaction})." >&2
      return 1
      ;;
  esac
  if [ "${interaction}" = "1" ] && [ ! -t 0 ]; then
    echo "DOTFILES_MACOS_INTERACTIVE=1 requires a TTY." >&2
    return 1
  fi

  MACOS_SELECTED_COMPONENTS=""
  MACOS_SAVED_COMPONENTS=""
  MACOS_STATE_LOADED=0
  if [ -n "${DOTFILES_MACOS_COMPONENTS:-}" ]; then
    parse_macos_components "${DOTFILES_MACOS_COMPONENTS}" || return 1
  else
    load_macos_install_state || return 1
    if [ "${interaction}" != "0" ] && [ -t 0 ]; then
      prompt_for_macos_components || return 1
    elif [ "${MACOS_STATE_LOADED}" = "1" ]; then
      MACOS_SELECTED_COMPONENTS="${MACOS_SAVED_COMPONENTS}"
    fi
  fi

  apply_legacy_macos_component_flags || return 1
  resolve_macos_component_dependencies || return 1

  if ! save_macos_install_state; then
    echo "warn: failed to save the macOS component selection." >&2
  fi

  local selected
  selected="$(macos_public_selected_components)"
  if [ -n "${selected}" ]; then
    echo "Selected macOS components: ${selected}"
  else
    echo "No macOS software components selected; only dotfiles will be linked."
  fi
}

validate_macos_brewfile_components() {
  local brewfile="${1:-${DOTFILES_DIR}/Brewfile}"
  local valid_components=" core development infrastructure editors vscode vscode-extensions work personal desktop japanese fonts ai rust-tools rust-projects tailscale app-store "

  awk -v valid_components="${valid_components}" '
    /^# dotfiles-component: / {
      component = $0
      sub(/^# dotfiles-component: /, "", component)
      if (index(valid_components, " " component " ") == 0) {
        print "unknown Brewfile component: " component > "/dev/stderr"
        failed = 1
      }
      next
    }
    /^(tap|brew|cask|cask_args|mas|vscode) / && component == "" {
      print "Brewfile entry is missing a dotfiles component: " $0 > "/dev/stderr"
      failed = 1
    }
    END { exit failed }
  ' "${brewfile}"
}

render_selected_macos_brewfile() {
  local output_file="$1"
  local brewfile="${DOTFILES_DIR}/Brewfile"

  validate_macos_brewfile_components "${brewfile}" || return 1
  awk -v selected=" ${MACOS_SELECTED_COMPONENTS} " '
    /^# dotfiles-component: / {
      component = $0
      sub(/^# dotfiles-component: /, "", component)
      next
    }
    component != "" && index(selected, " " component " ") > 0 { print }
  ' "${brewfile}" > "${output_file}"
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
  local homebrew_installer
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
  # Check the download separately: bash -c "" would otherwise report success.
  homebrew_installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
  # A curl | sh bootstrap has piped stdin, but can still have a controlling
  # terminal. Let Homebrew authenticate sudo itself on that terminal.
  if [ -z "${NONINTERACTIVE:-}${CI:-}" ] && { : </dev/tty; } 2>/dev/null; then
    /bin/bash -c "${homebrew_installer}" </dev/tty || return 1
  else
    NONINTERACTIVE=1 /bin/bash -c "${homebrew_installer}" || return 1
  fi

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
  local brewfile="$1"

  if ! brew trust --help >/dev/null 2>&1; then
    return 0
  fi

  if grep -Fqx 'brew "cloudflare/cloudflare/cf-terraforming"' "${brewfile}"; then
    brew trust --formula cloudflare/cloudflare/cf-terraforming || return 1
  fi
  if grep -Fqx 'brew "xcodesorg/made/xcodes"' "${brewfile}"; then
    brew trust --formula xcodesorg/made/xcodes || return 1
  fi
  if grep -Fqx 'cask "beutton/brew/wattsec"' "${brewfile}"; then
    brew trust --cask beutton/brew/wattsec || return 1
  fi
  if grep -Fqx 'cask "nikitabobko/tap/aerospace"' "${brewfile}"; then
    brew trust --cask nikitabobko/tap/aerospace || return 1
  fi
}

install_selected_macos_brewfile() {
  local bundle_file

  bundle_file="$(mktemp "${TMPDIR:-/tmp}/dotfiles-brewfile.XXXXXX")" || return 1
  if ! render_selected_macos_brewfile "${bundle_file}"; then
    rm -f "${bundle_file}"
    return 1
  fi

  if [ ! -s "${bundle_file}" ]; then
    rm -f "${bundle_file}"
    return 0
  fi

  echo "Trusting selected third-party Homebrew entries..."
  if ! ensure_homebrew_bundle_trust "${bundle_file}"; then
    rm -f "${bundle_file}"
    return 1
  fi

  echo "Applying selected Homebrew entries..."
  if ! brew bundle --file "${bundle_file}"; then
    rm -f "${bundle_file}"
    return 1
  fi

  rm -f "${bundle_file}"
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
  local shared_components

  configure_secondary_user_scope
  write_secondary_install_receipt

  echo "Secondary role: reusing ${BREW_PREFIX} without modifying Homebrew."
  export HOMEBREW_NO_AUTO_UPDATE=1

  shared_components="$(macos_public_selected_components)"
  if [ -n "${shared_components}" ]; then
    echo "Selected shared components are managed by the primary Homebrew owner: ${shared_components}"
  fi

  if macos_component_selected ai; then
    run_step "install user-scoped Codex/Claude Code CLI" install_ai_clis
  fi
  if macos_component_selected rust-tools; then
    run_step "install user-scoped rustup toolchain" install_rustup
    run_step "install user-scoped cargo tools" install_cargo_tools
  fi
  if macos_component_selected rust-projects; then
    run_step "install user-scoped Rust projects" install_rust_projects
  fi
  if macos_component_selected vscode-extensions; then
    run_step "install user-scoped VS Code extensions" install_vscode_extensions
  fi
  if macos_component_selected fonts; then
    run_step "verify shared Homebrew fonts" verify_shared_homebrew_fonts
  fi
  if macos_component_selected tailscale; then
    echo "Secondary role: Tailscale is machine-managed and was not installed."
  fi

  print_failed_steps
}

install_packages() {
  select_macos_components
  if [ -z "${MACOS_SELECTED_COMPONENTS}" ]; then
    return 0
  fi

  ensure_homebrew || return 1
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

  if [ -f "${DOTFILES_DIR}/Brewfile" ]; then
    run_step "apply selected Homebrew entries" install_selected_macos_brewfile

    if macos_component_selected fonts; then
      run_step "migrate Homebrew fonts to shared directory" ensure_shared_homebrew_fonts
    fi
  fi

  if macos_component_selected ai; then
    run_step "install Codex/Claude Code CLI" install_ai_clis
  fi
  if macos_component_selected rust-tools; then
    run_step "install rustup" install_rustup
    run_step "install cargo tools" install_cargo_tools
  fi
  if macos_component_selected rust-projects; then
    run_step "install Rust projects" install_rust_projects
  fi

  if macos_component_selected vscode-extensions; then
    run_step "install VS Code extensions" install_vscode_extensions
  fi

  if macos_component_selected tailscale; then
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
