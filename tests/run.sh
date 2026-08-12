#!/usr/bin/env bash

set -u

LC_ALL=C
export LC_ALL

TEST_ROOT="$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd -P)"
export TEST_ROOT

# shellcheck source=tests/assert.sh
. "${TEST_ROOT}/assert.sh"

total=0
passed=0
failed=0

runner_tmp="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tests.XXXXXX")" || exit 1
suite_list="${runner_tmp}/suites"
test_list="${runner_tmp}/tests"

cleanup_runner() {
  rm -rf "${runner_tmp}"
}
trap cleanup_runner EXIT HUP INT TERM

add_suite() {
  suite_name="$1"

  case "${suite_name}" in
  "" | */* | *..* | *[![:print:]]*)
    printf 'not ok - invalid suite name: %s\n' "${suite_name}" >&2
    failed=$((failed + 1))
    return 1
    ;;
  esac

  suite_file="${TEST_ROOT}/${suite_name}_test.sh"

  if [ ! -f "${suite_file}" ]; then
    printf 'not ok - missing suite: %s\n' "${suite_name}" >&2
    failed=$((failed + 1))
    return 1
  fi

  validate_suite_file "${suite_file}" || return 1
  printf '%s\n' "${suite_file}" >>"${suite_list}"
}

validate_suite_file() {
  suite_file="$1"
  suite_dir="$(CDPATH='' cd -P -- "$(dirname -- "${suite_file}")" && pwd -P)" || return 1
  suite_base="$(basename -- "${suite_file}")"

  if [ "${suite_dir}" != "${TEST_ROOT}" ]; then
    printf 'not ok - outside test root: %s\n' "${suite_file}" >&2
    failed=$((failed + 1))
    return 1
  fi

  case "${suite_base}" in
  *_test.sh) ;;
  *)
    printf 'not ok - invalid test file: %s\n' "${suite_file}" >&2
    failed=$((failed + 1))
    return 1
    ;;
  esac

  if [ -L "${suite_file}" ]; then
    printf 'not ok - outside test root: %s\n' "${suite_file}" >&2
    failed=$((failed + 1))
    return 1
  fi
}

if [ "$#" -gt 0 ]; then
  : >"${suite_list}"
  for suite_name in "$@"; do
    add_suite "${suite_name}"
  done
else
  : >"${suite_list}"
  for suite_file in "${TEST_ROOT}"/*_test.sh; do
    if [ -f "${suite_file}" ]; then
      validate_suite_file "${suite_file}" && printf '%s\n' "${suite_file}" >>"${suite_list}"
    fi
  done
fi

: >"${test_list}"
while IFS= read -r suite_file; do
  sed -n 's/^\(test_[A-Za-z0-9_][A-Za-z0-9_]*\)().*/\1/p' "${suite_file}" |
    while IFS= read -r test_name; do
      printf '%s	%s\n' "${suite_file}" "${test_name}" >>"${test_list}"
    done
done <"${suite_list}"

total="$(wc -l <"${test_list}" | tr -d ' ')"
printf '1..%s\n' "${total}"

run_one_test() {
  suite_file="$1"
  test_name="$2"
  suite_base="$(basename -- "${suite_file}")"
  suite_name="${suite_base%_test.sh}"
  test_tmpdir="$(mktemp -d "${runner_tmp}/${suite_name}.${test_name}.XXXXXX")" || return 1

  (
    TEST_TMPDIR="${test_tmpdir}"
    export TEST_TMPDIR
    # shellcheck source=tests/assert.sh
    . "${TEST_ROOT}/assert.sh"
    # shellcheck disable=SC1090
    . "${suite_file}"
    "${test_name}"
  )
  status=$?

  rm -rf "${test_tmpdir}"
  return "${status}"
}

while IFS='	' read -r suite_file test_name; do
  test_number=$((passed + failed + 1))
  display_name="${test_name#test_}"

  if run_one_test "${suite_file}" "${test_name}"; then
    printf 'ok %s - %s\n' "${test_number}" "${display_name}"
    passed=$((passed + 1))
  else
    printf 'not ok %s - %s\n' "${test_number}" "${display_name}"
    failed=$((failed + 1))
  fi
done <"${test_list}"

printf '# summary: %s passed, %s failed\n' "${passed}" "${failed}"

if [ "${failed}" -gt 0 ]; then
  exit 1
fi
