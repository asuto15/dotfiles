#!/bin/sh
set -eu

DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-https://github.com/asuto15/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-${HOME}/dotfiles}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command_exists sudo; then
    sudo "$@"
  else
    echo "sudo is required to install prerequisites as a non-root user." >&2
    exit 1
  fi
}

run_local_installer() {
  if command_exists bash; then
    exec bash "${DOTFILES_DIR}/scripts/install_local.sh"
  fi
  echo "bash is required to run the local installer." >&2
  exit 1
}

ensure_homebrew() {
  if command_exists brew; then
    return
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
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

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
  ensure_homebrew

  if ! command_exists git; then
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
  case "$(uname -s)" in
    Darwin) install_prerequisites_macos ;;
    Linux) install_prerequisites_linux ;;
    *)
      echo "Unsupported platform: $(uname -s)" >&2
      exit 1
      ;;
  esac

  if ! command_exists git; then
    echo "git installation failed or git is not on PATH." >&2
    exit 1
  fi
  if ! command_exists bash; then
    echo "bash installation failed or bash is not on PATH." >&2
    exit 1
  fi
}

script_dir() {
  case "$0" in
    */*) dirname "$0" ;;
    *) return 1 ;;
  esac
}

LOCAL_DOTFILES_DIR=""
if [ -z "${DOTFILES_BOOTSTRAP:-}" ]; then
  if dir="$(script_dir 2>/dev/null)" && [ -f "${dir}/scripts/install_local.sh" ]; then
    LOCAL_DOTFILES_DIR="$(cd "${dir}" && pwd)"
  fi
fi

install_prerequisites

if [ -n "${LOCAL_DOTFILES_DIR}" ]; then
  DOTFILES_DIR="${LOCAL_DOTFILES_DIR}"
  export DOTFILES_DIR
  export DOTFILES_BOOTSTRAP=1
  run_local_installer
fi

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
