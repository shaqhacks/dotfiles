# shellcheck shell=bash

DOCTOR_SOURCE_ROOT="${TEST_ROOT}/.."
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

make_doctor_repo() {
  DOCTOR_REPO="${TEST_TMPDIR}/repo"
  mkdir -p "${DOCTOR_REPO}/script" "${DOCTOR_REPO}/manifest" "${DOCTOR_REPO}/fonts" \
    "${DOCTOR_REPO}/zsh" "${DOCTOR_REPO}/git" || return 1
  cp "${DOCTOR_SOURCE_ROOT}"/script/*.sh "${DOCTOR_REPO}/script/" || return 1
  write_file "${DOCTOR_REPO}/zsh/zshrc.symlink" "repo zsh" || return 1
  write_file "${DOCTOR_REPO}/git/gitconfig.symlink" "repo git" || return 1
  write_file "${DOCTOR_REPO}/manifest/links.conf" \
    "zsh/zshrc.symlink|.zshrc" \
    "git/gitconfig.symlink|.gitconfig" || return 1
  write_file "${DOCTOR_REPO}/manifest/packages.debian" "zsh" "git" "curl" || return 1
  write_file "${DOCTOR_REPO}/manifest/packages.macos" "formula|git" || return 1
  write_file "${DOCTOR_REPO}/manifest/plugins.conf" \
    "sample|https://example.invalid/sample.git|1111111111111111111111111111111111111111|sample.plugin.zsh" || return 1
  write_file "${DOCTOR_REPO}/fonts/checksums" \
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

setup_doctor_environment() {
  DOTFILES_STUB_LOG="${TEST_TMPDIR}/stub.log"
  : >"${DOTFILES_STUB_LOG}" || return 1
  PATH="${FIXTURE_BIN}:${PATH}"
  DOTFILES_TEST_MODE=1
  DOTFILES_TEST_PLATFORM=debian
  DOTFILES_TEST_SHELLS_FILE="${TEST_TMPDIR}/shells"
  DOTFILES_STUB_DPKG_PACKAGES="$(printf 'zsh\ngit\ncurl')"
  export DOTFILES_STUB_LOG PATH DOTFILES_TEST_MODE DOTFILES_TEST_PLATFORM DOTFILES_TEST_SHELLS_FILE DOTFILES_STUB_DPKG_PACKAGES
  write_file "${DOTFILES_TEST_SHELLS_FILE}" "${FIXTURE_BIN}/zsh" || return 1
  make_test_home || return 1
}

make_healthy_install() {
  ln -s "$(canonical_file "${DOCTOR_REPO}/zsh/zshrc.symlink")" "${HOME}/.zshrc" || return 1
  ln -s "$(canonical_file "${DOCTOR_REPO}/git/gitconfig.symlink")" "${HOME}/.gitconfig" || return 1
  mkdir -p "${XDG_DATA_HOME}/dotfiles/plugins/sample/.git" "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont" || return 1
  write_file "${XDG_DATA_HOME}/dotfiles/plugins/sample/.git/origin" "https://example.invalid/sample.git" || return 1
  write_file "${XDG_DATA_HOME}/dotfiles/plugins/sample/.git/commit" "1111111111111111111111111111111111111111" || return 1
  write_file "${XDG_DATA_HOME}/dotfiles/plugins/sample/sample.plugin.zsh" "plugin" || return 1
  write_file "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf" "font" || return 1
  write_file "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/.version" "v3.5.0"
}

run_doctor_capture() {
  doctor_out="${TEST_TMPDIR}/doctor.out"
  doctor_err="${TEST_TMPDIR}/doctor.err"
  (
    cd "${TEST_TMPDIR}" || exit 1
    "${DOCTOR_REPO}/script/doctor.sh"
  ) >"${doctor_out}" 2>"${doctor_err}"
  doctor_status=$?
  return 0
}

test_doctor_reports_healthy_install_without_mutation() {
  make_doctor_repo || return 1
  setup_doctor_environment || return 1
  make_healthy_install || return 1

  run_doctor_capture

  assert_eq 0 "${doctor_status}" "doctor healthy status" || return 1
  assert_contains "${doctor_out}" "ok platform" || return 1
  assert_contains "${doctor_out}" "ok links" || return 1
  assert_log_count "sudo " 0 || return 1
  assert_log_count "git clone" 0 || return 1
  assert_log_count "chsh " 0
}

test_doctor_reports_missing_plugin_font_and_link_diagnostics() {
  make_doctor_repo || return 1
  setup_doctor_environment || return 1
  ln -s "${DOCTOR_REPO}/git/gitconfig.symlink" "${HOME}/.gitconfig" || return 1

  run_doctor_capture

  assert_eq 1 "${doctor_status}" "doctor unhealthy status" || return 1
  assert_contains "${doctor_out}" "ok platform" || return 1
  assert_contains "${doctor_out}" "ok packages" || return 1
  assert_not_contains "${doctor_out}" "ok plugins" || return 1
  assert_not_contains "${doctor_out}" "ok fonts" || return 1
  assert_not_contains "${doctor_out}" "ok links" || return 1
  assert_contains "${doctor_err}" "missing plugin: sample" || return 1
  assert_contains "${doctor_err}" "font is not installed: JetBrainsMonoNerdFont" || return 1
  assert_contains "${doctor_err}" "link mismatch: .zshrc"
}

test_doctor_reports_bad_plugin_revision_and_wrong_link_target() {
  make_doctor_repo || return 1
  setup_doctor_environment || return 1
  make_healthy_install || return 1
  write_file "${XDG_DATA_HOME}/dotfiles/plugins/sample/.git/commit" "2222222222222222222222222222222222222222" || return 1
  rm "${HOME}/.gitconfig" || return 1
  ln -s "$(canonical_file "${DOCTOR_REPO}/zsh/zshrc.symlink")" "${HOME}/.gitconfig" || return 1

  run_doctor_capture

  assert_eq 1 "${doctor_status}" "doctor unhealthy status" || return 1
  assert_contains "${doctor_out}" "ok platform" || return 1
  assert_contains "${doctor_out}" "ok packages" || return 1
  assert_not_contains "${doctor_out}" "ok plugins" || return 1
  assert_contains "${doctor_out}" "ok fonts" || return 1
  assert_not_contains "${doctor_out}" "ok links" || return 1
  assert_contains "${doctor_err}" "plugin revision mismatch: sample" || return 1
  assert_contains "${doctor_err}" "link mismatch: .gitconfig"
}
