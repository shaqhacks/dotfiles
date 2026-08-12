# shellcheck shell=bash

fail() {
  printf 'not ok - %s\n' "$*" >&2
  return 1
}

assert_eq() {
  expected="$1"
  actual="$2"
  message="${3:-values are equal}"

  if [ "${expected}" != "${actual}" ]; then
    fail "${message}: expected '${expected}', got '${actual}'"
    return 1
  fi
}

assert_file() {
  path="$1"

  if [ ! -f "${path}" ]; then
    fail "expected file: ${path}"
    return 1
  fi
}

assert_dir() {
  path="$1"

  if [ ! -d "${path}" ]; then
    fail "expected directory: ${path}"
    return 1
  fi
}

assert_symlink_target() {
  path="$1"
  expected="$2"

  if [ ! -L "${path}" ]; then
    fail "expected symlink: ${path}"
    return 1
  fi

  actual="$(readlink "${path}")" || return 1
  assert_eq "${expected}" "${actual}" "symlink target for ${path}"
}

assert_contains() {
  path="$1"
  needle="$2"

  assert_file "${path}" || return 1
  if ! grep -F -- "${needle}" "${path}" >/dev/null 2>&1; then
    fail "expected ${path} to contain: ${needle}"
    return 1
  fi
}

assert_not_contains() {
  path="$1"
  needle="$2"

  assert_file "${path}" || return 1
  if grep -F -- "${needle}" "${path}" >/dev/null 2>&1; then
    fail "expected ${path} not to contain: ${needle}"
    return 1
  fi
}

cleanup_test_home() {
  if [ -n "${DOTFILES_TEST_HOME_ROOT:-}" ]; then
    case "${DOTFILES_TEST_HOME_ROOT}" in
    "${TEST_TMPDIR}"/*)
      rm -rf "${DOTFILES_TEST_HOME_ROOT}"
      ;;
    *)
      fail "refusing to clean path outside TEST_TMPDIR: ${DOTFILES_TEST_HOME_ROOT}"
      return 1
      ;;
    esac
  fi
}

make_test_home() {
  if [ -z "${TEST_TMPDIR:-}" ]; then
    fail "TEST_TMPDIR is required"
    return 1
  fi

  DOTFILES_TEST_HOME_ROOT="$(mktemp -d "${TEST_TMPDIR}/home.XXXXXX")" || return 1
  HOME="${DOTFILES_TEST_HOME_ROOT}/home"
  XDG_CONFIG_HOME="${HOME}/.config"
  XDG_DATA_HOME="${HOME}/.local/share"
  XDG_STATE_HOME="${HOME}/.local/state"
  export DOTFILES_TEST_HOME_ROOT HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME

  mkdir -p "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}" || return 1
  trap cleanup_test_home EXIT HUP INT TERM
}
