#! bin/zsh
echo "Setting up Mac..."

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Homebrew packages
brew install git
brew install zsh
brew install tmux
brew install neovim
brew install starship
brew install anyenv

# Install CLI tools
brew install fzf
brew install fd
brew install ripgrep
brew install bat
brew install eza
brew install tldr
brew install tree
brew install htop
brew install wget
brew install curl
brew install httpie
brew install jq
brew install z

# Install Homebrew casks
brew install --cask visual-studio-code
brew install --cask google-chrome
brew install --cask clipy
brew install --cask rectangle

# Create symlinks
ln -s ~/dotfiles/.zshrc ~/.zshrc
ln -s ~/dotfiles/.aliases ~/.aliases
ln -s ~/dotfiles/.zsh_profile ~/.zsh_profile
ln -s ~/dotfiles/.tmux.conf ~/.tmux.conf
ln -s ~/dotfiles/.config/nvim ~/.config/nvim
ln -s ~/dotfiles/.config/alacritty ~/.config/alacritty
ln -s ~/dotfiles/.config/starship ~/.config/starship


