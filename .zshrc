autoload -U compinit
compinit

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

export PATH=/Users/asuto153/.anyenv/envs/nodenv/shims:/Users/asuto153/.anyenv/envs/nodenv/bin:/Library/Frameworks/Python.framework/Versions/3.12/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/opt/homebrew/opt:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/opt/X11/bin:/Users/asuto153/.cargo/bin:/Users/asuto153/.anyenv/envs/nodenv/versions/21.2.0/bin:/opt/homebrew/opt/ruby/bin:/usr/local/opt/llvm/bin
export LDFLAGS="-L/opt/homebrew/opt/llvm/lib"
export CPPFLAGS="-I/opt/homebrew/opt/llvm/include"
export GPG_TTY=$(tty)

export LIBRARY_PATH="$LIBRARY_PATH:/opt/homebrew/lib:/opt/homebrew/Cellar:/usr/local/lib"

export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"
export STARSHIP_CACHE="$HOME/.starship/cache"

eval "$(starship init zsh)"

. "$HOME/.local/bin/env"
source /Users/asuto153/.local/bin/env
