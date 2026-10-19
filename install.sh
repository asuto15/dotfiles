#!/bin/sh
set -eu

DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-https://github.com/asuto15/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-${HOME}/dotfiles}"

for option in "$@"; do
  case "${option}" in
    --minimal) DOTFILES_MINIMAL=1 ;;
    -h|--help)
      echo "Usage: install.sh [--minimal]"
      echo "  Without options, choose a setup mode interactively on macOS."
      echo "  --minimal  Link dotfiles only; do not install additional software."
      exit 0
      ;;
    *) echo "Unknown option: ${option}" >&2; exit 1 ;;
  esac
done
case "${DOTFILES_MINIMAL:-0}" in
  0|1) ;;
  *) echo "DOTFILES_MINIMAL must be 0 or 1." >&2; exit 1 ;;
esac

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

select_install_mode() {
  INSTALLER_USE_TTY=0
  if [ -n "${NONINTERACTIVE:-}${CI:-}" ]; then
    export DOTFILES_MACOS_INTERACTIVE=0
  fi

  # Ask before installing even bootstrap prerequisites. Explicit environment
  # selections and unattended runs retain their existing behavior.
  if [ "${DOTFILES_MINIMAL+x}" != x ] &&
     [ -z "${DOTFILES_MACOS_COMPONENTS:-}" ] &&
     [ "${DOTFILES_MACOS_INTERACTIVE:-auto}" != 0 ] &&
     [ "$(uname -s)" = Darwin ] &&
     { : </dev/tty >/dev/tty; } 2>/dev/null; then
    cat >/dev/tty <<'EOF'
Choose a setup mode:
  1) Minimal: link dotfiles only; install no additional software (default)
  2) Custom: choose which software components to install
EOF
    while :; do
      printf 'Setup mode [1/2, default: 1]: ' >/dev/tty
      if ! IFS= read -r setup_mode </dev/tty; then
        echo "No setup mode selected; aborting." >&2
        return 1
      fi
      case "${setup_mode}" in
        ""|1) DOTFILES_MINIMAL=1; break ;;
        2) DOTFILES_MINIMAL=0; break ;;
        *) echo "Please enter 1 or 2." >/dev/tty ;;
      esac
    done
    INSTALLER_USE_TTY=1
  fi
  export DOTFILES_MINIMAL="${DOTFILES_MINIMAL:-0}"
}

ensure_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    return
  fi
  if ! command_exists sudo; then
    echo "sudo is required to install prerequisites as a non-root user." >&2
    exit 1
  fi
  if sudo -n true 2>/dev/null; then
    return
  fi
  if { : </dev/tty >/dev/tty; } 2>/dev/null; then
    echo "sudo authentication is required." >/dev/tty
    if sudo -v </dev/tty >/dev/tty 2>&1; then
      return
    fi
  else
    echo "sudo authentication is required, but no TTY is available." >&2
    exit 1
  fi
  echo "sudo authentication failed." >&2
  exit 1
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command_exists sudo; then
    ensure_sudo
    sudo -n "$@"
  else
    echo "sudo is required to install prerequisites as a non-root user." >&2
    exit 1
  fi
}

run_local_installer() {
  if command_exists bash; then
    if [ "${INSTALLER_USE_TTY:-0}" = 1 ]; then
      exec bash "${DOTFILES_DIR}/scripts/install_local.sh" </dev/tty
    fi
    exec bash "${DOTFILES_DIR}/scripts/install_local.sh"
  fi
  echo "bash is required to run the local installer." >&2
  exit 1
}

ensure_homebrew() {
  brew_bin=""
  if command_exists brew; then
    brew_bin="$(command -v brew)"
  elif [ -x /opt/homebrew/bin/brew ]; then
    brew_bin="/opt/homebrew/bin/brew"
  elif [ -x /usr/local/bin/brew ]; then
    brew_bin="/usr/local/bin/brew"
  fi

  if [ -n "${brew_bin}" ]; then
    eval "$("${brew_bin}" shellenv)"
    return
  fi

  if [ "${DOTFILES_ROLE:-auto}" = "secondary" ]; then
    echo "DOTFILES_ROLE=secondary requires an existing Homebrew installation." >&2
    exit 1
  fi

  if ! command_exists curl; then
    echo "curl is required to install Homebrew." >&2
    exit 1
  fi
  if [ ! -x /bin/bash ]; then
    echo "/bin/bash is required to install Homebrew." >&2
    exit 1
  fi

  echo "Installing Homebrew..."
  # Check the download separately: bash -c "" would otherwise report success.
  homebrew_installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
  # A curl | sh bootstrap has piped stdin, but can still have a controlling
  # terminal. Let Homebrew authenticate sudo itself on that terminal.
  if [ -z "${NONINTERACTIVE:-}${CI:-}" ] && { : </dev/tty; } 2>/dev/null; then
    /bin/bash -c "${homebrew_installer}" </dev/tty || return 1
  else
    NONINTERACTIVE=1 /bin/bash -c "${homebrew_installer}" || return 1
  fi

  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "Homebrew installation failed or brew is not on PATH." >&2
    exit 1
  fi
}

install_prerequisites_macos() {
  if git_available && command_exists bash; then
    return
  fi

  ensure_homebrew || return 1

  if ! git_available; then
    brew install git
  fi
  if ! command_exists bash; then
    brew install bash
  fi
}

install_prerequisites_linux() {
  if command_exists git && command_exists bash; then
    return
  fi

  ensure_sudo

  if command_exists apt-get; then
    run_as_root apt-get update
    run_as_root apt-get install -y git bash
  elif command_exists dnf; then
    run_as_root dnf install -y git bash
  elif command_exists yum; then
    run_as_root yum install -y git bash
  elif command_exists pacman; then
    run_as_root pacman -Sy --needed --noconfirm git bash
  elif command_exists apk; then
    run_as_root apk add git bash
  elif command_exists zypper; then
    run_as_root zypper install -y git bash
  else
    echo "Unsupported Linux package manager. Install git and bash, then rerun." >&2
    exit 1
  fi
}

install_prerequisites() {
  if [ "${DOTFILES_MINIMAL:-0}" = "1" ]; then
    if git_available && command_exists bash; then
      return
    fi
    echo "Minimal setup requires working Git and Bash; no software was installed." >&2
    echo "On macOS, install Apple's Command Line Tools with xcode-select --install, then rerun." >&2
    exit 1
  fi

  case "$(uname -s)" in
    Darwin) install_prerequisites_macos ;;
    Linux) install_prerequisites_linux ;;
    *)
      echo "Unsupported platform: $(uname -s)" >&2
      exit 1
      ;;
  esac

  if ! git_available; then
    echo "git installation failed or git is not on PATH." >&2
    exit 1
  fi
  if ! command_exists bash; then
    echo "bash installation failed or bash is not on PATH." >&2
    exit 1
  fi
}

git_available() {
  command_exists git || return 1
  # /usr/bin/git exists even before Apple's Command Line Tools are installed.
  if [ "$(uname -s)" = Darwin ] && [ "$(command -v git)" = /usr/bin/git ]; then
    xcode-select -p >/dev/null 2>&1 || return 1
  fi
  git --version >/dev/null 2>&1
}

script_dir() {
  case "$0" in
    */*) dirname "$0" ;;
    *) return 1 ;;
  esac
}

LOCAL_DOTFILES_DIR=""
select_install_mode
if [ -z "${DOTFILES_BOOTSTRAP:-}" ]; then
  if dir="$(script_dir 2>/dev/null)" && [ -f "${dir}/scripts/install_local.sh" ]; then
    LOCAL_DOTFILES_DIR="$(cd "${dir}" && pwd)"
  fi
fi

if [ -n "${LOCAL_DOTFILES_DIR}" ]; then
  DOTFILES_DIR="${LOCAL_DOTFILES_DIR}"
  export DOTFILES_DIR
  export DOTFILES_BOOTSTRAP=1
  run_local_installer
fi

install_prerequisites

if [ ! -d "${DOTFILES_DIR}" ]; then
  echo "Cloning dotfiles into ${DOTFILES_DIR}..."
  git clone "${DOTFILES_REPO_URL}" "${DOTFILES_DIR}"
elif [ ! -d "${DOTFILES_DIR}/.git" ]; then
  echo "${DOTFILES_DIR} exists but is not a git repository. Aborting." >&2
  exit 1
elif [ "${DOTFILES_UPDATE:-1}" = "1" ]; then
  echo "Updating dotfiles in ${DOTFILES_DIR}..."
  if ! git -C "${DOTFILES_DIR}" pull --ff-only; then
    echo "warn: failed to update ${DOTFILES_DIR}; continuing with the local checkout." >&2
  fi
fi

if [ ! -f "${DOTFILES_DIR}/scripts/install_local.sh" ]; then
  echo "${DOTFILES_DIR} does not look like this dotfiles repository. Aborting." >&2
  exit 1
fi

export DOTFILES_DIR
export DOTFILES_BOOTSTRAP=1
run_local_installer
