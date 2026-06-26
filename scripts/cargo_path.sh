#!/usr/bin/env bash

ensure_cargo_path() {
  local helper_dir
  helper_dir="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

  . "${helper_dir}/shell/path_helpers.sh"
  ensure_brew_prefix

  if [ -n "${BREW_PREFIX}" ]; then
    prepend_path_if_exists "${BREW_PREFIX}/opt/rustup/bin"
  fi
  prepend_path_if_exists "${HOME}/.cargo/bin"
  export PATH
}
