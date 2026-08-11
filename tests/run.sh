#!/usr/bin/env bash

set -u

TEST_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TESTS_DIR="${TESTS_DIR:-${TEST_ROOT}}"
export TEST_ROOT TESTS_DIR

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
  suite_file="${TESTS_DIR}/${suite_name}_test.sh"

  if [ ! -f "${suite_file}" ]; then
    printf 'not ok - missing suite: %s\n' "${suite_name}" >&2
    failed=$((failed + 1))
    return 1
  fi

  printf '%s\n' "${suite_file}" >>"${suite_list}"
}

if [ "$#" -gt 0 ]; then
  : >"${suite_list}"
  for suite_name in "$@"; do
    add_suite "${suite_name}"
  done
else
  find "${TESTS_DIR}" -type f -name '*_test.sh' | sort >"${suite_list}"
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
    . "${TEST_ROOT}/assert.sh"
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
