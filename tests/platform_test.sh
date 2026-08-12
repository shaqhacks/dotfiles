# shellcheck shell=bash

COMMON_SH="${TEST_ROOT}/../script/common.sh"
MACOS_SH="${TEST_ROOT}/../script/macos.sh"
DEBIAN_SH="${TEST_ROOT}/../script/debian.sh"
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

  if [ -e "${path}" ]; then
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

load_platforms() {
  if [ ! -f "${COMMON_SH}" ]; then
    fail "missing common helpers: ${COMMON_SH}"
    return 1
  fi
  if [ ! -f "${MACOS_SH}" ]; then
    fail "missing macOS adapter: ${MACOS_SH}"
    return 1
  fi
  if [ ! -f "${DEBIAN_SH}" ]; then
    fail "missing Debian adapter: ${DEBIAN_SH}"
    return 1
  fi

  # shellcheck source=../script/common.sh
  # shellcheck disable=SC1091
  . "${COMMON_SH}"
  # shellcheck source=../script/macos.sh
  # shellcheck disable=SC1091
  . "${MACOS_SH}"
  # shellcheck source=../script/debian.sh
  # shellcheck disable=SC1091
  . "${DEBIAN_SH}"
}

setup_stubs() {
  DOTFILES_STUB_LOG="${TEST_TMPDIR}/stub.log"
  : >"${DOTFILES_STUB_LOG}" || return 1
  PATH="${FIXTURE_BIN}:${PATH}"
  DOTFILES_TEST_MODE=1
  export DOTFILES_STUB_LOG PATH DOTFILES_TEST_MODE
}

make_os_release() {
  DOTFILES_TEST_OS_RELEASE="${TEST_TMPDIR}/os-release"
  export DOTFILES_TEST_OS_RELEASE
  write_file "${DOTFILES_TEST_OS_RELEASE}" "$@"
}

make_shells() {
  DOTFILES_TEST_SHELLS_FILE="${TEST_TMPDIR}/shells"
  export DOTFILES_TEST_SHELLS_FILE
  write_file "${DOTFILES_TEST_SHELLS_FILE}" "$@"
}

test_detect_platform_reports_macos_from_uname() {
  load_platforms || return 1
  setup_stubs || return 1
  DOTFILES_STUB_UNAME=Darwin
  export DOTFILES_STUB_UNAME

  assert_eq "macos" "$(detect_platform)" "Darwin platform"
}

test_detect_platform_reports_debian_and_ubuntu_from_os_release() {
  load_platforms || return 1
  setup_stubs || return 1
  DOTFILES_STUB_UNAME=Linux
  export DOTFILES_STUB_UNAME

  make_os_release 'ID=debian'
  assert_eq "debian" "$(detect_platform)" "Debian platform" || return 1

  make_os_release 'ID=ubuntu'
  assert_eq "debian" "$(detect_platform)" "Ubuntu platform"
}

test_detect_platform_rejects_unsupported_linux_and_missing_os_release() {
  load_platforms || return 1
  setup_stubs || return 1
  DOTFILES_STUB_UNAME=Linux
  export DOTFILES_STUB_UNAME

  make_os_release 'ID=fedora'
  assert_fails detect_platform || return 1

  DOTFILES_TEST_OS_RELEASE="${TEST_TMPDIR}/missing-os-release"
  export DOTFILES_TEST_OS_RELEASE
  assert_fails detect_platform
}

test_detect_platform_accepts_test_override_only_in_test_mode() {
  load_platforms || return 1
  setup_stubs || return 1
  DOTFILES_TEST_PLATFORM=debian
  export DOTFILES_TEST_PLATFORM
  assert_eq "debian" "$(detect_platform)" "test override" || return 1

  DOTFILES_TEST_MODE=0
  export DOTFILES_TEST_MODE
  assert_fails detect_platform
}

test_platform_zsh_path_checks_debian_path_and_shells_without_editing_shells() {
  load_platforms || return 1
  setup_stubs || return 1
  make_shells "${FIXTURE_BIN}/zsh"

  assert_eq "${FIXTURE_BIN}/zsh" "$(platform_zsh_path debian)" "Debian zsh path" || return 1

  make_shells '/bin/zsh'
  assert_fails platform_zsh_path debian || return 1
  assert_log_count 'chsh ' 0
}

test_platform_zsh_path_reports_macos_bin_zsh_when_shell_is_allowed() {
  load_platforms || return 1
  setup_stubs || return 1
  DOTFILES_TEST_MACOS_ZSH_EXECUTABLE=1
  export DOTFILES_TEST_MACOS_ZSH_EXECUTABLE
  make_shells '/bin/zsh'

  assert_eq "/bin/zsh" "$(platform_zsh_path macos)" "macOS zsh path"
}

test_macos_plan_packages_appends_only_missing_formulae_and_casks() {
  load_platforms || return 1
  setup_stubs || return 1
  manifest="${TEST_TMPDIR}/packages.macos"
  write_file "${manifest}" \
    'formula|git' \
    'formula|fzf' \
    'cask|kitty' \
    'cask|font-jetbrains-mono-nerd-font'
  DOTFILES_STUB_BREW_FORMULAS=git
  DOTFILES_STUB_BREW_CASKS=kitty
  export DOTFILES_STUB_BREW_FORMULAS DOTFILES_STUB_BREW_CASKS

  plan_reset || return 1
  macos_plan_packages "${manifest}" || return 1

  assert_eq "$(printf 'packages\tinstall\tformula fzf\npackages\tinstall\tcask font-jetbrains-mono-nerd-font')" "$(plan_print)" "macOS package plan"
}

test_macos_install_packages_installs_only_planned_packages() {
  load_platforms || return 1
  setup_stubs || return 1
  manifest="${TEST_TMPDIR}/packages.macos"
  write_file "${manifest}" \
    'formula|git' \
    'formula|fzf' \
    'cask|kitty'
  DOTFILES_STUB_BREW_FORMULAS=git
  DOTFILES_STUB_BREW_CASKS=''
  export DOTFILES_STUB_BREW_FORMULAS DOTFILES_STUB_BREW_CASKS

  plan_reset || return 1
  macos_plan_packages "${manifest}" || return 1
  : >"${DOTFILES_STUB_LOG}" || return 1
  macos_install_packages "${manifest}" || return 1

  assert_log_count 'brew install fzf' 1 || return 1
  assert_log_count 'brew install --cask kitty' 1 || return 1
  assert_log_count 'brew install git' 0
}

test_macos_install_packages_propagates_brew_failure() {
  load_platforms || return 1
  setup_stubs || return 1
  manifest="${TEST_TMPDIR}/packages.macos"
  write_file "${manifest}" 'formula|fail'

  plan_reset || return 1
  macos_plan_packages "${manifest}" || return 1
  assert_fails macos_install_packages "${manifest}"
}

test_macos_ensure_homebrew_downloads_temp_installer_and_removes_it_after_confirmed_run() {
  load_platforms || return 1
  setup_stubs || return 1
  DOTFILES_STUB_BREW_ABSENT=1
  DOTFILES_ASSUME_YES=1
  export DOTFILES_STUB_BREW_ABSENT DOTFILES_ASSUME_YES

  plan_reset || return 1
  macos_ensure_homebrew || return 1

  plan="$(plan_print)"
  case "${plan}" in
    *'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -> '*)
      ;;
    *)
      fail "Homebrew installer source was not disclosed in plan"
      return 1
      ;;
  esac
  installer_path="${plan##* -> }"
  assert_missing "${installer_path}" || return 1
  assert_contains "${DOTFILES_STUB_LOG}" 'curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o ' || return 1
  assert_not_contains "${DOTFILES_STUB_LOG}" '|'
}

test_macos_ensure_homebrew_propagates_download_failure_without_running_installer() {
  load_platforms || return 1
  setup_stubs || return 1
  DOTFILES_STUB_BREW_ABSENT=1
  DOTFILES_STUB_CURL_FAIL=1
  DOTFILES_ASSUME_YES=1
  export DOTFILES_STUB_BREW_ABSENT DOTFILES_STUB_CURL_FAIL DOTFILES_ASSUME_YES

  plan_reset || return 1
  assert_fails macos_ensure_homebrew || return 1
  assert_log_count 'curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o ' 1
}

test_debian_plan_packages_appends_only_missing_packages() {
  load_platforms || return 1
  setup_stubs || return 1
  manifest="${TEST_TMPDIR}/packages.debian"
  write_file "${manifest}" 'zsh' 'git' 'curl'
  DOTFILES_STUB_DPKG_PACKAGES=git
  export DOTFILES_STUB_DPKG_PACKAGES

  plan_reset || return 1
  debian_plan_packages "${manifest}" || return 1

  assert_eq "$(printf 'packages\tinstall\tapt zsh\npackages\tinstall\tapt curl')" "$(plan_print)" "Debian package plan"
}

test_debian_install_packages_runs_apt_update_once_and_installs_only_planned_packages() {
  load_platforms || return 1
  setup_stubs || return 1
  manifest="${TEST_TMPDIR}/packages.debian"
  write_file "${manifest}" 'zsh' 'git' 'curl'
  DOTFILES_STUB_DPKG_PACKAGES=git
  export DOTFILES_STUB_DPKG_PACKAGES

  plan_reset || return 1
  debian_plan_packages "${manifest}" || return 1
  : >"${DOTFILES_STUB_LOG}" || return 1
  debian_install_packages "${manifest}" || return 1

  assert_log_count 'sudo apt-get update' 1 || return 1
  assert_log_count 'sudo apt-get install -y zsh curl' 1 || return 1
  assert_log_count 'git' 0
}

test_debian_install_packages_propagates_sudo_failure() {
  load_platforms || return 1
  setup_stubs || return 1
  manifest="${TEST_TMPDIR}/packages.debian"
  write_file "${manifest}" 'zsh'
  DOTFILES_STUB_SUDO_FAIL=1
  export DOTFILES_STUB_SUDO_FAIL

  plan_reset || return 1
  debian_plan_packages "${manifest}" || return 1
  assert_fails debian_install_packages "${manifest}"
}
