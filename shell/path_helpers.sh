#!/usr/bin/env bash

prepend_path_if_exists() {
  local dir="$1"
  if [ -d "${dir}" ]; then
    PATH=":${PATH}:"
    PATH="${PATH//:${dir}:/:}"
    PATH="${PATH#:}"
    PATH="${PATH%:}"
    if [ -n "${PATH}" ]; then
      PATH="${dir}:${PATH}"
    else
      PATH="${dir}"
    fi
  fi
}

detect_brew_prefix() {
  if command -v brew >/dev/null 2>&1; then
    brew --prefix
  elif [ -d "/opt/homebrew" ]; then
    printf '%s\n' "/opt/homebrew"
  elif [ -d "/usr/local/Homebrew" ]; then
    printf '%s\n' "/usr/local"
  elif [ -d "/home/linuxbrew/.linuxbrew" ]; then
    printf '%s\n' "/home/linuxbrew/.linuxbrew"
  fi
}

ensure_brew_prefix() {
  BREW_PREFIX="${BREW_PREFIX:-$(detect_brew_prefix)}"
}
