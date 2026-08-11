COMMON_SH="${TEST_ROOT}/../script/common.sh"

assert_fails() {
  if (
    "$@"
  ) >/dev/null 2>&1; then
    fail "expected command to fail: $*"
    return 1
  fi
}

load_common() {
  if [ ! -f "${COMMON_SH}" ]; then
    fail "missing common helpers: ${COMMON_SH}"
    return 1
  fi

  # shellcheck source=../script/common.sh
  . "${COMMON_SH}"
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

collect_callback() {
  printf '%s\n' "$*" >>"${TEST_TMPDIR}/callback-output"
}

marker_callback() {
  printf 'called\n' >"${TEST_TMPDIR}/callback-marker"
}

test_manifest_each_ignores_blank_lines_and_comments() {
  load_common || return 1
  manifest="${TEST_TMPDIR}/packages.debian"
  write_file "${manifest}" \
    '# Package records are data, not shell.' \
    '' \
    'git' \
    '   ' \
    '# another comment' \
    'curl'

  manifest_each debian "${manifest}" collect_callback || return 1

  assert_eq "$(printf 'git\ncurl')" "$(cat "${TEST_TMPDIR}/callback-output")" "debian records"
}

test_manifest_each_requires_exact_field_counts_before_callback() {
  load_common || return 1

  write_file "${TEST_TMPDIR}/links.conf" 'source|dest|extra'
  assert_fails manifest_each links "${TEST_TMPDIR}/links.conf" marker_callback
  if [ -e "${TEST_TMPDIR}/callback-marker" ]; then
    fail "link callback ran for an invalid record"
  fi

  write_file "${TEST_TMPDIR}/packages.macos" 'formula'
  assert_fails manifest_each macos "${TEST_TMPDIR}/packages.macos" marker_callback

  write_file "${TEST_TMPDIR}/packages.debian" 'git|extra'
  assert_fails manifest_each debian "${TEST_TMPDIR}/packages.debian" marker_callback

  write_file "${TEST_TMPDIR}/plugins.conf" 'name|https://example.invalid/repo.git|0123456789012345678901234567890123456789'
  assert_fails manifest_each plugins "${TEST_TMPDIR}/plugins.conf" marker_callback
}

test_manifest_each_rejects_duplicate_destinations_and_names() {
  load_common || return 1

  write_file "${TEST_TMPDIR}/links.conf" \
    'zsh/zshrc.symlink|.zshrc' \
    'git/gitconfig.symlink|.zshrc'
  assert_fails manifest_each links "${TEST_TMPDIR}/links.conf" marker_callback

  write_file "${TEST_TMPDIR}/plugins.conf" \
    'powerlevel10k|https://github.com/romkatv/powerlevel10k.git|35833ea15f14b71dbcebc7e54c104d8d56ca5268|powerlevel10k.zsh-theme' \
    'powerlevel10k|https://github.com/romkatv/powerlevel10k.git|35833ea15f14b71dbcebc7e54c104d8d56ca5268|powerlevel10k.zsh-theme'
  assert_fails manifest_each plugins "${TEST_TMPDIR}/plugins.conf" marker_callback
}

test_manifest_each_rejects_hostile_link_paths_before_callback() {
  load_common || return 1

  write_file "${TEST_TMPDIR}/missing-source.conf" 'missing/file|.zshrc'
  assert_fails manifest_each links "${TEST_TMPDIR}/missing-source.conf" marker_callback

  write_file "${TEST_TMPDIR}/absolute-source.conf" '/tmp/source|.zshrc'
  assert_fails manifest_each links "${TEST_TMPDIR}/absolute-source.conf" marker_callback

  write_file "${TEST_TMPDIR}/traversal-dest.conf" 'zsh/zshrc.symlink|../.zshrc'
  assert_fails manifest_each links "${TEST_TMPDIR}/traversal-dest.conf" marker_callback

  tab_record="$(printf 'zsh/zshrc.symlink|bad\tname')"
  write_file "${TEST_TMPDIR}/control-dest.conf" "${tab_record}"
  assert_fails manifest_each links "${TEST_TMPDIR}/control-dest.conf" marker_callback

  if [ -e "${TEST_TMPDIR}/callback-marker" ]; then
    fail "callback ran for a hostile link record"
  fi
}

test_manifest_each_rejects_hostile_plugin_fields() {
  load_common || return 1

  write_file "${TEST_TMPDIR}/plugins.conf" \
    'powerlevel10k|git://github.com/romkatv/powerlevel10k.git|35833ea15f14b71dbcebc7e54c104d8d56ca5268|powerlevel10k.zsh-theme'
  assert_fails manifest_each plugins "${TEST_TMPDIR}/plugins.conf" marker_callback

  write_file "${TEST_TMPDIR}/plugins.conf" \
    'powerlevel10k|https://github.com/romkatv/powerlevel10k.git|not-a-commit|powerlevel10k.zsh-theme'
  assert_fails manifest_each plugins "${TEST_TMPDIR}/plugins.conf" marker_callback

  write_file "${TEST_TMPDIR}/plugins.conf" \
    'powerlevel10k|https://github.com/romkatv/powerlevel10k.git|35833ea15f14b71dbcebc7e54c104d8d56ca5268|../theme.zsh'
  assert_fails manifest_each plugins "${TEST_TMPDIR}/plugins.conf" marker_callback
}

test_validate_repo_source_accepts_only_regular_files_inside_root() {
  load_common || return 1
  root="${TEST_TMPDIR}/repo"
  outside="${TEST_TMPDIR}/outside"
  mkdir -p "${root}/zsh" "${outside}" || return 1
  printf 'config\n' >"${root}/zsh/zshrc.symlink"
  printf 'secret\n' >"${outside}/secret"
  ln -s "${outside}/secret" "${root}/zsh/escaping.symlink"

  validate_repo_source "${root}" 'zsh/zshrc.symlink' || return 1
  assert_fails validate_repo_source "${root}" 'zsh/missing'
  assert_fails validate_repo_source "${root}" '/tmp/file'
  assert_fails validate_repo_source "${root}" '../outside/secret'
  assert_fails validate_repo_source "${root}" 'zsh/escaping.symlink'
}

test_validate_home_destination_rejects_escaping_or_ambiguous_paths() {
  load_common || return 1
  make_test_home

  validate_home_destination '.zshrc' || return 1
  validate_home_destination '.config/kitty/kitty.conf' || return 1
  assert_fails validate_home_destination ''
  assert_fails validate_home_destination '/tmp/dotfile'
  assert_fails validate_home_destination '.config//kitty.conf'
  assert_fails validate_home_destination './.zshrc'
  assert_fails validate_home_destination '.config/../.zshrc'
  newline_dest="$(printf '.config\nkitty.conf')"
  assert_fails validate_home_destination "${newline_dest}"
}

test_plan_primitives_preserve_order_without_bash4_arrays() {
  load_common || return 1

  plan_reset || return 1
  plan_append preflight validate manifests || return 1
  plan_append links link .zshrc || return 1

  assert_eq "$(printf 'preflight\tvalidate\tmanifests\nlinks\tlink\t.zshrc')" "$(plan_print)" "plan output"
}

test_locked_manifests_parse_to_expected_records() {
  load_common || return 1
  repo_root="$(CDPATH= cd -P -- "${TEST_ROOT}/.." && pwd -P)" || return 1

  : >"${TEST_TMPDIR}/callback-output"
  manifest_each macos "${repo_root}/manifest/packages.macos" collect_callback || return 1
  assert_eq "$(printf 'formula git\nformula fzf\nformula coreutils\nformula shellcheck\nformula shfmt\ncask kitty\ncask font-jetbrains-mono-nerd-font')" "$(cat "${TEST_TMPDIR}/callback-output")" "macOS packages"

  : >"${TEST_TMPDIR}/callback-output"
  manifest_each debian "${repo_root}/manifest/packages.debian" collect_callback || return 1
  assert_eq "$(printf 'zsh\ngit\ncurl\nfzf\nkitty\nfontconfig\nunzip\ncoreutils\nshellcheck\nshfmt')" "$(cat "${TEST_TMPDIR}/callback-output")" "Debian packages"

  : >"${TEST_TMPDIR}/callback-output"
  manifest_each plugins "${repo_root}/manifest/plugins.conf" collect_callback || return 1
  assert_eq "$(printf 'powerlevel10k https://github.com/romkatv/powerlevel10k.git 35833ea15f14b71dbcebc7e54c104d8d56ca5268 powerlevel10k.zsh-theme\nzsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git e52ee8ca55bcc56a17c828767a3f98f22a68d4eb zsh-autosuggestions.zsh\nzsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git db085e4661f6aafd24e5acb5b2e17e4dd5dddf3e zsh-syntax-highlighting.zsh')" "$(cat "${TEST_TMPDIR}/callback-output")" "plugins"
}
