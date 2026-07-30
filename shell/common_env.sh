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

# Keep keg-only Homebrew LLVM opt-in. In particular, its `dsymutil` cannot be
# mixed with another LLVM build's `libLLVM.dylib` while building rustc.
if [ -n "${BREW_PREFIX}" ]; then
  remove_path_entry "${BREW_PREFIX}/opt/llvm/bin"
fi

enable_homebrew_llvm() {
  ensure_brew_prefix

  local llvm_prefix
  llvm_prefix="${BREW_PREFIX}/opt/llvm"
  if [ -z "${BREW_PREFIX}" ] || [ ! -d "${llvm_prefix}" ]; then
    printf '%s\n' "Homebrew LLVM is not installed." >&2
    return 1
  fi

  prepend_path_if_exists "${llvm_prefix}/bin"
  case " ${LDFLAGS:-} " in
    *" -L${llvm_prefix}/lib "*) ;;
    *) LDFLAGS="-L${llvm_prefix}/lib${LDFLAGS:+ ${LDFLAGS}}" ;;
  esac
  case " ${CPPFLAGS:-} " in
    *" -I${llvm_prefix}/include "*) ;;
    *) CPPFLAGS="-I${llvm_prefix}/include${CPPFLAGS:+ ${CPPFLAGS}}" ;;
  esac

  CC="${llvm_prefix}/bin/clang"
  CXX="${llvm_prefix}/bin/clang++"
  LLVM_CONFIG="${llvm_prefix}/bin/llvm-config"
  export PATH LDFLAGS CPPFLAGS CC CXX LLVM_CONFIG
}

# Starship configuration
export STARSHIP_CONFIG="${HOME}/.config/starship/starship.toml"
export STARSHIP_CACHE="${HOME}/.starship/cache"

# GnuPG
GPG_TTY_CMD="$(command -v tty 2>/dev/null || true)"
if [ -n "${GPG_TTY_CMD}" ]; then
  export GPG_TTY="$(${GPG_TTY_CMD})"
fi

export PATH
