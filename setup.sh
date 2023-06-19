#! bin/sh
echo "setup dotfiles"
DOT_DIR="$HOME/dotfiles"
# git clone
cd $DOT_DIR

echo "install on $(uname -n)"
case $(uname -n) in
  "UbuntuonWSL2onG3")
    echo "make static link nvim config"
    ln -sf $HOME/dotfiles/.config/nvim/init.vim $HOME/.config/nvim/init.vim
    ln -sf $HOME/dotfiles/.config/nvim/dein.vim $HOME/.config/nvim/dein.vim
    ln -sf $HOME/dotfiles/.config/nvim/dein_lazy.toml $HOME/.config/nvim/dein_lazy.toml
    ;;
  *)
    ;;
esac
