if [ -f ~/.aliases ]; then
  source ~/.aliases
fi

export LIBRARY_PATH="$LIBRARY_PATH:/opt/homebrew/Cellar:/usr/local/lib"

export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"
export STARSHIP_CACHE="$HOME/.starship/cache"

eval "$(starship init zsh)"
