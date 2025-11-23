#!/bin/zsh
set -euo pipefail

echo "Setting up Mac..."
echo "OS Version: $(sw_vers -productVersion)"
echo "Architecture: $(uname -m)"

# working directory
DOTFILES_DIR="${HOME}/dotfiles"
cd "${DOTFILES_DIR}"

# Install Homebrew
if ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Apple Silicon
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  # Intel
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "Homebrew installation failed."
    exit 1
  fi
else
  echo "Homebrew already installed."
fi

# Install packages from Brewfile
if [ -f "${DOTFILES_DIR}/Brewfile" ]; then
  echo "Installing Homebrew packages from Brewfile..."
  brew bundle --file="${DOTFILES_DIR}/Brewfile"
fi

# Install rustup and cargo
if [ ! -d "${HOME}/.rustup" ]; then
  echo "Setting up rustup..."

  # Homebrew 由来の rustup-init があれば優先
  if command -v rustup-init >/dev/null 2>&1; then
    echo "Initializing rustup via rustup-init (Homebrew)..."
    rustup-init -y --no-modify-path --default-toolchain stable
  else
    echo "rustup-init not found, installing rustup from official installer..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --default-toolchain stable
  fi
else
  echo "rustup already initialized."
fi

if [ -f "${HOME}/.cargo/env" ]; then
  . "${HOME}/.cargo/env"
fi

# cargo install from cargo-tools.txt
if command -v cargo >/dev/null 2>&1 && [ -f "${DOTFILES_DIR}/cargo-tools.txt" ]; then
  echo "Installing cargo tools..."
  while IFS= read -r pkg; do
    case "$pkg" in
      ""|\#*) continue ;;  # 空行とコメント行(#...)をスキップ
    esac
    echo "  cargo install ${pkg}"
    cargo install "$pkg" || true
  done < "${DOTFILES_DIR}/cargo-tools.txt"
fi

# Create config directory
mkdir -p "${HOME}/.config"

# Create symlinks (idempotent)
ln -sf "${DOTFILES_DIR}/.zshrc"           "${HOME}/.zshrc"
ln -sf "${DOTFILES_DIR}/.aliases"         "${HOME}/.aliases"
ln -sf "${DOTFILES_DIR}/.zsh_profile"     "${HOME}/.zsh_profile"
ln -sf "${DOTFILES_DIR}/.tmux.conf"       "${HOME}/.tmux.conf"
ln -sf "${DOTFILES_DIR}/.gitconfig"       "${HOME}/.gitconfig"
ln -sf "${DOTFILES_DIR}/.config/nvim"      "${HOME}/.config/nvim"
ln -sf "${DOTFILES_DIR}/.config/alacritty" "${HOME}/.config/alacritty"
ln -sf "${DOTFILES_DIR}/.config/starship"  "${HOME}/.config/starship"

echo "Done."
