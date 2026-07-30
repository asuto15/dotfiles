#!/usr/bin/env bash

existing_homebrew_prefix() {
  local brew_bin

  if command -v brew >/dev/null 2>&1; then
    brew_bin="$(command -v brew)"
    if [ -x "${brew_bin}" ]; then
      brew --prefix
      return
    fi
  fi

  if [ -x "/opt/homebrew/bin/brew" ]; then
    printf '%s\n' "/opt/homebrew"
  elif [ -x "/usr/local/bin/brew" ]; then
    printf '%s\n' "/usr/local"
  elif [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    printf '%s\n' "/home/linuxbrew/.linuxbrew"
  fi
}

path_owner_uid() {
  local target="$1"

  case "$(uname -s)" in
    Darwin) stat -f '%u' "${target}" ;;
    *) stat -c '%u' "${target}" ;;
  esac
}

resolve_dotfiles_role() {
  local requested="${DOTFILES_ROLE:-auto}"
  local os_name current_uid brew_prefix brew_owner_uid

  case "${requested}" in
    auto|primary|secondary) ;;
    *)
      echo "DOTFILES_ROLE must be auto, primary, or secondary (got: ${requested})." >&2
      return 1
      ;;
  esac

  os_name="$(uname -s)"
  current_uid="${_DOTFILES_TEST_CURRENT_UID:-$(id -u)}"
  brew_prefix="${_DOTFILES_TEST_HOMEBREW_PREFIX:-$(existing_homebrew_prefix)}"
  brew_owner_uid=""
  if [ -n "${brew_prefix}" ] && [ -d "${brew_prefix}" ]; then
    brew_owner_uid="$(path_owner_uid "${brew_prefix}")"
  fi

  if [ "${requested}" = "auto" ]; then
    if [ "${os_name}" = "Darwin" ] &&
       [ -n "${brew_owner_uid}" ] &&
       [ "${brew_owner_uid}" != "${current_uid}" ]; then
      DOTFILES_ROLE="secondary"
      DOTFILES_ROLE_REASON="Homebrew prefix ${brew_prefix} is owned by uid ${brew_owner_uid}"
    else
      DOTFILES_ROLE="primary"
      if [ -n "${brew_prefix}" ]; then
        DOTFILES_ROLE_REASON="Homebrew prefix ${brew_prefix} is owned by the current user"
      else
        DOTFILES_ROLE_REASON="no existing Homebrew prefix requires secondary-user protection"
      fi
    fi
  else
    DOTFILES_ROLE="${requested}"
    DOTFILES_ROLE_REASON="explicit DOTFILES_ROLE=${requested}"
  fi

  if [ "${DOTFILES_ROLE}" = "primary" ] &&
     [ "${os_name}" = "Darwin" ] &&
     [ -n "${brew_owner_uid}" ] &&
     [ "${brew_owner_uid}" != "${current_uid}" ]; then
    cat >&2 <<EOF
Refusing primary setup because ${brew_prefix} is owned by uid ${brew_owner_uid},
not the current uid ${current_uid}. Use DOTFILES_ROLE=secondary, or repair the
Homebrew ownership deliberately before running a primary setup.
EOF
    return 1
  fi

  export DOTFILES_ROLE DOTFILES_ROLE_REASON
}
