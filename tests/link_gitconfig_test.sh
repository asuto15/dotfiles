#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d /tmp/dotfiles-link-gitconfig-test.XXXXXX)"
DOTFILES_DIR="${TEST_ROOT}/dotfiles"
HOME="${TEST_ROOT}/home"
mkdir -p "${DOTFILES_DIR}" "${HOME}"

cat >"${DOTFILES_DIR}/.gitconfig" <<'EOF'
[user]
	name = shared-user
	email = shared@example.com
EOF

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/link.sh"

install_gitconfig_wrapper

if [ -L "${HOME}/.gitconfig" ] || [ ! -f "${HOME}/.gitconfig" ]; then
  echo "FAIL: ~/.gitconfig must be a real wrapper file" >&2
  exit 1
fi
if [ "$(HOME="${HOME}" git config --global --includes user.name)" != "shared-user" ]; then
  echo "FAIL: wrapper does not expose the shared user.name" >&2
  exit 1
fi

shared_before="$(shasum -a 256 "${DOTFILES_DIR}/.gitconfig")"
git config --file "${HOME}/.gitconfig" \
  'credential.https://github.com.helper' \
  '!gh auth git-credential'
shared_after="$(shasum -a 256 "${DOTFILES_DIR}/.gitconfig")"
if [ "${shared_before}" != "${shared_after}" ]; then
  echo "FAIL: per-user credential setup changed the tracked shared config" >&2
  exit 1
fi
before_rerun="$(shasum -a 256 "${HOME}/.gitconfig")"
install_gitconfig_wrapper
after_rerun="$(shasum -a 256 "${HOME}/.gitconfig")"
if [ "${before_rerun}" != "${after_rerun}" ]; then
  echo "FAIL: rerun changed the existing per-user wrapper" >&2
  exit 1
fi

LEGACY_HOME="${TEST_ROOT}/legacy-home"
HOME="${LEGACY_HOME}"
mkdir -p "${HOME}"
ln -s "${DOTFILES_DIR}/.gitconfig" "${HOME}/.gitconfig"
install_gitconfig_wrapper

if [ -L "${HOME}/.gitconfig" ] || [ ! -f "${HOME}/.gitconfig" ]; then
  echo "FAIL: legacy shared symlink was not migrated to a wrapper" >&2
  exit 1
fi
if [ "$(HOME="${HOME}" git config --global --includes user.email)" != "shared@example.com" ]; then
  echo "FAIL: migrated wrapper does not expose the shared user.email" >&2
  exit 1
fi
legacy_backup="$(find "${HOME}" -maxdepth 1 -type l -name '.gitconfig.backup.*' -print -quit)"
if [ -z "${legacy_backup}" ] ||
   [ "$(readlink "${legacy_backup}")" != "${DOTFILES_DIR}/.gitconfig" ]; then
  echo "FAIL: legacy symlink was not retained as a backup" >&2
  exit 1
fi

EXISTING_HOME="${TEST_ROOT}/existing-home"
HOME="${EXISTING_HOME}"
mkdir -p "${HOME}"
cat >"${HOME}/.gitconfig" <<'EOF'
[user]
	name = existing-local-user
EOF
install_gitconfig_wrapper

if [ "$(HOME="${HOME}" git config --global --includes user.name)" != "existing-local-user" ]; then
  echo "FAIL: existing per-user Git configuration was not preserved" >&2
  exit 1
fi

echo "link_gitconfig_test: PASS"
