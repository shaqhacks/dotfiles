# shellcheck shell=bash
# shellcheck disable=SC2016

COMMON_SH="${TEST_ROOT}/../script/common.sh"
PLUGINS_SH="${TEST_ROOT}/../script/plugins.sh"
FONTS_SH="${TEST_ROOT}/../script/fonts.sh"

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

  if [ -e "${path}" ]; then
    fail "expected missing path: ${path}"
    return 1
  fi
}

assert_log_contains() {
  needle="$1"

  assert_contains "${DOTFILES_STUB_LOG}" "${needle}"
}

assert_status() {
  expected="$1"
  actual="$2"
  message="$3"

  assert_eq "${expected}" "${actual}" "${message}"
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

load_dependencies() {
  if [ ! -f "${COMMON_SH}" ]; then
    fail "missing common helpers: ${COMMON_SH}"
    return 1
  fi
  if [ ! -f "${PLUGINS_SH}" ]; then
    fail "missing plugin installer: ${PLUGINS_SH}"
    return 1
  fi
  if [ ! -f "${FONTS_SH}" ]; then
    fail "missing font installer: ${FONTS_SH}"
    return 1
  fi

  # shellcheck source=../script/common.sh
  # shellcheck disable=SC1091
  . "${COMMON_SH}"
  # shellcheck source=../script/plugins.sh
  # shellcheck disable=SC1091
  . "${PLUGINS_SH}"
  # shellcheck source=../script/fonts.sh
  # shellcheck disable=SC1091
  . "${FONTS_SH}"
}

setup_dependency_stubs() {
  DOTFILES_STUB_LOG="${TEST_TMPDIR}/stub.log"
  DOTFILES_STUB_BIN="${TEST_TMPDIR}/bin"
  mkdir -p "${DOTFILES_STUB_BIN}" || return 1
  : >"${DOTFILES_STUB_LOG}" || return 1
  PATH="${DOTFILES_STUB_BIN}:${PATH}"
  export DOTFILES_STUB_LOG DOTFILES_STUB_BIN PATH

  write_file "${DOTFILES_STUB_BIN}/git" \
    '#!/usr/bin/env bash' \
    'printf "git %s\n" "$*" >>"${DOTFILES_STUB_LOG}"' \
    'cwd="${PWD}"' \
    'if [ "${1:-}" = "-C" ]; then cwd="$2"; shift 2; fi' \
    'case "${1:-}" in' \
    '  clone)' \
    '    url="$2"; dest="$3"' \
    '    if [ "${DOTFILES_STUB_GIT_CLONE_FAIL:-0}" = 1 ]; then exit 46; fi' \
    '    mkdir -p "${dest}/.git" || exit 1' \
    '    if [ "${DOTFILES_STUB_GIT_TERM_AFTER_TEMP:-0}" = 1 ]; then kill -TERM "${PPID}"; sleep 1; exit 143; fi' \
    '    printf "%s\n" "${url}" >"${dest}/.git/origin"' \
    '    printf "%s\n" "${DOTFILES_STUB_GIT_CLONE_COMMIT:-0000000000000000000000000000000000000000}" >"${dest}/.git/commit"' \
    '    : >"${dest}/.git/clean"' \
    '    printf "plugin\n" >"${dest}/${DOTFILES_STUB_PLUGIN_ENTRYPOINT:-sample.plugin.zsh}"' \
    '    ;;' \
    '  config)' \
    '    case "${2:-}" in --get) cat "${cwd}/.git/origin" ;; *) exit 64 ;; esac' \
    '    ;;' \
    '  rev-parse)' \
    '    case "${2:-}" in HEAD) cat "${cwd}/.git/commit" ;; --git-dir) [ -d "${cwd}/.git" ] && printf "%s/.git\n" "${cwd}" || exit 1 ;; *) exit 64 ;; esac' \
    '    ;;' \
    '  status)' \
    '    if [ -f "${cwd}/.git/dirty" ]; then printf " M file\n"; fi' \
    '    ;;' \
    '  fetch)' \
    '    if [ "${DOTFILES_STUB_GIT_FETCH_FAIL:-0}" = 1 ]; then exit 47; fi' \
    '    ;;' \
    '  checkout)' \
    '    if [ "${DOTFILES_STUB_GIT_CHECKOUT_FAIL:-0}" = 1 ]; then exit 48; fi' \
    '    commit="${@: -1}"' \
    '    printf "%s\n" "${commit}" >"${cwd}/.git/commit"' \
    '    printf "plugin\n" >"${cwd}/${DOTFILES_STUB_PLUGIN_ENTRYPOINT:-sample.plugin.zsh}"' \
    '    ;;' \
    '  *) exit 64 ;;' \
    'esac'
  chmod +x "${DOTFILES_STUB_BIN}/git" || return 1

  write_file "${DOTFILES_STUB_BIN}/curl" \
    '#!/usr/bin/env bash' \
    'printf "curl %s\n" "$*" >>"${DOTFILES_STUB_LOG}"' \
    'if [ "${DOTFILES_STUB_CURL_FAIL:-0}" = 1 ]; then exit 49; fi' \
    'output=""' \
    'while [ "$#" -gt 0 ]; do case "$1" in -o) shift; output="$1" ;; esac; shift; done' \
    '[ -n "${output}" ] || exit 64' \
    'printf "%s" "${DOTFILES_STUB_ARCHIVE_CONTENT:-font-archive}" >"${output}"'
  chmod +x "${DOTFILES_STUB_BIN}/curl" || return 1

  write_file "${DOTFILES_STUB_BIN}/unzip" \
    '#!/usr/bin/env bash' \
    'printf "unzip %s\n" "$*" >>"${DOTFILES_STUB_LOG}"' \
    'has_ttf=0' \
    'has_otf=0' \
    'for member in ${DOTFILES_STUB_ZIP_MEMBERS:-JetBrainsMonoNerdFont-Regular.ttf}; do' \
    '  case "${member}" in *.ttf) has_ttf=1 ;; *.otf) has_otf=1 ;; esac' \
    'done' \
    'case "${1:-}" in' \
    '  -Z1)' \
    '    printf "%s\n" ${DOTFILES_STUB_ZIP_MEMBERS:-JetBrainsMonoNerdFont-Regular.ttf}' \
    '    ;;' \
    '  *)' \
    '    archive="$1"; shift' \
    '    dest=""' \
    '    patterns=""' \
    '    while [ "$#" -gt 0 ]; do' \
    '      case "$1" in' \
    '        -d) shift; dest="$1" ;;' \
    '        *.ttf) [ "${has_ttf}" = 1 ] || exit 51; patterns="${patterns} $1" ;;' \
    '        *.otf) [ "${has_otf}" = 1 ] || exit 51; patterns="${patterns} $1" ;;' \
    '        *) patterns="${patterns} $1" ;;' \
    '      esac' \
    '      shift' \
    '    done' \
    '    [ -n "${archive}" ] || exit 64' \
    '    [ -n "${dest}" ] || exit 64' \
    '    mkdir -p "${dest}" || exit 1' \
    '    for member in ${DOTFILES_STUB_ZIP_MEMBERS:-JetBrainsMonoNerdFont-Regular.ttf}; do' \
    '      case "${member}" in *.ttf|*.otf)' \
    '        for pattern in ${patterns}; do' \
    '          case "${pattern}:${member}" in *.ttf:*.ttf|*.otf:*.otf|"${member}:${member}") printf "font\n" >"${dest}/$(basename -- "${member}")" ;; esac' \
    '        done' \
    '        ;;' \
    '      esac' \
    '    done' \
    '    ;;' \
    'esac'
  chmod +x "${DOTFILES_STUB_BIN}/unzip" || return 1

  write_file "${DOTFILES_STUB_BIN}/fc-cache" \
    '#!/usr/bin/env bash' \
    'printf "fc-cache %s\n" "$*" >>"${DOTFILES_STUB_LOG}"' \
    'if [ "${DOTFILES_STUB_FC_CACHE_FAIL:-0}" = 1 ]; then exit 50; fi'
  chmod +x "${DOTFILES_STUB_BIN}/fc-cache" || return 1
}

plugin_manifest() {
  manifest="${TEST_TMPDIR}/plugins.conf"
  write_file "${manifest}" \
    "sample|https://example.invalid/sample.git|1111111111111111111111111111111111111111|sample.plugin.zsh"
  printf '%s' "${manifest}"
}

make_plugin_checkout() {
  path="$1"
  origin="$2"
  commit="$3"

  mkdir -p "${path}/.git" || return 1
  printf '%s\n' "${origin}" >"${path}/.git/origin" || return 1
  printf '%s\n' "${commit}" >"${path}/.git/commit" || return 1
  : >"${path}/.git/clean"
  printf 'plugin\n' >"${path}/sample.plugin.zsh" || return 1
}

font_metadata() {
  checksum="$1"
  metadata="${TEST_TMPDIR}/checksums"
  write_file "${metadata}" \
    "JetBrainsMonoNerdFont|v3.5.0|JetBrainsMono.zip|${checksum}|https://example.invalid/JetBrainsMono.zip"
  printf '%s' "${metadata}"
}

archive_checksum() {
  content="${DOTFILES_STUB_ARCHIVE_CONTENT:-font-archive}"
  printf '%s' "${content}" | shasum -a 256 | sed 's/ .*//'
}

test_plugins_apply_clones_missing_plugin_atomically() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  manifest="$(plugin_manifest)"
  data_root="${TEST_TMPDIR}/data"

  plan_reset || return 1
  plugins_plan "${manifest}" "${data_root}" || return 1
  assert_eq "$(printf 'plugins\tclone\tsample')" "$(plan_print)" "plugin clone plan" || return 1

  plugins_apply "${manifest}" "${data_root}" || return 1

  assert_dir "${data_root}/plugins/sample/.git" || return 1
  assert_eq "1111111111111111111111111111111111111111" "$(cat "${data_root}/plugins/sample/.git/commit")" "checked out commit" || return 1
  assert_log_contains "git clone https://example.invalid/sample.git ${data_root}/plugins/.sample.tmp." || return 1
  assert_log_contains "git -C ${data_root}/plugins/.sample.tmp."
  assert_log_contains "checkout --detach 1111111111111111111111111111111111111111"
}

test_plugins_plan_reports_noop_for_exact_commit() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  manifest="$(plugin_manifest)"
  data_root="${TEST_TMPDIR}/data"
  make_plugin_checkout "${data_root}/plugins/sample" "https://example.invalid/sample.git" "1111111111111111111111111111111111111111" || return 1

  plan_reset || return 1
  plugins_plan "${manifest}" "${data_root}" || return 1

  assert_eq "$(printf 'plugins\tnoop\tsample')" "$(plan_print)" "plugin noop plan"
}

test_plugins_apply_updates_changed_pinned_revision() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  manifest="$(plugin_manifest)"
  data_root="${TEST_TMPDIR}/data"
  make_plugin_checkout "${data_root}/plugins/sample" "https://example.invalid/sample.git" "2222222222222222222222222222222222222222" || return 1

  plan_reset || return 1
  plugins_plan "${manifest}" "${data_root}" || return 1
  assert_eq "$(printf 'plugins\tupdate\tsample')" "$(plan_print)" "plugin update plan" || return 1

  plugins_apply "${manifest}" "${data_root}" || return 1
  assert_eq "1111111111111111111111111111111111111111" "$(cat "${data_root}/plugins/sample/.git/commit")" "updated commit" || return 1
  assert_log_contains "git -C ${data_root}/plugins/sample fetch --depth 1 origin 1111111111111111111111111111111111111111"
}

test_plugins_apply_update_preserves_fetch_and_checkout_failure_status() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  manifest="$(plugin_manifest)"
  data_root="${TEST_TMPDIR}/data"
  make_plugin_checkout "${data_root}/plugins/sample" "https://example.invalid/sample.git" "2222222222222222222222222222222222222222" || return 1
  DOTFILES_STUB_GIT_FETCH_FAIL=1
  export DOTFILES_STUB_GIT_FETCH_FAIL

  plugins_apply "${manifest}" "${data_root}" >/dev/null 2>&1
  status=$?
  assert_status 47 "${status}" "plugin update fetch failure status" || return 1
  assert_eq "2222222222222222222222222222222222222222" "$(cat "${data_root}/plugins/sample/.git/commit")" "commit after failed fetch" || return 1

  unset DOTFILES_STUB_GIT_FETCH_FAIL
  DOTFILES_STUB_GIT_CHECKOUT_FAIL=1
  export DOTFILES_STUB_GIT_CHECKOUT_FAIL
  plugins_apply "${manifest}" "${data_root}" >/dev/null 2>&1
  status=$?
  assert_status 48 "${status}" "plugin update checkout failure status" || return 1
  assert_eq "2222222222222222222222222222222222222222" "$(cat "${data_root}/plugins/sample/.git/commit")" "commit after failed checkout"
}

test_plugins_apply_rejects_mismatched_origin() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  manifest="$(plugin_manifest)"
  data_root="${TEST_TMPDIR}/data"
  make_plugin_checkout "${data_root}/plugins/sample" "https://example.invalid/other.git" "1111111111111111111111111111111111111111" || return 1

  assert_fails plugins_apply "${manifest}" "${data_root}" || return 1
  assert_eq "https://example.invalid/other.git" "$(cat "${data_root}/plugins/sample/.git/origin")" "origin preserved"
}

test_plugins_apply_rejects_dirty_checkout() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  manifest="$(plugin_manifest)"
  data_root="${TEST_TMPDIR}/data"
  make_plugin_checkout "${data_root}/plugins/sample" "https://example.invalid/sample.git" "2222222222222222222222222222222222222222" || return 1
  : >"${data_root}/plugins/sample/.git/dirty" || return 1

  assert_fails plugins_apply "${manifest}" "${data_root}" || return 1
  assert_eq "2222222222222222222222222222222222222222" "$(cat "${data_root}/plugins/sample/.git/commit")" "dirty checkout commit preserved"
}

test_plugins_apply_removes_temp_clone_after_failure() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  manifest="$(plugin_manifest)"
  data_root="${TEST_TMPDIR}/data"
  DOTFILES_STUB_GIT_CLONE_FAIL=1
  export DOTFILES_STUB_GIT_CLONE_FAIL

  assert_fails plugins_apply "${manifest}" "${data_root}" || return 1
  assert_missing "${data_root}/plugins/sample" || return 1
  if find "${data_root}/plugins" -name '.sample.tmp.*' -print 2>/dev/null | grep . >/dev/null 2>&1; then
    fail "temporary clone was left behind"
    return 1
  fi
}

test_plugins_apply_removes_temp_clone_after_term_signal() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  manifest="$(plugin_manifest)"
  data_root="${TEST_TMPDIR}/data"
  DOTFILES_STUB_GIT_TERM_AFTER_TEMP=1
  export DOTFILES_STUB_GIT_TERM_AFTER_TEMP

  (
    plugins_apply "${manifest}" "${data_root}"
  ) >/dev/null 2>&1
  status=$?
  if [ "${status}" -eq 0 ]; then
    fail "plugins_apply succeeded after simulated TERM"
    return 1
  fi

  assert_missing "${data_root}/plugins/sample" || return 1
  if find "${data_root}/plugins" -name '.sample.tmp.*' -print 2>/dev/null | grep . >/dev/null 2>&1; then
    fail "temporary clone was left behind after TERM"
    return 1
  fi
}

test_plugins_apply_preserves_outer_term_trap_after_successful_clone() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  manifest="$(plugin_manifest)"
  data_root="${TEST_TMPDIR}/data"
  trap 'printf term >"${TEST_TMPDIR}/outer-term-trap"' TERM
  before_trap="$(trap -p TERM)"

  plugins_apply "${manifest}" "${data_root}" || return 1

  after_trap="$(trap -p TERM)"
  assert_eq "${before_trap}" "${after_trap}" "outer TERM trap after plugin clone"
}

test_plugins_plan_rejects_manifest_with_malformed_entrypoint() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  manifest="${TEST_TMPDIR}/plugins.conf"
  write_file "${manifest}" \
    "sample|https://example.invalid/sample.git|1111111111111111111111111111111111111111|../sample.zsh"

  plan_reset || return 1
  assert_fails plugins_plan "${manifest}" "${TEST_TMPDIR}/data"
}

test_font_plan_is_noop_when_linux_font_is_already_present() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  make_test_home
  mkdir -p "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont" || return 1
  printf 'font\n' >"${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf" || return 1
  printf 'v3.5.0\n' >"${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/.version" || return 1

  plan_reset || return 1
  font_plan debian || return 1

  assert_eq "$(printf 'fonts\tnoop\tJetBrainsMonoNerdFont')" "$(plan_print)" "font noop plan"
}

test_font_install_linux_rejects_digest_mismatch_before_extracting() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  make_test_home
  metadata="$(font_metadata "0000000000000000000000000000000000000000000000000000000000000000")"

  assert_fails font_install_linux "${metadata}" || return 1
  assert_missing "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont" || return 1
  assert_log_contains "curl -fsSL https://example.invalid/JetBrainsMono.zip -o " || return 1
  if grep -F "unzip " "${DOTFILES_STUB_LOG}" >/dev/null 2>&1; then
    fail "unzip ran after digest mismatch"
    return 1
  fi
}

test_font_install_linux_rejects_archive_traversal_before_extraction() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  make_test_home
  metadata="$(font_metadata "$(archive_checksum)")"
  DOTFILES_STUB_ZIP_MEMBERS='../evil.ttf JetBrainsMonoNerdFont-Regular.ttf'
  export DOTFILES_STUB_ZIP_MEMBERS

  assert_fails font_install_linux "${metadata}" || return 1
  assert_missing "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont" || return 1
  assert_log_contains "unzip -Z1 "
  if grep -F "unzip -q " "${DOTFILES_STUB_LOG}" >/dev/null 2>&1; then
    fail "extracting unzip ran after unsafe member"
    return 1
  fi
}

test_font_install_linux_propagates_download_failure_and_cleans_archive() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  make_test_home
  metadata="$(font_metadata "$(archive_checksum)")"
  DOTFILES_STUB_CURL_FAIL=1
  export DOTFILES_STUB_CURL_FAIL

  assert_fails font_install_linux "${metadata}" || return 1
  assert_missing "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont"
}

test_font_install_linux_installs_fonts_and_refreshes_cache() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  make_test_home
  metadata="$(font_metadata "$(archive_checksum)")"
  DOTFILES_STUB_ZIP_MEMBERS='nested/JetBrainsMonoNerdFont-Regular.ttf JetBrainsMonoNerdFont-Bold.otf README.md'
  export DOTFILES_STUB_ZIP_MEMBERS

  font_install_linux "${metadata}" || return 1

  assert_file "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf" || return 1
  assert_file "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Bold.otf" || return 1
  assert_missing "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/README.md" || return 1
  assert_eq "v3.5.0" "$(cat "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/.version")" "font version marker" || return 1
  assert_log_contains "fc-cache -f ${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont"
}

test_font_install_linux_installs_ttf_only_archive() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  make_test_home
  metadata="$(font_metadata "$(archive_checksum)")"
  DOTFILES_STUB_ZIP_MEMBERS='JetBrainsMonoNerdFont-Regular.ttf'
  export DOTFILES_STUB_ZIP_MEMBERS

  font_install_linux "${metadata}" || return 1

  assert_file "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf"
}

test_font_install_linux_installs_otf_only_archive() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  make_test_home
  metadata="$(font_metadata "$(archive_checksum)")"
  DOTFILES_STUB_ZIP_MEMBERS='JetBrainsMonoNerdFont-Regular.otf'
  export DOTFILES_STUB_ZIP_MEMBERS

  font_install_linux "${metadata}" || return 1

  assert_file "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.otf"
}

test_font_install_linux_propagates_cache_refresh_failure() {
  load_dependencies || return 1
  setup_dependency_stubs || return 1
  make_test_home
  metadata="$(font_metadata "$(archive_checksum)")"
  DOTFILES_STUB_FC_CACHE_FAIL=1
  export DOTFILES_STUB_FC_CACHE_FAIL

  assert_fails font_install_linux "${metadata}" || return 1
  assert_file "${XDG_DATA_HOME}/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf"
}
