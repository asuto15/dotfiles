#!/usr/bin/env bash
set -euo pipefail

echo "Setting up dotfiles..."

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OS_NAME="$(uname -s)"

# Optional feature flags
INSTALL_TAILSCALE="${INSTALL_TAILSCALE:-0}"

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

install_packages
link_dotfiles
if command -v print_platform_post_install_notes >/dev/null 2>&1; then
  print_platform_post_install_notes
fi

echo "Done."
