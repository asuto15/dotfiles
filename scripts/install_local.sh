#!/usr/bin/env bash
set -euo pipefail

echo "Setting up dotfiles..."

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OS_NAME="$(uname -s)"

case "${DOTFILES_MINIMAL:-0}" in
  0|1) ;;
  *) echo "DOTFILES_MINIMAL must be 0 or 1." >&2; exit 1 ;;
esac

# Check before linking anything: the Git config wrapper also needs Git.
if [ "${DOTFILES_MINIMAL:-0}" = "1" ]; then
  if { [ "${OS_NAME}" = Darwin ] && [ "$(command -v git)" = /usr/bin/git ] &&
       ! xcode-select -p >/dev/null 2>&1; } || ! git --version >/dev/null 2>&1; then
    echo "Minimal setup requires working Git; no software was installed." >&2
    echo "On macOS, install Apple's Command Line Tools with xcode-select --install, then rerun." >&2
    exit 1
  fi
fi

case "${OS_NAME}" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  *)
    echo "Unsupported platform: ${OS_NAME}"
    exit 1
    ;;
esac

export DOTFILES_DIR

source "${DOTFILES_DIR}/scripts/cargo_path.sh"
source "${DOTFILES_DIR}/scripts/rust_projects.sh"
source "${DOTFILES_DIR}/scripts/npm.sh"
source "${DOTFILES_DIR}/scripts/install_role.sh"
source "${DOTFILES_DIR}/scripts/pkg_${PLATFORM}.sh"
source "${DOTFILES_DIR}/scripts/link.sh"

resolve_dotfiles_role
echo "Dotfiles install role: ${DOTFILES_ROLE} (${DOTFILES_ROLE_REASON})"

if [ "${DOTFILES_MINIMAL:-0}" = "1" ] && [ "${PLATFORM}" = linux ]; then
  echo "Minimal setup: only dotfiles will be linked; no software will be installed."
else
  install_packages
fi
link_dotfiles
if command -v print_platform_post_install_notes >/dev/null 2>&1; then
  print_platform_post_install_notes
fi

echo "Done."
