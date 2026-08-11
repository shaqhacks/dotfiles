assert_fails() {
  if (
    "$@"
  ) >/dev/null 2>&1; then
    fail "expected command to fail: $*"
    return 1
  fi
}

test_assertions_accept_expected_values() {
  tmp_dir="${TEST_TMPDIR}/assertions"
  mkdir -p "${tmp_dir}/dir"
  printf 'hello world\n' >"${tmp_dir}/file"
  ln -s "${tmp_dir}/file" "${tmp_dir}/link"

  assert_eq "same value" "same value" "equal strings pass"
  assert_file "${tmp_dir}/file"
  assert_dir "${tmp_dir}/dir"
  assert_symlink_target "${tmp_dir}/link" "${tmp_dir}/file"
  assert_contains "${tmp_dir}/file" "hello world"
  assert_not_contains "${tmp_dir}/file" "goodbye"
}

test_assertions_fail_in_child_processes() {
  assert_fails assert_eq "expected" "actual"
  assert_fails assert_file "${TEST_TMPDIR}/missing-file"
  assert_fails assert_dir "${TEST_TMPDIR}/missing-dir"
  assert_fails assert_symlink_target "${TEST_TMPDIR}/missing-link" "target"
  assert_fails assert_contains "${TEST_TMPDIR}/missing-file" "needle"

  sample="${TEST_TMPDIR}/sample"
  printf 'alpha\n' >"${sample}"
  assert_fails assert_not_contains "${sample}" "alpha"
}

test_make_test_home_exports_isolated_xdg_directories() {
  original_home="${HOME}"
  make_test_home

  case "${HOME}" in
    "${TEST_TMPDIR}"/*) ;;
    *) fail "HOME was not isolated under TEST_TMPDIR" ;;
  esac

  assert_dir "${HOME}"
  assert_eq "${HOME}/.config" "${XDG_CONFIG_HOME}" "XDG config home"
  assert_eq "${HOME}/.local/share" "${XDG_DATA_HOME}" "XDG data home"
  assert_eq "${HOME}/.local/state" "${XDG_STATE_HOME}" "XDG state home"
  assert_dir "${XDG_CONFIG_HOME}"
  assert_dir "${XDG_DATA_HOME}"
  assert_dir "${XDG_STATE_HOME}"
  if [ "${HOME}" = "${original_home}" ]; then
    fail "HOME was not changed"
  fi
}

test_run_sh_accepts_suite_names_with_spaces() {
  suite_name="suite with spaces"
  suite_file="${TEST_ROOT}/${suite_name}_test.sh"
  printf '%s\n' \
    'test_space_safe_arguments() {' \
    '  assert_eq "value with spaces" "value with spaces" "space-safe value"' \
    '}' >"${suite_file}"
  trap 'rm -f "${suite_file}"' EXIT HUP INT TERM

  output="$(bash "${TEST_ROOT}/run.sh" "${suite_name}")" || fail "space suite failed"
  rm -f "${suite_file}"
  trap - EXIT HUP INT TERM

  case "${output}" in
    *"ok "*"space_safe_arguments"*) ;;
    *) fail "space suite output did not include the test name: ${output}" ;;
  esac
}

test_run_sh_returns_nonzero_for_failed_assertions() {
  suite_file="${TEST_ROOT}/failure_test.sh"
  printf '%s\n' \
    'test_intentional_failure() {' \
    '  assert_eq "expected" "actual" "intentional child failure"' \
    '}' >"${suite_file}"
  trap 'rm -f "${suite_file}"' EXIT HUP INT TERM

  if output="$(bash "${TEST_ROOT}/run.sh" failure 2>&1)"; then
    rm -f "${suite_file}"
    trap - EXIT HUP INT TERM
    fail "runner returned success for a failing suite"
  fi

  rm -f "${suite_file}"
  trap - EXIT HUP INT TERM
  case "${output}" in
    *"not ok "*"intentional_failure"*"# summary: 0 passed, 1 failed"*) ;;
    *) fail "failure output was not TAP-like: ${output}" ;;
  esac
}

test_run_sh_rejects_traversal_suite_names() {
  if output="$(bash "${TEST_ROOT}/run.sh" "../harness" 2>&1)"; then
    fail "runner accepted a traversal suite name"
  fi

  case "${output}" in
    *"invalid suite name"*"../harness"*) ;;
    *) fail "traversal rejection was unclear: ${output}" ;;
  esac
}

test_run_sh_rejects_control_whitespace_suite_names() {
  tab_suite="$(printf 'bad\tname')"
  newline_suite="$(printf 'bad\nname')"

  if output="$(bash "${TEST_ROOT}/run.sh" "${tab_suite}" 2>&1)"; then
    fail "runner accepted a tab in a suite name"
  fi
  case "${output}" in
    *"invalid suite name"*) ;;
    *) fail "tab rejection was unclear: ${output}" ;;
  esac

  if output="$(bash "${TEST_ROOT}/run.sh" "${newline_suite}" 2>&1)"; then
    fail "runner accepted a newline in a suite name"
  fi
  case "${output}" in
    *"invalid suite name"*) ;;
    *) fail "newline rejection was unclear: ${output}" ;;
  esac
}

test_run_sh_ignores_caller_controlled_tests_dir() {
  suite_file="${TEST_TMPDIR}/outside_test.sh"
  marker_file="${TEST_TMPDIR}/outside-ran"
  printf '%s\n' \
    'test_outside_suite() {' \
    "  printf ran >\"${marker_file}\"" \
    '}' >"${suite_file}"

  if output="$(TESTS_DIR="${TEST_TMPDIR}" bash "${TEST_ROOT}/run.sh" outside 2>&1)"; then
    fail "runner executed a suite from caller-controlled TESTS_DIR"
  fi

  if [ -e "${marker_file}" ]; then
    fail "outside suite marker was created"
  fi
  case "${output}" in
    *"missing suite: outside"*) ;;
    *) fail "outside suite rejection was unclear: ${output}" ;;
  esac
}

test_run_sh_rejects_suite_symlink_outside_test_root() {
  suite_name="outside symlink"
  suite_file="${TEST_ROOT}/${suite_name}_test.sh"
  outside_file="${TEST_TMPDIR}/outside_symlink_target_test.sh"
  marker_file="${TEST_TMPDIR}/symlink-ran"
  printf '%s\n' \
    'test_outside_symlink_target() {' \
    "  printf ran >\"${marker_file}\"" \
    '}' >"${outside_file}"
  ln -s "${outside_file}" "${suite_file}"
  trap 'rm -f "${suite_file}"' EXIT HUP INT TERM

  if output="$(bash "${TEST_ROOT}/run.sh" "${suite_name}" 2>&1)"; then
    fail "runner sourced a symlinked suite outside TEST_ROOT"
  fi

  rm -f "${suite_file}"
  trap - EXIT HUP INT TERM
  if [ -e "${marker_file}" ]; then
    fail "symlinked outside suite marker was created"
  fi
  case "${output}" in
    *"outside test root"*) ;;
    *) fail "symlink rejection was unclear: ${output}" ;;
  esac
}

test_make_test_home_cleans_up_after_child_exit() {
  marker_file="${TEST_TMPDIR}/home-path"

  (
    . "${TEST_ROOT}/assert.sh"
    TEST_TMPDIR="${TEST_TMPDIR}/cleanup child"
    mkdir -p "${TEST_TMPDIR}"
    make_test_home
    printf '%s\n' "${HOME}" >"${marker_file}"
    assert_dir "${HOME}"
  )

  child_home="$(cat "${marker_file}")"
  if [ -e "${child_home}" ]; then
    fail "child HOME was not cleaned up: ${child_home}"
  fi
}
