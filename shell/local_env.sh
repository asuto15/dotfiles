#!/usr/bin/env bash
# Ensure ~/.local/bin is present in PATH for interactive shells.
case ":${PATH}:" in
  *:"${HOME}/.local/bin":*) ;;
  *)
    PATH="${HOME}/.local/bin:${PATH}"
    export PATH
    ;;
esac
