ZSH_BIN="${ZSH_BIN:-zsh}"

zsh_repo_root() {
  CDPATH= cd -P -- "${TEST_ROOT}/.." && pwd -P
}

copy_zsh_repo_with_spaces() {
  source_repo="$(zsh_repo_root)" || return 1
  ZSH_TEST_REPO="${TEST_TMPDIR}/repo with spaces"
  mkdir -p "${ZSH_TEST_REPO}" || return 1
  ZSH_TEST_REPO="$(CDPATH= cd -P -- "${ZSH_TEST_REPO}" && pwd -P)" || return 1
  (
    cd "${source_repo}" || exit 1
    tar -cf - zsh system 2>/dev/null
  ) | (
    cd "${ZSH_TEST_REPO}" || exit 1
    tar -xf -
  )
  export ZSH_TEST_REPO
}

prepare_zsh_home() {
  make_test_home || return 1
  copy_zsh_repo_with_spaces || return 1
  mkdir -p "${HOME}" "${XDG_DATA_HOME}/dotfiles/plugins" "${XDG_CONFIG_HOME}" || return 1
  ln -s "${ZSH_TEST_REPO}/zsh/zshrc.symlink" "${HOME}/.zshrc" || return 1
}

write_plugin_marker() {
  plugin_name="$1"
  entrypoint="$2"
  marker="$3"
  plugin_dir="${XDG_DATA_HOME}/dotfiles/plugins/${plugin_name}"

  mkdir -p "${plugin_dir}" || return 1
  printf '%s\n' "print -r -- ${marker} >> \"\${DOTFILES_ZSH_LOAD_TRACE}\"" >"${plugin_dir}/${entrypoint}"
}

run_login_zsh() {
  DOTFILES_ZSH_LOAD_TRACE="${TEST_TMPDIR}/load-trace"
  export DOTFILES_ZSH_LOAD_TRACE
  : >"${DOTFILES_ZSH_LOAD_TRACE}"

  HOME="${HOME}" \
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" \
    XDG_DATA_HOME="${XDG_DATA_HOME}" \
    XDG_STATE_HOME="${XDG_STATE_HOME}" \
    XDG_CACHE_HOME="${XDG_CACHE_HOME:-}" \
    DOTFILES_ZSH_LOAD_TRACE="${DOTFILES_ZSH_LOAD_TRACE}" \
    DOTFILES_FZF_ZSH_FALLBACKS="${DOTFILES_FZF_ZSH_FALLBACKS:-}" \
    PATH="${PATH}" \
    "${ZSH_BIN}" -df -c 'source "$HOME/.zshrc"; eval "$1"' zsh-test "$1"
}

test_zsh_fragments_parse_with_zsh() {
  repo="$(zsh_repo_root)" || return 1

  "${ZSH_BIN}" -n \
    "${repo}/zsh/path.zsh" \
    "${repo}/zsh/config.zsh" \
    "${repo}/zsh/keybindings.zsh" \
    "${repo}/zsh/completion.zsh" \
    "${repo}/zsh/zshrc.symlink" \
    "${repo}/system/aliases.zsh" \
    "${repo}/system/colors.zsh"
}

test_zshrc_resolves_repo_from_symlink_target_with_spaces() {
  prepare_zsh_home || return 1

  actual="$(run_login_zsh 'print -r -- "$DOTFILES_REPO"')" || return 1
  assert_eq "${ZSH_TEST_REPO}" "${actual}" "repo resolved from symlink target"
}

test_zsh_load_order_keeps_syntax_highlighting_last_after_local_override() {
  prepare_zsh_home || return 1
  cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}"
  mkdir -p "${cache_dir}" || return 1
  printf '%s\n' 'print -r -- instant >> "${DOTFILES_ZSH_LOAD_TRACE}"' >"${cache_dir}/p10k-instant-prompt-${USER:-user}.zsh"
  printf '%s\n' 'print -r -- local >> "${DOTFILES_ZSH_LOAD_TRACE}"' >"${HOME}/.zshrc.local"
  mkdir -p "${ZSH_TEST_REPO}/powerlevel10k" || return 1
  printf '%s\n' 'print -r -- p10k-config >> "${DOTFILES_ZSH_LOAD_TRACE}"' >"${ZSH_TEST_REPO}/powerlevel10k/p10k.zsh"
  write_plugin_marker powerlevel10k powerlevel10k.zsh-theme p10k-theme || return 1
  write_plugin_marker zsh-autosuggestions zsh-autosuggestions.zsh autosuggestions || return 1
  write_plugin_marker zsh-syntax-highlighting zsh-syntax-highlighting.zsh syntax || return 1

  run_login_zsh ':' >/dev/null || return 1

  expected="$(printf '%s\n' \
    instant \
    path \
    config \
    aliases \
    colors \
    keybindings \
    completion \
    p10k-theme \
    p10k-config \
    autosuggestions \
    local \
    syntax)"
  assert_eq "${expected}" "$(cat "${DOTFILES_ZSH_LOAD_TRACE}")" "load order trace"
}

test_zsh_missing_optional_plugins_and_tools_still_loads() {
  prepare_zsh_home || return 1

  output="$(PATH="/usr/bin:/bin" run_login_zsh 'print -r -- "$HISTFILE"')" || return 1
  assert_eq "${XDG_STATE_HOME}/zsh/history" "${output}" "history remains available without optional tools"
}

test_zsh_path_setup_is_duplicate_free_and_portable() {
  prepare_zsh_home || return 1
  mkdir -p "${HOME}/.local/bin" "${HOME}/bin" || return 1

  output="$(PATH="/usr/bin:/bin:/usr/bin" run_login_zsh 'print -r -- ${(j:|:)path}')" || return 1
  expected="${HOME}/.local/bin|${HOME}/bin|/opt/homebrew/bin|/usr/local/bin|/usr/local/sbin|/usr/bin|/bin"
  assert_eq "${expected}" "${output}" "deduplicated path order"
}

test_zsh_history_parent_is_secure_xdg_state_directory() {
  prepare_zsh_home || return 1

  output="$(run_login_zsh 'print -r -- "$HISTFILE"; print -r -- ${options[appendhistory]}:${options[sharehistory]}:${options[histignorealldups]}:${options[histreduceblanks]}:${options[extendedhistory]}; print -r -- "$(stat -f %Lp -- "${HISTFILE:h}")"')" || return 1
  expected="$(printf '%s\n%s\n%s' "${XDG_STATE_HOME}/zsh/history" "on:on:on:on:on" "700")"
  assert_eq "${expected}" "${output}" "history file, options, and parent mode"
}

test_zsh_completion_uses_xdg_cache_location() {
  prepare_zsh_home || return 1
  XDG_CACHE_HOME="${HOME}/cache with spaces"
  export XDG_CACHE_HOME

  output="$(run_login_zsh 'print -r -- "$DOTFILES_ZSH_COMPDUMP"; print -r -- ${options[completeinword]}; zstyle -s ":completion:*" matcher-list matcher; print -r -- "$matcher"')" || return 1
  expected="$(printf '%s\n%s\n%s' "${XDG_CACHE_HOME}/zsh/zcompdump" "on" "m:{a-z}={A-Z}")"
  assert_eq "${expected}" "${output}" "completion cache and matching"
  assert_file "${XDG_CACHE_HOME}/zsh/zcompdump"
}

test_zsh_fzf_uses_modern_zsh_integration_when_available() {
  prepare_zsh_home || return 1
  fake_bin="${TEST_TMPDIR}/fake-bin"
  mkdir -p "${fake_bin}" || return 1
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [ "$1" = "--zsh" ]; then' \
    '  printf "%s\n" "print -r -- fzf-modern >> \"\${DOTFILES_ZSH_LOAD_TRACE}\""' \
    'fi' >"${fake_bin}/fzf"
  chmod +x "${fake_bin}/fzf"

  PATH="${fake_bin}:${PATH}" run_login_zsh ':' >/dev/null || return 1
  assert_contains "${DOTFILES_ZSH_LOAD_TRACE}" "fzf-modern"
}

test_zsh_fzf_uses_distro_fallback_files_without_modern_output() {
  prepare_zsh_home || return 1
  fake_bin="${TEST_TMPDIR}/fake-bin"
  fallback_root="${TEST_TMPDIR}/fzf distro"
  mkdir -p "${fake_bin}" "${fallback_root}" || return 1
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${fake_bin}/fzf"
  chmod +x "${fake_bin}/fzf"
  printf '%s\n' 'print -r -- fzf-fallback >> "${DOTFILES_ZSH_LOAD_TRACE}"' >"${fallback_root}/key-bindings.zsh"

  DOTFILES_FZF_ZSH_FALLBACKS="${fallback_root}/key-bindings.zsh"
  export DOTFILES_FZF_ZSH_FALLBACKS
  PATH="${fake_bin}:${PATH}" run_login_zsh ':' >/dev/null || return 1
  assert_contains "${DOTFILES_ZSH_LOAD_TRACE}" "fzf-fallback"
}

test_zsh_aliases_are_guarded_by_available_commands() {
  prepare_zsh_home || return 1
  fake_bin="${TEST_TMPDIR}/fake-bin"
  mkdir -p "${fake_bin}" || return 1
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${fake_bin}/git"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${fake_bin}/gls"
  chmod +x "${fake_bin}/git" "${fake_bin}/gls"

  output="$(PATH="${fake_bin}:/usr/bin:/bin" run_login_zsh 'alias gs l ll la; print -r -- ${aliases[cls]-missing}; print -r -- ${aliases[pubkey]-missing}')" || return 1
  case "${output}" in
    *"gs='git status -sb'"* ) ;;
    *) fail "missing guarded git alias: ${output}" ;;
  esac
  case "${output}" in
    *"l='gls -lAh --color=auto'"* ) ;;
    *) fail "missing guarded GNU ls alias: ${output}" ;;
  esac
  case "${output}" in
    *"clear"*"missing"*) ;;
    *) fail "unguarded or personal aliases leaked: ${output}" ;;
  esac
}
