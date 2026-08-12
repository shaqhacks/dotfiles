# shellcheck shell=bash

COMMON_SH="${TEST_ROOT}/../script/common.sh"
LINKS_SH="${TEST_ROOT}/../script/links.sh"

assert_fails() {
  if (
    "$@"
  ) >/dev/null 2>&1; then
    fail "expected command to fail: $*"
    return 1
  fi
}

load_links() {
  if [ ! -f "${COMMON_SH}" ]; then
    fail "missing common helpers: ${COMMON_SH}"
    return 1
  fi
  if [ ! -f "${LINKS_SH}" ]; then
    fail "missing link helpers: ${LINKS_SH}"
    return 1
  fi

  # shellcheck source=../script/common.sh
  # shellcheck disable=SC1091
  . "${COMMON_SH}"
  # shellcheck source=../script/links.sh
  # shellcheck disable=SC1091
  . "${LINKS_SH}"
}

write_file() {
  path="$1"
  shift

  mkdir -p "$(dirname -- "${path}")" || return 1
  : >"${path}" || return 1
  for line in "$@"; do
    printf '%s\n' "${line}" >>"${path}" || return 1
  done
}

make_links_repo() {
  repo_root="${TEST_TMPDIR}/repo with spaces"
  mkdir -p "${repo_root}/manifest" "${repo_root}/zsh" "${repo_root}/git" "${repo_root}/kitty configs" || return 1
  printf 'zsh config\n' >"${repo_root}/zsh/zshrc.symlink" || return 1
  printf 'git config\n' >"${repo_root}/git/gitconfig.symlink" || return 1
  printf 'kitty config\n' >"${repo_root}/kitty configs/kitty.conf" || return 1
  links_manifest="${repo_root}/manifest/links.conf"
}

apply_links() {
  backup_root="${TEST_TMPDIR}/backup root"
  journal="${TEST_TMPDIR}/links journal"
  links_apply "${repo_root}" "${links_manifest}" "${backup_root}" "${journal}"
}

source_path() {
  rel="$1"
  printf '%s/%s' "$(CDPATH='' cd -P -- "${repo_root}" && pwd -P)" "${rel}"
}

home_path() {
  rel="$1"
  printf '%s/%s' "$(CDPATH='' cd -P -- "${HOME}" && pwd -P)" "${rel}"
}

test_links_plan_reports_first_installation_actions_without_mutation() {
  load_links || return 1
  make_test_home
  make_links_repo || return 1
  write_file "${links_manifest}" 'zsh/zshrc.symlink|.zshrc'

  plan_reset || return 1
  links_plan "${repo_root}" "${links_manifest}" || return 1

  assert_eq "$(printf 'links\tlink\t.zshrc')" "$(plan_print)" "first install plan"
  if [ -e "${HOME}/.zshrc" ]; then
    fail "links_plan mutated HOME"
  fi
}

test_links_plan_reports_noop_for_already_correct_link() {
  load_links || return 1
  make_test_home
  make_links_repo || return 1
  write_file "${links_manifest}" 'zsh/zshrc.symlink|.zshrc'
  ln -s "$(source_path 'zsh/zshrc.symlink')" "${HOME}/.zshrc" || return 1

  plan_reset || return 1
  links_plan "${repo_root}" "${links_manifest}" || return 1

  assert_eq "$(printf 'links\tnoop\t.zshrc')" "$(plan_print)" "noop plan"
}

test_links_apply_replaces_wrong_symlink_with_backup_and_rollback_restores_it() {
  load_links || return 1
  make_test_home
  make_links_repo || return 1
  write_file "${links_manifest}" 'zsh/zshrc.symlink|.zshrc'
  outside="${TEST_TMPDIR}/outside-target"
  printf 'outside\n' >"${outside}"
  ln -s "${outside}" "${HOME}/.zshrc" || return 1

  apply_links || return 1

  assert_symlink_target "${HOME}/.zshrc" "$(source_path 'zsh/zshrc.symlink')" || return 1
  assert_symlink_target "${backup_root}/.zshrc" "${outside}" || return 1
  assert_contains "${journal}" "$(printf 'backup\t%s\t%s/.zshrc' "$(home_path '.zshrc')" "${backup_root}")" || return 1

  links_rollback "${journal}" || return 1
  assert_symlink_target "${HOME}/.zshrc" "${outside}"
}

test_links_rollback_twice_preserves_restored_wrong_symlink() {
  load_links || return 1
  make_test_home
  make_links_repo || return 1
  write_file "${links_manifest}" 'zsh/zshrc.symlink|.zshrc'
  outside="${TEST_TMPDIR}/outside-target"
  printf 'outside\n' >"${outside}"
  ln -s "${outside}" "${HOME}/.zshrc" || return 1

  apply_links || return 1
  links_rollback "${journal}" || return 1
  links_rollback "${journal}" || return 1

  assert_symlink_target "${HOME}/.zshrc" "${outside}"
}

test_links_apply_preflight_uses_explicit_repo_root_for_sources() {
  load_links || return 1
  make_test_home
  make_links_repo || return 1
  manifest_repo="${repo_root}"
  passed_repo="${TEST_TMPDIR}/passed repo"
  mkdir -p "${passed_repo}/zsh" || return 1
  repo_root="${passed_repo}"
  write_file "${links_manifest}" 'zsh/zshrc.symlink|.zshrc'

  if apply_links >/dev/null 2>&1; then
    repo_root="${manifest_repo}"
    fail "links_apply accepted source missing under explicit repo root"
    return 1
  fi

  if [ -e "${HOME}/.zshrc" ] || [ -L "${HOME}/.zshrc" ]; then
    repo_root="${manifest_repo}"
    fail "failed explicit repo preflight still mutated destination"
    return 1
  fi
  repo_root="${manifest_repo}"
}

test_links_apply_preserves_regular_file_conflict_under_relative_backup_path() {
  load_links || return 1
  make_test_home
  make_links_repo || return 1
  write_file "${links_manifest}" 'git/gitconfig.symlink|.config/git/config'
  write_file "${HOME}/.config/git/config" 'user config'

  apply_links || return 1

  assert_symlink_target "${HOME}/.config/git/config" "$(source_path 'git/gitconfig.symlink')" || return 1
  assert_file "${backup_root}/.config/git/config" || return 1
  assert_contains "${backup_root}/.config/git/config" 'user config'
}

test_links_apply_preserves_directory_conflict_and_relinks_destination() {
  load_links || return 1
  make_test_home
  make_links_repo || return 1
  write_file "${links_manifest}" 'git/gitconfig.symlink|.gitconfig'
  mkdir -p "${HOME}/.gitconfig" || return 1
  write_file "${HOME}/.gitconfig/inside" 'directory conflict'

  apply_links || return 1

  assert_symlink_target "${HOME}/.gitconfig" "$(source_path 'git/gitconfig.symlink')" || return 1
  assert_file "${backup_root}/.gitconfig/inside" || return 1
  assert_contains "${backup_root}/.gitconfig/inside" 'directory conflict'
}

test_links_apply_handles_spaces_in_source_destination_backup_and_journal_paths() {
  load_links || return 1
  make_test_home
  make_links_repo || return 1
  write_file "${links_manifest}" 'kitty configs/kitty.conf|.config/kitty config/kitty.conf'

  apply_links || return 1

  assert_symlink_target "${HOME}/.config/kitty config/kitty.conf" "$(source_path 'kitty configs/kitty.conf')" || return 1
  assert_contains "${journal}" "$(printf 'link\t%s\t' "$(home_path '.config/kitty config/kitty.conf')")"
}

test_links_apply_journals_nested_destination_creation_and_rollback_removes_it() {
  load_links || return 1
  make_test_home
  make_links_repo || return 1
  write_file "${links_manifest}" 'git/gitconfig.symlink|.config/git/deep/config'

  apply_links || return 1

  assert_symlink_target "${HOME}/.config/git/deep/config" "$(source_path 'git/gitconfig.symlink')" || return 1
  assert_contains "${journal}" "$(printf 'mkdir\t%s\t' "$(home_path '.config/git/deep')")" || return 1

  links_rollback "${journal}" || return 1
  if [ -e "${HOME}/.config/git/deep/config" ]; then
    fail "rollback left created link"
  fi
  if [ -e "${HOME}/.config/git/deep" ]; then
    fail "rollback left created nested directory"
  fi
  if [ -e "${HOME}/.config/git" ]; then
    fail "rollback left created parent directory"
  fi
}

test_links_apply_reuses_one_backup_root_for_multiple_conflicts() {
  load_links || return 1
  make_test_home
  make_links_repo || return 1
  write_file "${links_manifest}" \
    'zsh/zshrc.symlink|.zshrc' \
    'git/gitconfig.symlink|.gitconfig'
  write_file "${HOME}/.zshrc" 'old zsh'
  write_file "${HOME}/.gitconfig" 'old git'

  apply_links || return 1

  assert_file "${backup_root}/.zshrc" || return 1
  assert_file "${backup_root}/.gitconfig" || return 1
  assert_contains "${journal}" "$(printf 'backup\t%s\t%s/.zshrc' "$(home_path '.zshrc')" "${backup_root}")" || return 1
  assert_contains "${journal}" "$(printf 'backup\t%s\t%s/.gitconfig' "$(home_path '.gitconfig')" "${backup_root}")"
}

test_links_apply_rolls_back_earlier_mutations_after_injected_later_failure() {
  load_links || return 1
  make_test_home
  make_links_repo || return 1
  write_file "${links_manifest}" \
    'zsh/zshrc.symlink|.zshrc' \
    'git/gitconfig.symlink|.gitconfig'
  write_file "${HOME}/.zshrc" 'old zsh'
  backup_root="${TEST_TMPDIR}/backup root"
  journal="${TEST_TMPDIR}/links journal"

  DOTFILES_LINKS_FAIL_AFTER_MUTATIONS=2
  export DOTFILES_LINKS_FAIL_AFTER_MUTATIONS
  assert_fails apply_links
  unset DOTFILES_LINKS_FAIL_AFTER_MUTATIONS

  assert_file "${HOME}/.zshrc" || return 1
  assert_contains "${HOME}/.zshrc" 'old zsh' || return 1
  if [ -e "${HOME}/.gitconfig" ]; then
    fail "failed apply left later destination behind"
  fi
  links_rollback "${journal}" || return 1
  links_rollback "${journal}" || return 1
}
