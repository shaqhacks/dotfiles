autoload -Uz compinit

DOTFILES_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
DOTFILES_ZSH_COMPDUMP="${DOTFILES_CACHE_HOME}/zsh/zcompdump"
mkdir -p "${DOTFILES_ZSH_COMPDUMP:h}"
compinit -i -d "${DOTFILES_ZSH_COMPDUMP}"

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' insert-tab pending

dotfiles_source_fzf_fallbacks() {
  local fallback
  local -a fallback_files

  if [[ -n "${DOTFILES_FZF_ZSH_FALLBACKS:-}" ]]; then
    fallback_files=("${DOTFILES_FZF_ZSH_FALLBACKS}")
  else
    fallback_files=(
      /opt/homebrew/opt/fzf/shell/key-bindings.zsh
      /usr/share/doc/fzf/examples/key-bindings.zsh
      /usr/share/fzf/key-bindings.zsh
    )
  fi

  for fallback in "${fallback_files[@]}"; do
    if [[ -r "${fallback}" ]]; then
      source "${fallback}"
      return 0
    fi
  done
}

if (( ${+commands[fzf]} )); then
  DOTFILES_FZF_ZSH_SOURCE="$(fzf --zsh 2>/dev/null)"
  if [[ -n "${DOTFILES_FZF_ZSH_SOURCE}" ]]; then
    source <(print -r -- "${DOTFILES_FZF_ZSH_SOURCE}")
  else
    dotfiles_source_fzf_fallbacks
  fi
  unset DOTFILES_FZF_ZSH_SOURCE
fi

unfunction dotfiles_source_fzf_fallbacks
export DOTFILES_ZSH_COMPDUMP
