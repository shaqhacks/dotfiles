DOTFILES_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
HISTFILE="${DOTFILES_STATE_HOME}/zsh/history"
HISTSIZE=10000
SAVEHIST=10000

mkdir -p -m 700 "${HISTFILE:h}"
chmod 700 "${HISTFILE:h}" 2>/dev/null || true

setopt append_history
setopt inc_append_history
setopt share_history
setopt extended_history
setopt hist_verify
setopt hist_ignore_all_dups
setopt hist_reduce_blanks
setopt complete_aliases
setopt complete_in_word
setopt prompt_subst
setopt no_bg_nice
setopt no_hup
setopt no_list_beep
setopt local_options
setopt local_traps

export HISTFILE HISTSIZE SAVEHIST
