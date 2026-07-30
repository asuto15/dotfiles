#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d /tmp/dotfiles-pkg-macos-test.XXXXXX)"
DOTFILES_DIR="${TEST_ROOT}/dotfiles"
BREW_PREFIX="${TEST_ROOT}/homebrew"
DOTFILES_SHARED_FONT_DIR="${TEST_ROOT}/Library/Fonts"
BREW_CALLS="${TEST_ROOT}/brew-calls"
mkdir -p \
  "${DOTFILES_DIR}" \
  "${BREW_PREFIX}/Caskroom/font-already-shared/.metadata" \
  "${BREW_PREFIX}/Caskroom/font-needs-migration/.metadata" \
  "${DOTFILES_SHARED_FONT_DIR}"

cat >"${DOTFILES_DIR}/Brewfile" <<'EOF'
cask_args fontdir: "/Library/Fonts"
cask "font-already-shared"
cask "font-needs-migration"
EOF

jq -n --arg fontdir "${DOTFILES_SHARED_FONT_DIR}" \
  '{default: {fontdir: $fontdir}, env: {}, explicit: {}}' \
  >"${BREW_PREFIX}/Caskroom/font-already-shared/.metadata/config.json"
jq -n \
  --arg fontdir "${TEST_ROOT}/primary/Library/Fonts" \
  '{default: {fontdir: $fontdir}, env: {}, explicit: {}}' \
  >"${BREW_PREFIX}/Caskroom/font-needs-migration/.metadata/config.json"

touch \
  "${DOTFILES_SHARED_FONT_DIR}/AlreadyShared.ttf" \
  "${DOTFILES_SHARED_FONT_DIR}/MigratedFont.otf"

brew() {
  printf '%s\n' "$*" >>"${BREW_CALLS}"
  case "$1 $2" in
    "list --cask")
      return 0
      ;;
    "reinstall --cask")
      return 0
      ;;
    "info --cask")
      cat <<'EOF'
{
  "casks": [
    {
      "token": "font-already-shared",
      "artifacts": [{"font": ["AlreadyShared.ttf"]}]
    },
    {
      "token": "font-needs-migration",
      "artifacts": [{"font": ["nested/MigratedFont.otf"]}]
    }
  ]
}
EOF
      ;;
    *)
      echo "unexpected brew invocation: $*" >&2
      return 1
      ;;
  esac
}

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/pkg_macos.sh"

ensure_shared_homebrew_fonts
if grep -Fq "font-already-shared" "${BREW_CALLS}"; then
  echo "FAIL: already-shared font cask should not be reinstalled" >&2
  exit 1
fi
if ! grep -Fq \
  "reinstall --cask --no-ask --fontdir=${DOTFILES_SHARED_FONT_DIR} font-needs-migration" \
  "${BREW_CALLS}"; then
  echo "FAIL: font cask needing migration was not reinstalled" >&2
  exit 1
fi

: >"${BREW_CALLS}"
verify_shared_homebrew_fonts

: >"${BREW_CALLS}"
SAVED_PATH="${PATH}"
PATH="/usr/bin:/bin"
DOTFILES_ROLE=secondary
if install_ai_clis; then
  echo "FAIL: secondary AI CLI setup should fail cleanly when npm is unavailable" >&2
  exit 1
fi
PATH="${SAVED_PATH}"
if [ -s "${BREW_CALLS}" ]; then
  echo "FAIL: secondary AI CLI setup attempted to mutate Homebrew" >&2
  exit 1
fi

SECONDARY_HOME="${TEST_ROOT}/secondary-home"
mkdir -p "${SECONDARY_HOME}/dotfiles"
SECONDARY_HOME="$(cd "${SECONDARY_HOME}" && pwd -P)"
HOME="${SECONDARY_HOME}"
DOTFILES_DIR="${SECONDARY_HOME}/dotfiles"
CARGO_HOME="${TEST_ROOT}/outside-cargo"
RUSTUP_HOME="${TEST_ROOT}/outside-rustup"
RUST_PROJECTS_DIR="${TEST_ROOT}/outside-projects"
NPM_CONFIG_PREFIX="${TEST_ROOT}/outside-npm"
XDG_STATE_HOME="${TEST_ROOT}/outside-state"
VSCODE_EXTENSIONS_DIR="${TEST_ROOT}/outside-vscode"
configure_secondary_user_scope
write_secondary_install_receipt

for managed_path in \
  "${CARGO_HOME}" \
  "${CARGO_INSTALL_ROOT}" \
  "${CARGO_TARGET_DIR}" \
  "${RUSTUP_HOME}" \
  "${RUST_PROJECTS_DIR}" \
  "${NPM_CONFIG_PREFIX}" \
  "${NPM_CONFIG_CACHE}" \
  "${NPM_CONFIG_USERCONFIG}" \
  "${XDG_CACHE_HOME}" \
  "${XDG_CONFIG_HOME}" \
  "${XDG_DATA_HOME}" \
  "${XDG_STATE_HOME}" \
  "${HOMEBREW_CACHE}" \
  "${HOMEBREW_LOGS}" \
  "${VSCODE_EXTENSIONS_DIR}"
do
  case "${managed_path}" in
    "${SECONDARY_HOME}"/*) ;;
    *)
      echo "FAIL: secondary managed path escaped HOME: ${managed_path}" >&2
      exit 1
      ;;
  esac
done

if [ ! -f "${XDG_STATE_HOME}/dotfiles/secondary-install-paths" ]; then
  echo "FAIL: secondary install receipt was not written" >&2
  exit 1
fi

DOTFILES_DIR="${TEST_ROOT}/outside-dotfiles"
mkdir -p "${DOTFILES_DIR}"
if configure_secondary_user_scope 2>/dev/null; then
  echo "FAIL: secondary setup accepted a dotfiles checkout outside HOME" >&2
  exit 1
fi

echo "pkg_macos_multi_user_test: PASS"
