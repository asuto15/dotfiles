#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d /tmp/dotfiles-macos-selection-test.XXXXXX)"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${REPO_DIR}"
HOME="${TEST_ROOT}/home"
DOTFILES_MACOS_STATE_FILE="${TEST_ROOT}/macos-install.env"
DOTFILES_MACOS_INTERACTIVE=0
mkdir -p "${HOME}"

source "${DOTFILES_DIR}/scripts/pkg_macos.sh"

assert_selected() {
  local component="$1"
  if ! macos_component_selected "${component}"; then
    echo "FAIL: expected component to be selected: ${component}" >&2
    exit 1
  fi
}

assert_not_selected() {
  local component="$1"
  if macos_component_selected "${component}"; then
    echo "FAIL: unexpected selected component: ${component}" >&2
    exit 1
  fi
}

assert_file_contains() {
  local needle="$1"
  local file="$2"
  if ! grep -Fqx "${needle}" "${file}"; then
    echo "FAIL: expected ${file} to contain: ${needle}" >&2
    exit 1
  fi
}

assert_file_lacks() {
  local needle="$1"
  local file="$2"
  if grep -Fqx "${needle}" "${file}"; then
    echo "FAIL: expected ${file} not to contain: ${needle}" >&2
    exit 1
  fi
}

homebrew_called=0
ensure_homebrew() {
  homebrew_called=1
}

DOTFILES_MACOS_COMPONENTS=none
install_packages
if [ "${homebrew_called}" != "0" ]; then
  echo "FAIL: a link-only setup invoked Homebrew" >&2
  exit 1
fi

DOTFILES_MACOS_COMPONENTS='work,vscode-extensions,rust-projects'
select_macos_components
assert_selected work
assert_selected vscode
assert_selected vscode-extensions
assert_selected rust-tools
assert_selected rust-projects
assert_selected app-store
assert_not_selected personal
assert_not_selected infrastructure

SELECTED_BREWFILE="${TEST_ROOT}/selected.Brewfile"
render_selected_macos_brewfile "${SELECTED_BREWFILE}"
assert_file_contains 'brew "mas"' "${SELECTED_BREWFILE}"
assert_file_contains 'cask "visual-studio-code"' "${SELECTED_BREWFILE}"
assert_file_contains 'cask "slack"' "${SELECTED_BREWFILE}"
assert_file_contains 'mas "Microsoft Word", id: 462054704' "${SELECTED_BREWFILE}"
assert_file_contains 'brew "rustup"' "${SELECTED_BREWFILE}"
assert_file_contains 'vscode "rust-lang.rust-analyzer"' "${SELECTED_BREWFILE}"
assert_file_lacks 'cask "docker-desktop"' "${SELECTED_BREWFILE}"
assert_file_lacks 'mas "Kindle", id: 302584613' "${SELECTED_BREWFILE}"
assert_file_lacks 'brew "ollama", restart_service: :changed' "${SELECTED_BREWFILE}"

unset DOTFILES_MACOS_COMPONENTS
select_macos_components
assert_selected work
assert_selected vscode-extensions
assert_selected rust-projects

DOTFILES_MACOS_COMPONENTS=none
INSTALL_AI_CLI=1
select_macos_components
assert_selected ai
unset INSTALL_AI_CLI

# Minimal must override saved selections, explicit lists, legacy flags, and
# forced interactive selection even when no terminal is available.
DOTFILES_MINIMAL=1
DOTFILES_MACOS_COMPONENTS=all
DOTFILES_MACOS_INTERACTIVE=1
INSTALL_AI_CLI=1
INSTALL_RUST_TOOLS=1
INSTALL_RUST_PROJECTS=1
INSTALL_VSCODE_EXTENSIONS=1
INSTALL_FONTS=1
INSTALL_TAILSCALE=1
install_packages
if [ -n "${MACOS_SELECTED_COMPONENTS}" ] || [ "${homebrew_called}" != "0" ]; then
  echo "FAIL: minimal setup selected software or invoked Homebrew" >&2
  exit 1
fi
assert_file_contains 'MACOS_COMPONENTS=none' "${DOTFILES_MACOS_STATE_FILE}"
unset DOTFILES_MINIMAL INSTALL_AI_CLI INSTALL_RUST_TOOLS INSTALL_RUST_PROJECTS
unset INSTALL_VSCODE_EXTENSIONS INSTALL_FONTS INSTALL_TAILSCALE
DOTFILES_MACOS_INTERACTIVE=0

DOTFILES_MACOS_COMPONENTS=not-a-component
if select_macos_components >/dev/null 2>&1; then
  echo "FAIL: an unknown component was accepted" >&2
  exit 1
fi

echo "pkg_macos_selection_test: PASS"
