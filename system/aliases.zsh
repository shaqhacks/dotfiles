if (( ${+commands[git]} )); then
  alias gs='git status -sb'
  alias gl='git pull --prune'
  alias gp='git push origin HEAD'
  alias gd='git diff'
  alias gc='git commit'
  alias gco='git checkout'
  alias gb='git branch'
fi

alias cls='clear'
alias reload!='source ~/.zshrc'

autoload -Uz zmv
alias mmv='noglob zmv -W'
