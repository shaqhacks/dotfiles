typeset -gU path PATH

path=(
  "${HOME}/.local/bin"
  "${HOME}/bin"
  /opt/homebrew/bin
  /usr/local/bin
  /usr/local/sbin
  ${path}
)

export PATH
