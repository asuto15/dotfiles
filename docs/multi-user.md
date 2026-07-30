# Multi-user setup

`install.sh` supports a primary package-management user and secondary users
that reuse machine-wide applications without mutating them.

## Roles

`DOTFILES_ROLE` accepts:

- `auto` (default): on macOS, use `primary` when the current user owns the
  Homebrew prefix and `secondary` when another user owns it.
- `primary`: install and update Homebrew packages, casks, Mac App Store apps,
  services, and user-scoped tools.
- `secondary`: never install, update, upgrade, trust, or start Homebrew-managed
  software. Reuse the existing Homebrew binaries and install only user-scoped
  tools and configuration.

An explicit `primary` setup refuses to continue when the Homebrew prefix is
owned by another user. This prevents the Homebrew installer or package manager
from transferring or mixing ownership accidentally.

## macOS secondary setup

Create the additional macOS Administrator user, sign in as that user, and run:

```sh
git clone https://github.com/asuto15/dotfiles.git "$HOME/dotfiles"
cd "$HOME/dotfiles"
./install.sh
```

The installer detects `/opt/homebrew/bin/brew` even when it is not on the new
user's initial `PATH`. It does not rerun the Homebrew installer.

The secondary setup installs these items under the new user's home directory:

- dotfile symlinks and a real `~/.gitconfig` wrapper
- npm global CLI packages under `~/.npm-global`
- rustup state under `~/.rustup`
- Cargo tools under `~/.cargo/bin`
- source checkouts under `~/.local/src`
- VS Code extensions under `~/.vscode/extensions`

The tracked `dotfiles/.gitconfig` remains the shared Git configuration, including
the same `user.name` and `user.email` for both roles. The installer no longer
symlinks it directly. Instead, each user's real `~/.gitconfig` includes the
tracked file and `~/.gitconfig.local`. Commands such as `gh auth setup-git` and
`git config --global` therefore write credential helpers only to that user's
wrapper, not back into the repository.

Applications in `/Applications` and formula binaries under `/opt/homebrew` are
reused. Homebrew font casks are installed once under `/Library/Fonts`, so their
files are also shared. Homebrew services are not started for secondary users.

The secondary role requires the dotfiles checkout itself to be below that
user's home directory. It also overrides Cargo, rustup, npm, XDG, Homebrew cache,
and VS Code extension locations for the installer process so every duplicated
binary, package, checkout, extension, and persistent installer cache stays below
that home directory. The resolved locations are recorded in
`~/.local/state/dotfiles/secondary-install-paths`.

Authentication and signing credentials are intentionally not copied between
macOS users. After installation, run `gh auth login` and `gh auth setup-git` as
the secondary user. The shared Git configuration enables `commit.gpgsign`, so
also provision that user's GPG secret key or override the setting in
`~/.gitconfig.local`.

Before setting up the first secondary user, rerun `./install.sh` once as the
primary Homebrew owner. Existing font casks installed in the primary user's
`~/Library/Fonts` are reinstalled into `/Library/Fonts`, and future font-cask
installs through this Brewfile use the shared directory. The secondary installer
verifies that these font files exist, but does not reinstall or copy them.

## Optional secondary components

Set any of these to `0` to skip the corresponding user-scoped step:

```sh
INSTALL_AI_CLI=0
INSTALL_RUST_TOOLS=0
INSTALL_RUST_PROJECTS=0
INSTALL_VSCODE_EXTENSIONS=0
INSTALL_FONTS=0
```

For example, to link only the dotfiles while reusing existing machine
applications:

```sh
DOTFILES_ROLE=secondary \
INSTALL_AI_CLI=0 \
INSTALL_RUST_TOOLS=0 \
INSTALL_RUST_PROJECTS=0 \
INSTALL_VSCODE_EXTENSIONS=0 \
INSTALL_FONTS=0 \
./install.sh
```

## Removing a secondary macOS user

Log out the secondary user, then delete it from System Settings > Users &
Groups. Select **Delete the home folder**. That removes the dotfiles checkout,
user-scoped npm/Rust/Cargo installations, VS Code extensions, configuration,
application data, and persistent caches installed for that user.

Do not select **Save the home folder in a disk image** or **Don't change the home
folder** when the goal is to reclaim the duplicated storage. Those choices
deliberately retain the user's files.

The shared Homebrew prefix, applications in `/Applications`, and fonts in
`/Library/Fonts` remain because they are the primary user's machine-wide
installation, not secondary-user duplicates.

## Security boundary

This is an ownership-safe bootstrap policy, not a security boundary between
Administrator users. Homebrew does not officially support multiple users
mutating one installation. Only the primary user should run `brew install`,
`brew update`, `brew upgrade`, `brew bundle`, or `brew services`.
