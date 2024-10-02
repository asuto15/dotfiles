#! bin/bash
echo "Setting up dotfiles on $(uname -n)"
DOT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$DOT_DIR" ]; then
  echo "Dotfiles directory not found at $DOT_DIR"
  exit 1
fi

echo "Updating apt commands"
sudo apt -qq update && sudo apt -qq upgrade -y

cmds=(
  "git"
  "tmux"
  "fzf"
  "ripgrep"
  "bat"
  "eza"
  "tldr"
  "tree"
  "htop"
  "wget"
  "curl"
  "httpie"
  "jq"
)

missing_cmds=()
for cmd in "${cmds[@]}"; do
  if ! command -v $cmd &> /dev/null; then
    missing_cmds+=("$cmd")
  fi
done

if [ ${#missing_cmds[@]} -ne 0 ]; then
  echo "Installing missing commands: ${missing_cmds[*]}"
  sudo apt install -y -qq "${missing_cmds[@]}"
else
  echo "All commands are already installed."
fi

echo "Installing nvim"
if ! command -v nvim &> /dev/null; then
  sudo snap install -y nvim
fi

echo "Create symbolic links for configuration files"
[ "$(readlink $HOME/.bashrc)" != "$DOT_DIR/.bashrc" ] && ln -sf "$DOT_DIR/.bashrc" "$HOME/.bashrc"
[ "$(readlink $HOME/.aliases)" != "$DOT_DIR/.aliases" ] && ln -sf "$DOT_DIR/.aliases" "$HOME/.aliases"
mkdir -p "$HOME/.config/nvim"
[ "$(readlink $HOME/.config/nvim/init.vim)" != "$DOT_DIR/.config/nvim/init.vim" ] && ln -sf "$DOT_DIR/.config/nvim/init.vim" "$HOME/.config/nvim/init.vim"
[ "$(readlink $HOME/.config/nvim/dein.vim)" != "$DOT_DIR/.config/nvim/dein.vim" ] && ln -sf "$DOT_DIR/.config/nvim/dein.vim" "$HOME/.config/nvim/dein.vim"
[ "$(readlink $HOME/.config/nvim/dein_lazy.toml)" != "$DOT_DIR/.config/nvim/dein_lazy.toml" ] && ln -sf "$DOT_DIR/.config/nvim/dein_lazy.toml" "$HOME/.config/nvim/dein_lazy.toml"
[ "$(readlink $HOME/.tmux.conf)" != "$DOT_DIR/.tmux.conf" ] && ln -sf "$DOT_DIR/.tmux.conf" "$HOME/.tmux.conf"

echo "Installing rustup"
if ! command -v rustup &> /dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
fi

source $HOME/.bashrc
