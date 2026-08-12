# shellcheck shell=sh
# shellcheck disable=SC1091,SC2016

COMMON_SH="${TEST_ROOT}/../script/common.sh"
LINKS_SH="${TEST_ROOT}/../script/links.sh"
ZSH_BIN="${ZSH_BIN:-zsh}"

load_config_helpers() {
  if [ ! -f "${COMMON_SH}" ]; then
    fail "missing common helpers: ${COMMON_SH}"
    return 1
  fi
  if [ ! -f "${LINKS_SH}" ]; then
    fail "missing link helpers: ${LINKS_SH}"
    return 1
  fi

  # shellcheck source=../script/common.sh
  . "${COMMON_SH}"
  # shellcheck source=../script/links.sh
  . "${LINKS_SH}"
}

config_repo_root() {
  CDPATH='' cd -P -- "${TEST_ROOT}/.." && pwd -P
}

collect_config_record() {
  printf '%s\n' "$*" >>"${TEST_TMPDIR}/callback-output"
}

git_config_value() {
  key="$1"
  git config --file "$(config_repo_root)/git/gitconfig.symlink" --get "${key}"
}

test_git_config_has_portable_defaults_and_local_include_without_identity() {
  repo_root="$(config_repo_root)" || return 1
  config_file="${repo_root}/git/gitconfig.symlink"

  git config --file "${config_file}" --list >/dev/null || return 1

  assert_eq "main" "$(git_config_value init.defaultBranch)" "default Git branch" || return 1
  assert_eq "auto" "$(git_config_value color.ui)" "Git color mode" || return 1
  assert_eq "true" "$(git_config_value fetch.prune)" "Git fetch pruning" || return 1
  assert_eq "only" "$(git_config_value pull.ff)" "Git pull mode" || return 1
  assert_eq "true" "$(git_config_value push.autoSetupRemote)" "Git push upstream setup" || return 1
  expected_include="~"'/.gitconfig.local'
  assert_eq "${expected_include}" "$(git_config_value include.path)" "local Git include" || return 1

  if git config --file "${config_file}" --get user.name >/dev/null 2>&1; then
    fail "tracked Git config must not set user.name"
    return 1
  fi
  if git config --file "${config_file}" --get user.email >/dev/null 2>&1; then
    fail "tracked Git config must not set user.email"
    return 1
  fi
}

test_powerlevel10k_config_exports_compact_prompt_segments() {
  repo_root="$(config_repo_root)" || return 1
  p10k_file="${repo_root}/powerlevel10k/p10k.zsh"

  output="$("${ZSH_BIN}" -df -c '
    source "$1"
    print -r -- ${(j:|:)POWERLEVEL9K_LEFT_PROMPT_ELEMENTS}
    print -r -- ${(j:|:)POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS}
    print -r -- "${POWERLEVEL9K_PROMPT_ON_NEWLINE}"
    print -r -- "${POWERLEVEL9K_CONTEXT}"
  ' zsh-test "${p10k_file}")" || return 1

  expected="$(printf '%s\n%s\n%s\n%s' \
    "context|dir|vcs|newline|prompt_char" \
    "status|command_execution_time|background_jobs|time" \
    "true" \
    "remote")"
  assert_eq "${expected}" "${output}" "Powerlevel10k prompt contract"
}

test_links_manifest_declares_application_topic_mappings() {
  load_config_helpers || return 1
  make_test_home
  repo_root="$(config_repo_root)" || return 1
  links_manifest="${repo_root}/manifest/links.conf"

  : >"${TEST_TMPDIR}/callback-output"
  manifest_each links "${links_manifest}" collect_config_record || return 1

  expected="$(printf '%s\n' \
    "zsh/zshrc.symlink .zshrc" \
    "git/gitconfig.symlink .gitconfig" \
    "kitty/kitty.conf .config/kitty/kitty.conf" \
    "powerlevel10k/p10k.zsh .p10k.zsh")"
  assert_eq "${expected}" "$(cat "${TEST_TMPDIR}/callback-output")" "application link records"
}

test_links_manifest_plans_first_installation_for_application_topics() {
  load_config_helpers || return 1
  make_test_home
  repo_root="$(config_repo_root)" || return 1
  links_manifest="${repo_root}/manifest/links.conf"

  plan_reset || return 1
  links_plan "${repo_root}" "${links_manifest}" || return 1

  expected="$(printf '%s\n' \
    "$(printf 'links\tlink\t.zshrc')" \
    "$(printf 'links\tlink\t.gitconfig')" \
    "$(printf 'links\tmkdir\t.config/kitty/kitty.conf')" \
    "$(printf 'links\tlink\t.config/kitty/kitty.conf')" \
    "$(printf 'links\tlink\t.p10k.zsh')")"
  assert_eq "${expected}" "$(plan_print)" "first install link plan"
}
