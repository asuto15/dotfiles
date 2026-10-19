# macOS software selection

`./install.sh` run from a local checkout now selects macOS software by
component before it invokes Homebrew. It never applies the complete `Brewfile`
implicitly.

Running `./install.sh` without options in a macOS terminal first asks you to
choose a setup mode, before installing any prerequisites:

- `1` (also Enter): minimal setup, linking dotfiles only
- `2`: custom setup, followed by the component questions below

This also works with `curl ... | sh`: both the mode choice and subsequent
component questions read from the controlling terminal. `--minimal` skips
the questions. Explicit `DOTFILES_MINIMAL` or `DOTFILES_MACOS_COMPONENTS`
settings also skip the mode question. `DOTFILES_MACOS_INTERACTIVE=0`,
`NONINTERACTIVE=1`, `CI=1`, or a session without a controlling terminal skips
the mode question; noninteractive component selection keeps its saved/default
behavior. `NONINTERACTIVE=1` and `CI=1` also suppress component questions.

## Minimal setup for a company Mac

```sh
./install.sh --minimal
# Equivalent environment option (also works with scripts/install_local.sh):
DOTFILES_MINIMAL=1 ./install.sh
```

This links the dotfiles without installing or updating Homebrew, formulae,
casks, App Store apps, fonts, language toolchains, CLI tools, or editor
extensions. It takes precedence over saved selections, explicit component
lists, interactive prompts, and all legacy `INSTALL_*` flags. On macOS it
saves `none` as the next component selection. Existing software is retained.
Existing configuration files are backed up by the usual linking process.

The repository checkout and a working Git and Bash are still required (Git
also writes the local Git configuration wrapper). A remote bootstrap may clone
or update this repository. If Apple's Command Line Tools are missing, minimal
setup stops with instructions to run `xcode-select --install`; it does not
install Homebrew as a workaround. Tool-dependent aliases and configuration
remain present, but their associated programs are not installed.

For a piped bootstrap, pass the option to the shell executing the installer:

```sh
curl -fsSL https://raw.githubusercontent.com/asuto15/dotfiles/master/install.sh | sh -s -- --minimal
```

`core` includes many CLI utilities and `work` includes applications such as
Slack and Office; neither is a minimal preset. Use an explicit component list
when you want to install those groups. `DOTFILES_MACOS_COMPONENTS=none` remains
available, but unlike `--minimal`, legacy `INSTALL_*` flags can override it.

## Homebrew on a new Mac

When selected software needs Homebrew, setup runs the official installer as
the current user and uses `/dev/tty` for its authentication and confirmation
prompts, including with a piped bootstrap. Do not run the whole dotfiles
installer with `sudo`. The previous forced `NONINTERACTIVE=1` prevented sudo
authentication on a fresh Mac and could produce
`Insufficient permissions to install Homebrew to "/opt/homebrew"`.

Explicit `NONINTERACTIVE=1` or `CI=1`, and sessions without a controlling
terminal, retain noninteractive installation. In that case Homebrew must
already have the permissions it needs; run the setup in a terminal if it needs
administrator authentication. Download or installation failures stop setup.

## Component selection

In a terminal, the installer asks about each component in order. On a first
run, only `core` defaults to yes; every other component defaults to no. A
subsequent interactive run uses the preceding choices as its defaults.

The components are:

- `core`: common command-line tools such as Git, curl, ripgrep, and tmux
- `development`: language runtimes, compilers, and development tools
- `infrastructure`: containers, networking, server, and virtual-machine tools
- `editors`, `vscode`, and `vscode-extensions`: editor applications and the
  curated VS Code extension set
- `work`: work-oriented credentials, cloud storage, Slack, and Microsoft apps
- `personal`: personal Mac App Store applications and media tools
- `desktop`, `japanese`, and `fonts`: desktop utilities, input methods, and
  shared fonts
- `ai`, `rust-tools`, `rust-projects`, and `tailscale`: opt-in developer and
  network tooling

`vscode-extensions` selects `vscode` automatically, `rust-projects` selects
`rust-tools`, and either App Store application group installs the `mas` helper.
The remaining components are independent.

For unattended setup, set `DOTFILES_MACOS_COMPONENTS` to a comma-separated
list. `all` is an explicit full-machine selection; `none` links dotfiles
without invoking Homebrew:

```sh
DOTFILES_MACOS_COMPONENTS=core,development,vscode,work ./install.sh
DOTFILES_MACOS_COMPONENTS=none ./install.sh
DOTFILES_MACOS_COMPONENTS=all ./install.sh
```

With no TTY and no prior selection, the installer selects `none`. The chosen
public components are saved in `~/.config/dotfiles/macos-install.env`; override
that location for automation with `DOTFILES_MACOS_STATE_FILE`. Use
`DOTFILES_MACOS_INTERACTIVE=0` to suppress prompts explicitly.

The earlier component flags remain supported and override the matching item in
the component list: `INSTALL_AI_CLI`, `INSTALL_RUST_TOOLS`,
`INSTALL_RUST_PROJECTS`, `INSTALL_VSCODE_EXTENSIONS`, `INSTALL_FONTS`, and
`INSTALL_TAILSCALE`. Each accepts `0` or `1`.

For a managed company device, start with `DOTFILES_MACOS_COMPONENTS=none` or a
small explicit list and add components only after confirming the organisation's
software and device-management policy. In particular, `fonts` writes to the
shared `/Library/Fonts` location, and App Store, Homebrew service, VPN, or
device-management tools may require separate approval.
