#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d /tmp/dotfiles-link-test.XXXXXX)"
DOTFILES_DIR="${TEST_ROOT}/dotfiles"
HOME="${TEST_ROOT}/home"

mkdir -p "${DOTFILES_DIR}/.config/omniwm" "${HOME}/.config/omniwm"
printf '%s\n' 'managed = true' >"${DOTFILES_DIR}/.config/omniwm/settings.toml"
printf '%s\n' 'original = true' >"${HOME}/.config/omniwm/settings.toml"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/link.sh"

link_dotfiles

if [ ! -L "${HOME}/.config/omniwm" ]; then
  echo "FAIL: ~/.config/omniwm is not a symlink" >&2
  exit 1
fi
if [ "$(readlink "${HOME}/.config/omniwm")" != "${DOTFILES_DIR}/.config/omniwm" ]; then
  echo "FAIL: ~/.config/omniwm does not point to the tracked config directory" >&2
  exit 1
fi
if ! grep -Fqx 'managed = true' "${HOME}/.config/omniwm/settings.toml"; then
  echo "FAIL: linked OmniWM settings do not come from the dotfiles checkout" >&2
  exit 1
fi

backup="$(find "${HOME}/.config" -maxdepth 1 -type d -name 'omniwm.backup.*' -print -quit)"
if [ -z "${backup}" ] ||
   ! grep -Fqx 'original = true' "${backup}/settings.toml"; then
  echo "FAIL: existing OmniWM settings were not preserved in a backup" >&2
  exit 1
fi

backup_count_before="$(find "${HOME}/.config" -maxdepth 1 -type d -name 'omniwm.backup.*' | wc -l | tr -d ' ')"
link_dotfiles
backup_count_after="$(find "${HOME}/.config" -maxdepth 1 -type d -name 'omniwm.backup.*' | wc -l | tr -d ' ')"

if [ "${backup_count_before}" != "${backup_count_after}" ]; then
  echo "FAIL: rerun created an unnecessary OmniWM settings backup" >&2
  exit 1
fi

echo "link_dotfiles_test: PASS"
