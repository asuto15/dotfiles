autoload -U compinit
compinit

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${(%):-%N}")" && pwd)}"
[ -f "${DOTFILES_DIR}/shell/common_env.sh" ] && source "${DOTFILES_DIR}/shell/common_env.sh"
[ -f "${DOTFILES_DIR}/shell/local_env.sh" ] && source "${DOTFILES_DIR}/shell/local_env.sh"

_ssh_hosts() {
  setopt localoptions nullglob
  local -a compHosts files
  local config="$HOME/.ssh/config"
  local includes=($(awk '/^Include / {print $2}' $config))

  for i in $includes; do
    if [[ $i == /* ]]; then
      files+=($~i)
    else
      files+=(~/.ssh/$~i)
    fi
  done
  files+=($config)

  compHosts=($(awk '/^Host / && $2 != "*" { if (!seen[$2]++) print $2 }' ${files[@]} ))
  _wanted hosts expl host compadd -a compHosts
}

compdef _ssh_hosts ssh

if [ -f ~/.aliases ]; then
  source ~/.aliases
fi

if command -v starship >/dev/null 2>&1; then
  export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"
  eval "$(starship init zsh)"
fi

if command -v anyenv >/dev/null 2>&1; then
  eval "$(anyenv init -)"
fi

if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --zsh)"
  [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
  export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
fi
