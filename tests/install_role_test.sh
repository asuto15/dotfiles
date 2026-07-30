#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d /tmp/dotfiles-role-test.XXXXXX)"
FAKE_PREFIX="${TEST_ROOT}/homebrew"
mkdir -p "${FAKE_PREFIX}/bin"
touch "${FAKE_PREFIX}/bin/brew"
chmod +x "${FAKE_PREFIX}/bin/brew"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/install_role.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [ "${expected}" != "${actual}" ]; then
    echo "FAIL: ${message}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
}

current_uid="$(id -u)"

DOTFILES_ROLE=auto
_DOTFILES_TEST_HOMEBREW_PREFIX="${FAKE_PREFIX}"
_DOTFILES_TEST_CURRENT_UID="${current_uid}"
resolve_dotfiles_role
assert_eq "primary" "${DOTFILES_ROLE}" "owner should resolve to primary"

DOTFILES_ROLE=auto
_DOTFILES_TEST_CURRENT_UID="$((current_uid + 1))"
resolve_dotfiles_role
assert_eq "secondary" "${DOTFILES_ROLE}" "non-owner should resolve to secondary"

DOTFILES_ROLE=secondary
_DOTFILES_TEST_CURRENT_UID="${current_uid}"
resolve_dotfiles_role
assert_eq "secondary" "${DOTFILES_ROLE}" "explicit secondary should be preserved"

DOTFILES_ROLE=primary
_DOTFILES_TEST_CURRENT_UID="$((current_uid + 1))"
if resolve_dotfiles_role 2>/dev/null; then
  echo "FAIL: explicit primary should reject a foreign-owned prefix" >&2
  exit 1
fi

DOTFILES_ROLE=invalid
if resolve_dotfiles_role 2>/dev/null; then
  echo "FAIL: invalid role should be rejected" >&2
  exit 1
fi

echo "install_role_test: PASS"
