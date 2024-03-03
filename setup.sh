#! bin/sh
echo "setup dotfiles"
DOT_DIR="$HOME/dotfiles"
# git clone
cd $DOT_DIR

echo "install on $(uname -n)"
case $(uname -s) in
  "Linux")
    echo "make static link .bashrc"
    ln -sf $HOME/dotfiles/.bashrc $HOME/.bashrc
    echo "make static link nvim config"
    mkdir -p $HOME/.config/nvim
    ln -sf $HOME/dotfiles/.config/nvim/init.vim $HOME/.config/nvim/init.vim
    ln -sf $HOME/dotfiles/.config/nvim/dein.vim $HOME/.config/nvim/dein.vim
    ln -sf $HOME/dotfiles/.config/nvim/dein_lazy.toml $HOME/.config/nvim/dein_lazy.toml
    echo "make static link tmux config"
    ln -sf $HOME/dotfiles/.tmux.conf $HOME/.tmux.conf
    ;;
  *)
    ;;
esac

source $HOME/.bashrc
