#!/usr/bin/env bash
# Ensure ~/.local/bin is present in PATH for interactive shells.
case ":${PATH}:" in
  *:"${HOME}/.local/bin":*) ;;
  *)
    PATH="${HOME}/.local/bin:${PATH}"
    export PATH
    ;;
esac

# LM Studio CLI (lms)
case ":${PATH}:" in
  *:"${HOME}/.lmstudio/bin":*) ;;
  *)
    if [ -d "${HOME}/.lmstudio/bin" ]; then
      PATH="${PATH}:${HOME}/.lmstudio/bin"
      export PATH
    fi
    ;;
esac
