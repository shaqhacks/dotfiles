export CLICOLOR=1
export LSCOLORS='exfxcxdxbxegedabagacad'

if (( ${+commands[gdircolors]} )); then
  eval "$(gdircolors -b 2>/dev/null)"
elif (( ${+commands[dircolors]} )); then
  eval "$(dircolors -b 2>/dev/null)"
fi

if (( ${+commands[gls]} )); then
  alias ls='gls -F --color=auto'
  alias l='gls -lAh --color=auto'
  alias ll='gls -l --color=auto'
  alias la='gls -A --color=auto'
elif [[ "$(uname -s 2>/dev/null)" = Darwin ]]; then
  alias ls='ls -FG'
  alias l='ls -lAhG'
  alias ll='ls -lG'
  alias la='ls -AG'
elif ls --color=auto >/dev/null 2>&1; then
  alias ls='ls -F --color=auto'
  alias l='ls -lAh --color=auto'
  alias ll='ls -l --color=auto'
  alias la='ls -A --color=auto'
fi
