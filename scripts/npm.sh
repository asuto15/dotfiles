#!/usr/bin/env bash

ensure_npm_global_prefix() {
  if ! command -v npm >/dev/null 2>&1; then
    return 1
  fi

  mkdir -p "${HOME}/.npm-global"
  npm config set prefix "${HOME}/.npm-global"

  case ":${PATH}:" in
    *:"${HOME}/.npm-global/bin":*) ;;
    *) PATH="${HOME}/.npm-global/bin:${PATH}" ;;
  esac
  export PATH
}
