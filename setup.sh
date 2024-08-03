#! bin/bash
echo "setup dotfiles"
DOT_DIR="$HOME/dotfiles"
# git clone
cd $DOT_DIR

echo "install on $(uname -n)"
case $(uname -s) in
  "Linux")
    echo "apt install commands"
    sudo apt update && sudo apt upgrade -y
    cmds=(
      "git"
      "tmux"
      "fzf"
      "ripgrep"
      "bat"
      "exa"
      "tldr"
      "tree"
      "htop"
      "wget"
      "curl"
      "httpie"
      "jq"
    )

    for cmd in "${cmds[@]}"; do
      if ! [[ $(command -v $cmd) ]]; then
        sudo apt install -y $cmd
      fi
    done

    if ! [[ $(command -v nvim) ]]; then
      sudo snap install -y nvim
    fi

    echo "make static link .bashrc"
    ln -sf $HOME/dotfiles/.bashrc $HOME/.bashrc
    ln -sf $HOME/dotfiles/.aliases $HOME/.aliases
    echo "make static link nvim config"
    mkdir -p $HOME/.config/nvim
    ln -sf $HOME/dotfiles/.config/nvim/init.vim $HOME/.config/nvim/init.vim
    ln -sf $HOME/dotfiles/.config/nvim/dein.vim $HOME/.config/nvim/dein.vim
    ln -sf $HOME/dotfiles/.config/nvim/dein_lazy.toml $HOME/.config/nvim/dein_lazy.toml
    echo "make static link tmux config"
    ln -sf $HOME/dotfiles/.tmux.conf $HOME/.tmux.conf

    echo "install rustup"
    if ! [[ $(command -v rustup) ]]; then
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    fi
    ;;
  *)
    ;;
esac

source $HOME/.bashrc
