#!/usr/bin/env bash
# Common environment for both zsh/bash. Keep POSIX-compatible constructs.

if [ -n "${BASH_SOURCE[0]:-}" ]; then
  COMMON_ENV_FILE="${BASH_SOURCE[0]}"
else
  COMMON_ENV_FILE="${(%):-%x}"
fi
COMMON_ENV_DIR="$(cd "$(dirname "${COMMON_ENV_FILE}")" && pwd)"
. "${COMMON_ENV_DIR}/path_helpers.sh"
unset COMMON_ENV_DIR COMMON_ENV_FILE

# Detect Homebrew prefix without assuming architecture
ensure_brew_prefix

if [ -n "${BREW_PREFIX}" ]; then
  prepend_path_if_exists "${BREW_PREFIX}/bin"
  prepend_path_if_exists "${BREW_PREFIX}/sbin"
fi

# Local user bin paths
prepend_path_if_exists "${HOME}/.local/bin"
prepend_path_if_exists "${HOME}/.npm-global/bin"
if [ -n "${BREW_PREFIX}" ]; then
  prepend_path_if_exists "${BREW_PREFIX}/opt/rustup/bin"
fi
prepend_path_if_exists "${HOME}/.cargo/bin"
prepend_path_if_exists "${HOME}/.anyenv/bin"

# Add nodenv shims if available
if [ -d "${HOME}/.anyenv/envs/nodenv/shims" ]; then
  prepend_path_if_exists "${HOME}/.anyenv/envs/nodenv/shims"
fi
if [ -d "${HOME}/.anyenv/envs/nodenv/bin" ]; then
  prepend_path_if_exists "${HOME}/.anyenv/envs/nodenv/bin"
fi

# Ruby (Homebrew)
if [ -n "${BREW_PREFIX}" ] && [ -d "${BREW_PREFIX}/opt/ruby/bin" ]; then
  prepend_path_if_exists "${BREW_PREFIX}/opt/ruby/bin"
fi

# macOS framework Python (falls back to default if not present)
prepend_path_if_exists "/Library/Frameworks/Python.framework/Versions/Current/bin"

# LLVM flags (only if installed via Homebrew)
if [ -n "${BREW_PREFIX}" ] && [ -d "${BREW_PREFIX}/opt/llvm" ]; then
  export LDFLAGS="-L${BREW_PREFIX}/opt/llvm/lib${LDFLAGS:+:${LDFLAGS}}"
  export CPPFLAGS="-I${BREW_PREFIX}/opt/llvm/include${CPPFLAGS:+:${CPPFLAGS}}"
  prepend_path_if_exists "${BREW_PREFIX}/opt/llvm/bin"
fi

# Starship configuration
export STARSHIP_CONFIG="${HOME}/.config/starship/starship.toml"
export STARSHIP_CACHE="${HOME}/.starship/cache"

# GnuPG
GPG_TTY_CMD="$(command -v tty 2>/dev/null || true)"
if [ -n "${GPG_TTY_CMD}" ]; then
  export GPG_TTY="$(${GPG_TTY_CMD})"
fi

export PATH
