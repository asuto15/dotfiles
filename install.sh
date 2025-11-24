#!/usr/bin/env bash
set -euo pipefail

echo "Setting up dotfiles..."

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

source "${DOTFILES_DIR}/scripts/pkg_${PLATFORM}.sh"
source "${DOTFILES_DIR}/scripts/link.sh"

install_packages
link_dotfiles

echo "Done."
