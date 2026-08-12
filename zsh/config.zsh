DOTFILES_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
DOTFILES_HISTORY_DIR="${DOTFILES_STATE_HOME}/zsh"

dotfiles_file_mode() {
  local file_path="$1"

  if stat -c %a -- "${file_path}" >/dev/null 2>&1; then
    stat -c %a -- "${file_path}"
  else
    stat -f %Lp -- "${file_path}"
  fi
}

dotfiles_disable_persistent_history() {
  print -ru2 -- "dotfiles: insecure history directory; disabling persistent zsh history for this session: ${DOTFILES_HISTORY_DIR}"
  HISTFILE=""
  HISTSIZE=0
  SAVEHIST=0
  unsetopt append_history
  unsetopt inc_append_history
  unsetopt share_history
  unsetopt extended_history
  unsetopt hist_ignore_all_dups
  unsetopt hist_reduce_blanks
}

if mkdir -p -m 700 "${DOTFILES_HISTORY_DIR}" && chmod 700 "${DOTFILES_HISTORY_DIR}" 2>/dev/null; then
  DOTFILES_HISTORY_MODE="$(dotfiles_file_mode "${DOTFILES_HISTORY_DIR}" 2>/dev/null)"
  if [[ "${DOTFILES_HISTORY_MODE}" = 700 && -O "${DOTFILES_HISTORY_DIR}" ]]; then
    HISTFILE="${DOTFILES_HISTORY_DIR}/history"
    HISTSIZE=10000
    SAVEHIST=10000

    setopt append_history
    setopt inc_append_history
    setopt share_history
    setopt extended_history
    setopt hist_verify
    setopt hist_ignore_all_dups
    setopt hist_reduce_blanks
  else
    dotfiles_disable_persistent_history
  fi
else
  dotfiles_disable_persistent_history
fi

setopt complete_aliases
setopt complete_in_word
setopt prompt_subst
setopt no_bg_nice
setopt no_hup
setopt no_list_beep
setopt local_options
setopt local_traps

export HISTFILE HISTSIZE SAVEHIST
unset DOTFILES_HISTORY_DIR DOTFILES_HISTORY_MODE
unfunction dotfiles_file_mode dotfiles_disable_persistent_history
