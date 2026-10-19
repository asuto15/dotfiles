#!/usr/bin/env python3
"""Exercise both bootstrap paths with fake downloads and a real controlling TTY.

No sudo, network, package installation, or changes to the user's home occur.
Temporary fixtures are retained for inspection.
"""

import errno
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import time


REPO = Path(__file__).resolve().parents[1]
ROOT = Path(tempfile.mkdtemp(prefix="dotfiles-bootstrap-test-"))
ENV = os.environ.copy()
for key in list(ENV):
    if key.startswith(("DOTFILES_", "INSTALL_")) or key in (
        "CI", "NONINTERACTIVE", "INTERACTIVE", "BASH_ENV", "ENV"
    ):
        ENV.pop(key)

# Keep the standalone bootstrap's definitions without executing its entrypoint.
bootstrap = ROOT / "bootstrap-functions.sh"
def hide_installed_homebrew(source):
    # Redirect only the fixed filesystem probes to nonexistent fixture paths.
    return source.replace("/opt/homebrew/bin/brew", str(ROOT / "missing-arm-brew")).replace(
        "/usr/local/bin/brew", str(ROOT / "missing-intel-brew")
    )


bootstrap.write_text(hide_installed_homebrew(
    (REPO / "install.sh").read_text().split('LOCAL_DOTFILES_DIR=""')[0]))
packages = ROOT / "pkg_macos.sh"
packages.write_text(hide_installed_homebrew((REPO / "scripts/pkg_macos.sh").read_text()))
harness = ROOT / "homebrew-harness.sh"
harness.write_text(r'''
set -eu
source_file="$1"
scenario="$2"
set --
. "$source_file"
# Hide the real Homebrew, including its absolute fallback paths.
command() {
  if [ "$*" = '-v brew' ]; then return 1; fi
  builtin command "$@"
}
curl() {
  echo DOWNLOAD >&2
  if [ "$scenario" = download-failure ]; then return 22; fi
  cat <<'INSTALLER'
echo "INSTALLER mode=${NONINTERACTIVE:-interactive}"
if [ -t 0 ]; then echo 'INPUT=tty'; else echo 'INPUT=pipe'; fi
if [ -z "${NONINTERACTIVE:-}" ]; then
  echo PASSWORD_PROMPT
  read -r answer
  [ "$answer" = test-password ] || exit 38
  echo AUTHENTICATED
fi
# Deliberately fail before shellenv: no real Homebrew is ever installed.
exit 37
INSTALLER
}
case "$scenario" in
  secondary) DOTFILES_ROLE=secondary ;;
  noninteractive) export NONINTERACTIVE=1 ;;
  ci) export CI=1 ;;
esac
ensure_homebrew
echo UNEXPECTED_SUCCESS
''')


def run_pty(argv, *, piped_stdin=False, env=None, exchanges=None):
    if exchanges is None:
        exchanges = [(b"PASSWORD_PROMPT", b"test-password\n")]
    pid, master = pty.fork()
    if pid == 0:
        if piped_stdin:
            read_fd, write_fd = os.pipe()
            os.close(write_fd)
            os.dup2(read_fd, 0)
            os.close(read_fd)
        os.execve(argv[0], argv, ENV if env is None else env)
    output = b""
    next_exchange = 0
    search_offset = 0
    deadline = time.monotonic() + 10
    try:
        while time.monotonic() < deadline:
            if not select.select([master], [], [], 0.1)[0]:
                continue
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            output += chunk
            while next_exchange < len(exchanges):
                prompt, answer = exchanges[next_exchange]
                position = output.find(prompt, search_offset)
                if position < 0:
                    break
                os.write(master, answer)
                search_offset = position + len(prompt)
                next_exchange += 1
        else:
            os.kill(pid, 9)
            raise AssertionError(f"TTY test timed out: {output!r}")
    finally:
        os.close(master)
        _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status), output.decode()


for shell, source in (("/bin/sh", bootstrap), ("/bin/bash", packages)):
    for scenario, tty, piped in (
        ("interactive", True, False),
        ("interactive", True, True),
        ("noninteractive", True, False),
        ("ci", True, False),
        ("no-tty", False, False),
        ("download-failure", False, False),
        ("secondary", False, False),
    ):
        argv = [shell, str(harness), str(source), scenario]
        if tty:
            status, output = run_pty(argv, piped_stdin=piped)
        else:
            result = subprocess.run(argv, env=ENV, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, start_new_session=True, timeout=10)
            status, output = result.returncode, result.stdout
        assert status != 0 and "UNEXPECTED_SUCCESS" not in output, output
        if scenario in ("download-failure", "secondary"):
            assert "INSTALLER mode=" not in output, output
            if scenario == "secondary":
                assert "DOWNLOAD" not in output, output
        elif scenario == "interactive":
            assert "INSTALLER mode=interactive" in output, output
            assert "INPUT=tty" in output and "AUTHENTICATED" in output, output
        else:
            assert "INSTALLER mode=1" in output, output
            assert "PASSWORD_PROMPT" not in output, output
        print(f"PASS: {shell} {source.name} {scenario} piped={piped}")

# Missing Git must stop the minimal remote bootstrap before Homebrew or clone.
missing_git = ROOT / "missing-git.sh"
missing_git.write_text(f'. "{bootstrap}"\n' + '''
DOTFILES_MINIMAL=1
git_available() { return 1; }
ensure_homebrew() { echo UNEXPECTED_HOMEBREW; exit 99; }
install_prerequisites
echo UNEXPECTED_SUCCESS
''')
result = subprocess.run(["/bin/sh", str(missing_git)], env=ENV, capture_output=True, text=True)
assert result.returncode != 0 and "UNEXPECTED" not in result.stdout, result
assert "no software was installed" in result.stderr, result
print("PASS: minimal bootstrap refuses missing Git without installing software")

# A macOS Git placeholder must not count as installed Git or launch its UI.
git_placeholder = ROOT / "git-placeholder.sh"
git_placeholder.write_text(f'. "{bootstrap}"\n' + '''
command() {
  if [ "$*" = '-v git' ]; then echo /usr/bin/git; return 0; fi
  builtin command "$@"
}
uname() { echo Darwin; }
xcode-select() { return 1; }
git() { echo UNEXPECTED_GIT_LAUNCH; return 0; }
git_available
''')
result = subprocess.run(["/bin/sh", str(git_placeholder)], env=ENV,
                        capture_output=True, text=True)
assert result.returncode != 0 and "UNEXPECTED" not in result.stdout, result
print("PASS: missing Command Line Tools detected without launching the Git placeholder")

# Catch invalid options before they can trigger installation or linking.
for argv, extra_env, expected_status in (
    (["--help"], {}, 0),
    (["--unknown"], {}, 1),
    ([], {"DOTFILES_MINIMAL": "invalid"}, 1),
):
    result = subprocess.run(["/bin/sh", str(REPO / "install.sh"), *argv],
                            env=ENV | extra_env, capture_output=True, text=True)
    assert result.returncode == expected_status, result
    assert "Setting up dotfiles" not in result.stdout, result
print("PASS: help, unknown options, and invalid minimal setting have no install side effects")

# Full local entrypoint, using a disposable home and an observable fake brew.
fake_bin = ROOT / "bin"
fake_bin.mkdir()
brew_calls = ROOT / "brew-calls"
brew = fake_bin / "brew"
brew.write_text(f'''#!/bin/sh
printf '%s\\n' "$*" >> "{brew_calls}"
if [ "$*" = --prefix ]; then printf '%s\\n' "{ROOT}"; exit 0; fi
echo 'Unexpected brew mutation' >&2
exit 99
''')
brew.chmod(0o755)
test_home = ROOT / "home"
test_home.mkdir()
(test_home / ".zshrc").write_text("existing user settings\n")
minimal_env = ENV | {
    "HOME": str(test_home),
    "PATH": f"{fake_bin}:/usr/bin:/bin:/usr/sbin:/sbin",
    "DOTFILES_MACOS_STATE_FILE": str(ROOT / "selection.env"),
    "DOTFILES_MACOS_COMPONENTS": "all",
    "INSTALL_AI_CLI": "1",
    "INSTALL_TAILSCALE": "1",
}
result = subprocess.run(["/bin/sh", str(REPO / "install.sh"), "--minimal"],
                        env=minimal_env, capture_output=True, text=True, timeout=15)
assert result.returncode == 0, result.stdout + result.stderr
assert (test_home / ".zshrc").is_symlink()
assert any(p.read_text() == "existing user settings\n"
           for p in test_home.glob(".zshrc.backup.*"))
assert (test_home / ".gitconfig").is_file()
assert not brew_calls.exists() or set(brew_calls.read_text().splitlines()) <= {"--prefix"}
assert (ROOT / "selection.env").read_text() == "MACOS_COMPONENTS=none\n"
print("PASS: --minimal links settings, preserves existing files, and never installs software")

# No-argument setup must offer the mode choice in both local and remote paths.
mode_env = minimal_env.copy()
for key in ("DOTFILES_MACOS_COMPONENTS", "INSTALL_AI_CLI", "INSTALL_TAILSCALE"):
    mode_env.pop(key)
for remote in (False, True):
    run_env = mode_env.copy()
    if remote:
        run_env.update(DOTFILES_BOOTSTRAP="1", DOTFILES_DIR=str(REPO), DOTFILES_UPDATE="0")
    status, output = run_pty(
        ["/bin/sh", str(REPO / "install.sh")], piped_stdin=remote, env=run_env,
        exchanges=[(b"Setup mode [", b"invalid\n\n")],
    )
    assert status == 0, output
    assert "Please enter 1 or 2." in output and "Minimal setup:" in output, output
    assert output.count("Choose a setup mode:") == 1, output
    assert "Install core command-line tools?" not in output, output
    print(f"PASS: no-argument setup offers minimal by default (remote={remote})")

    # Reuse the saved 'none' defaults and decline each software component.
    status, output = run_pty(
        ["/bin/sh", str(REPO / "install.sh")], piped_stdin=remote, env=run_env,
        exchanges=[(b"Setup mode [", b"2\n")] + [(b"Install ", b"n\n")] * 15,
    )
    assert status == 0, output
    assert "Install core command-line tools?" in output, output
    assert "No macOS software components selected" in output, output
    print(f"PASS: custom mode asks for components, including with piped stdin (remote={remote})")

for setting in (
    {"DOTFILES_MINIMAL": "1"},
    {"DOTFILES_MACOS_COMPONENTS": "none"},
    {"DOTFILES_MACOS_INTERACTIVE": "0"},
    {"CI": "1"},
    {"NONINTERACTIVE": "1"},
):
    status, output = run_pty(["/bin/sh", str(REPO / "install.sh")],
                             env=mode_env | setting, exchanges=[])
    assert status == 0 and "Choose a setup mode:" not in output, output
    assert "Install core command-line tools?" not in output, output
print("PASS: explicit environment selections and noninteractive settings suppress questions")

result = subprocess.run(["/bin/sh", str(REPO / "install.sh")], env=mode_env,
                        stdin=subprocess.DEVNULL, capture_output=True, text=True,
                        start_new_session=True, timeout=15)
assert result.returncode == 0 and "Choose a setup mode:" not in result.stdout, result
assert not brew_calls.exists() or set(brew_calls.read_text().splitlines()) <= {"--prefix"}
print("PASS: no terminal uses the saved selection without waiting or installing software")
print(f"homebrew_bootstrap_test: PASS (fixtures: {ROOT})")
