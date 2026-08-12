# shellcheck shell=bash

SETUP_SOURCE_ROOT="${TEST_ROOT}/.."
FIXTURE_BIN="${TEST_ROOT}/fixtures/bin"

assert_fails() {
  if (
    "$@"
  ) >/dev/null 2>&1; then
    fail "expected command to fail: $*"
    return 1
  fi
}

assert_missing() {
  path="$1"

  if [ -e "${path}" ] || [ -L "${path}" ]; then
    fail "expected missing path: ${path}"
    return 1
  fi
}

assert_status() {
  expected="$1"
  actual="$2"
  message="$3"

  assert_eq "${expected}" "${actual}" "${message}"
}

assert_log_count() {
  needle="$1"
  expected="$2"

  actual="$(grep -F -c -- "${needle}" "${DOTFILES_STUB_LOG}" 2>/dev/null || true)"
  assert_eq "${expected}" "${actual}" "log count for ${needle}"
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

make_setup_repo() {
  SETUP_REPO="${TEST_TMPDIR}/repo"
  mkdir -p "${SETUP_REPO}/script" "${SETUP_REPO}/manifest" "${SETUP_REPO}/fonts" \
    "${SETUP_REPO}/zsh" "${SETUP_REPO}/git" || return 1
  cp "${SETUP_SOURCE_ROOT}/setup.sh" "${SETUP_REPO}/setup.sh" || return 1
  cp "${SETUP_SOURCE_ROOT}"/script/*.sh "${SETUP_REPO}/script/" || return 1
  chmod +x "${SETUP_REPO}/setup.sh" || return 1

  write_file "${SETUP_REPO}/zsh/zshrc.symlink" "repo zsh" || return 1
  write_file "${SETUP_REPO}/git/gitconfig.symlink" "repo git" || return 1
  write_file "${SETUP_REPO}/manifest/links.conf" \
    "zsh/zshrc.symlink|.zshrc" \
    "git/gitconfig.symlink|.gitconfig" || return 1
  write_file "${SETUP_REPO}/manifest/packages.debian" "zsh" "git" "curl" || return 1
  write_file "${SETUP_REPO}/manifest/packages.macos" "formula|git" || return 1
  write_file "${SETUP_REPO}/manifest/plugins.conf" \
    "sample|https://example.invalid/sample.git|1111111111111111111111111111111111111111|sample.plugin.zsh" || return 1
  write_file "${SETUP_REPO}/fonts/checksums" \
    "JetBrainsMonoNerdFont|v3.5.0|JetBrainsMono.zip|$(archive_checksum)|https://example.invalid/JetBrainsMono.zip"
}

archive_checksum() {
  printf '%s' "${DOTFILES_STUB_ARCHIVE_CONTENT:-font-archive}" | shasum -a 256 | sed 's/ .*//'
}

canonical_file() {
  file_path="$1"
  file_dir="$(dirname -- "${file_path}")"
  file_base="$(basename -- "${file_path}")"
  printf '%s/%s' "$(CDPATH='' cd -P -- "${file_dir}" && pwd -P)" "${file_base}"
}

setup_environment() {
  DOTFILES_STUB_LOG="${TEST_TMPDIR}/stub.log"
  DOTFILES_PHASE_LOG="${TEST_TMPDIR}/phase.log"
  : >"${DOTFILES_STUB_LOG}" || return 1
  : >"${DOTFILES_PHASE_LOG}" || return 1
  PATH="${FIXTURE_BIN}:${PATH}"
  DOTFILES_TEST_MODE=1
  DOTFILES_TEST_PLATFORM=debian
  DOTFILES_TEST_INTERACTIVE=1
  DOTFILES_TEST_CONFIRM_RESPONSE=yes
  DOTFILES_TEST_SHELLS_FILE="${TEST_TMPDIR}/shells"
  DOTFILES_STUB_DPKG_PACKAGES="$(printf 'zsh\ngit\ncurl')"
  export DOTFILES_STUB_LOG DOTFILES_PHASE_LOG PATH DOTFILES_TEST_MODE DOTFILES_TEST_PLATFORM
  export DOTFILES_TEST_INTERACTIVE DOTFILES_TEST_CONFIRM_RESPONSE DOTFILES_TEST_SHELLS_FILE DOTFILES_STUB_DPKG_PACKAGES
  write_file "${DOTFILES_TEST_SHELLS_FILE}" "${FIXTURE_BIN}/zsh" || return 1
  make_test_home || return 1
  mkdir -p "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont" || return 1
  write_file "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf" "font" || return 1
  write_file "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/.version" "v3.5.0"
}

run_setup_capture() {
  setup_out="${TEST_TMPDIR}/setup.out"
  setup_err="${TEST_TMPDIR}/setup.err"
  (
    cd "${TEST_TMPDIR}" || exit 1
    "${SETUP_REPO}/setup.sh" "$@"
  ) >"${setup_out}" 2>"${setup_err}"
  setup_status=$?
  return 0
}

test_setup_help_lists_supported_flags() {
  make_setup_repo || return 1
  setup_environment || return 1

  run_setup_capture --help

  assert_status 0 "${setup_status}" "help status" || return 1
  assert_contains "${setup_out}" "--dry-run" || return 1
  assert_contains "${setup_out}" "--skip-packages" || return 1
  assert_contains "${setup_out}" "--set-default-shell"
}

test_setup_rejects_unknown_and_duplicate_flags_before_mutation() {
  make_setup_repo || return 1
  setup_environment || return 1

  run_setup_capture --bogus
  assert_status 2 "${setup_status}" "unknown flag status" || return 1
  assert_missing "${HOME}/.zshrc" || return 1
  assert_log_count "git clone" 0 || return 1

  run_setup_capture --dry-run --dry-run
  assert_status 2 "${setup_status}" "duplicate flag status" || return 1
  assert_missing "${HOME}/.zshrc" || return 1
  assert_log_count "chsh " 0
}

test_setup_rejects_unsupported_os_before_mutation() {
  make_setup_repo || return 1
  setup_environment || return 1
  DOTFILES_TEST_PLATFORM=plan9
  export DOTFILES_TEST_PLATFORM

  run_setup_capture --dry-run

  assert_status 1 "${setup_status}" "unsupported OS status" || return 1
  assert_contains "${setup_err}" "unsupported" || return 1
  assert_missing "${HOME}/.zshrc"
}

test_setup_dry_run_prints_validated_plan_without_prompt_or_mutation() {
  make_setup_repo || return 1
  setup_environment || return 1
  unset DOTFILES_TEST_INTERACTIVE
  unset DOTFILES_TEST_CONFIRM_RESPONSE

  run_setup_capture --dry-run

  assert_status 0 "${setup_status}" "dry-run status" || return 1
  assert_contains "${setup_out}" "$(printf 'plugins\tclone\tsample')" || return 1
  assert_contains "${setup_out}" "$(printf 'links\tlink\t.zshrc')" || return 1
  assert_not_contains "${setup_err}" "[y/N]" || return 1
  assert_missing "${HOME}/.zshrc" || return 1
  assert_missing "${XDG_DATA_HOME}/dotfiles/plugins/sample" || return 1
  assert_log_count "git clone" 0 || return 1
  assert_log_count "chsh " 0
}

test_setup_requires_tty_for_confirmation_and_decline_aborts_cleanly() {
  make_setup_repo || return 1
  setup_environment || return 1
  DOTFILES_TEST_INTERACTIVE=0
  export DOTFILES_TEST_INTERACTIVE

  run_setup_capture
  assert_status 1 "${setup_status}" "no-tty status" || return 1
  assert_contains "${setup_err}" "interactive terminal" || return 1
  assert_missing "${HOME}/.zshrc" || return 1

  DOTFILES_TEST_INTERACTIVE=1
  DOTFILES_TEST_CONFIRM_RESPONSE=no
  export DOTFILES_TEST_INTERACTIVE DOTFILES_TEST_CONFIRM_RESPONSE
  run_setup_capture
  assert_status 1 "${setup_status}" "declined status" || return 1
  assert_contains "${setup_err}" "aborted" || return 1
  assert_missing "${HOME}/.zshrc"
}

test_setup_runs_one_confirmation_and_exact_phase_order() {
  make_setup_repo || return 1
  setup_environment || return 1

  run_setup_capture

  assert_status 0 "${setup_status}" "setup status" || return 1
  expected="$(printf 'parse\npreflight\nprint-plan\nconfirm\npackages\nplugins\nfonts\nlinks\ndoctor')"
  assert_eq "${expected}" "$(cat "${DOTFILES_PHASE_LOG}")" "phase order" || return 1
  assert_log_count "git clone https://example.invalid/sample.git" 1 || return 1
  assert_symlink_target "${HOME}/.zshrc" "$(canonical_file "${SETUP_REPO}/zsh/zshrc.symlink")"
}

test_setup_skip_packages_still_installs_plugins_fonts_and_links() {
  make_setup_repo || return 1
  setup_environment || return 1
  DOTFILES_STUB_DPKG_PACKAGES=""
  export DOTFILES_STUB_DPKG_PACKAGES

  run_setup_capture --skip-packages

  assert_status 0 "${setup_status}" "skip package setup status" || return 1
  assert_log_count "sudo apt-get update" 0 || return 1
  assert_log_count "git clone https://example.invalid/sample.git" 1 || return 1
  assert_symlink_target "${HOME}/.gitconfig" "$(canonical_file "${SETUP_REPO}/git/gitconfig.symlink")"
}

test_setup_package_failure_preserves_status_and_happens_before_links() {
  make_setup_repo || return 1
  setup_environment || return 1
  write_file "${SETUP_REPO}/manifest/packages.debian" "fail" || return 1
  DOTFILES_STUB_DPKG_PACKAGES=""
  export DOTFILES_STUB_DPKG_PACKAGES

  run_setup_capture

  assert_status 42 "${setup_status}" "package failure status" || return 1
  assert_log_count "sudo apt-get install -y fail" 1 || return 1
  assert_missing "${HOME}/.zshrc" || return 1
  assert_log_count "git clone" 0
}

test_setup_plugin_failure_preserves_status_and_happens_before_links() {
  make_setup_repo || return 1
  setup_environment || return 1
  DOTFILES_STUB_GIT_CLONE_FAIL=1
  export DOTFILES_STUB_GIT_CLONE_FAIL

  run_setup_capture --skip-packages

  assert_status 46 "${setup_status}" "plugin failure status" || return 1
  assert_log_count "git clone https://example.invalid/sample.git" 1 || return 1
  assert_missing "${HOME}/.zshrc"
}

test_setup_rolls_back_links_and_prints_backup_path_when_links_changed() {
  make_setup_repo || return 1
  setup_environment || return 1
  write_file "${HOME}/.zshrc" "old zsh" || return 1
  DOTFILES_LINKS_FAIL_AFTER_MUTATIONS=2
  export DOTFILES_LINKS_FAIL_AFTER_MUTATIONS

  run_setup_capture --skip-packages

  assert_status 1 "${setup_status}" "link failure status" || return 1
  assert_file "${HOME}/.zshrc" || return 1
  assert_contains "${HOME}/.zshrc" "old zsh" || return 1
  assert_missing "${HOME}/.gitconfig" || return 1
  assert_contains "${setup_err}" "backup root:"
}

test_setup_set_default_shell_uses_validated_zsh_and_propagates_chsh_failure() {
  make_setup_repo || return 1
  setup_environment || return 1

  run_setup_capture --skip-packages --set-default-shell
  assert_status 0 "${setup_status}" "shell setup status" || return 1
  assert_log_count "chsh -s ${FIXTURE_BIN}/zsh" 1 || return 1
  assert_not_contains "${DOTFILES_STUB_LOG}" "/etc/shells" || return 1

  make_test_home || return 1
  mkdir -p "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont" || return 1
  write_file "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf" "font" || return 1
  write_file "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/.version" "v3.5.0" || return 1
  DOTFILES_STUB_CHSH_FAIL=1
  export DOTFILES_STUB_CHSH_FAIL
  run_setup_capture --skip-packages --set-default-shell
  assert_status 95 "${setup_status}" "chsh failure status"
}

test_setup_rejects_unlisted_shell_path_before_chsh() {
  make_setup_repo || return 1
  setup_environment || return 1
  write_file "${DOTFILES_TEST_SHELLS_FILE}" "/not/the/stub/zsh" || return 1

  run_setup_capture --skip-packages --set-default-shell

  assert_status 1 "${setup_status}" "invalid shell status" || return 1
  assert_log_count "chsh " 0 || return 1
  assert_missing "${HOME}/.zshrc"
}
