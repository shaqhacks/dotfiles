#!/usr/bin/env bash

dotfiles_test_mode_enabled() {
  [ "${DOTFILES_TEST_MODE:-0}" = 1 ]
}

dotfiles_os_release_path() {
  if dotfiles_test_mode_enabled && [ -n "${DOTFILES_TEST_OS_RELEASE:-}" ]; then
    printf '%s' "${DOTFILES_TEST_OS_RELEASE}"
    return 0
  fi

  printf '/etc/os-release'
}

dotfiles_shells_path() {
  if dotfiles_test_mode_enabled && [ -n "${DOTFILES_TEST_SHELLS_FILE:-}" ]; then
    printf '%s' "${DOTFILES_TEST_SHELLS_FILE}"
    return 0
  fi

  printf '/etc/shells'
}

dotfiles_path_is_executable() {
  path="$1"

  if dotfiles_test_mode_enabled && [ "${path}" = "/bin/zsh" ] && [ "${DOTFILES_TEST_MACOS_ZSH_EXECUTABLE:-0}" = 1 ]; then
    return 0
  fi

  [ -x "${path}" ]
}

detect_platform() {
  if [ -n "${DOTFILES_TEST_PLATFORM:-}" ]; then
    if ! dotfiles_test_mode_enabled; then
      error "DOTFILES_TEST_PLATFORM requires DOTFILES_TEST_MODE=1"
      return 1
    fi
    case "${DOTFILES_TEST_PLATFORM}" in
      macos|debian)
        printf '%s\n' "${DOTFILES_TEST_PLATFORM}"
        return 0
        ;;
      *)
        error "unsupported test platform: ${DOTFILES_TEST_PLATFORM}"
        return 1
        ;;
    esac
  fi

  kernel="$(uname -s)" || return 1
  case "${kernel}" in
    Darwin)
      printf 'macos\n'
      ;;
    Linux)
      os_release="$(dotfiles_os_release_path)"
      if [ ! -f "${os_release}" ]; then
        error "missing os-release: ${os_release}"
        return 1
      fi
      os_id="$(sed -n 's/^ID=//p' "${os_release}" | sed -n '1p')"
      os_id="${os_id#\"}"
      os_id="${os_id%\"}"
      case "${os_id}" in
        debian|ubuntu)
          printf 'debian\n'
          ;;
        *)
          error "unsupported Linux distribution: ${os_id}"
          return 1
          ;;
      esac
      ;;
    *)
      error "unsupported system: ${kernel}"
      return 1
      ;;
  esac
}

platform_zsh_path() {
  platform="$1"

  case "${platform}" in
    macos)
      zsh_path="/bin/zsh"
      ;;
    debian)
      zsh_path="$(command -v zsh 2>/dev/null)" || {
        error "zsh is not installed"
        return 1
      }
      ;;
    *)
      error "unsupported platform: ${platform}"
      return 1
      ;;
  esac

  if ! dotfiles_path_is_executable "${zsh_path}"; then
    error "zsh path is not executable: ${zsh_path}"
    return 1
  fi

  shells_path="$(dotfiles_shells_path)"
  if [ ! -f "${shells_path}" ] || ! grep -F -x -- "${zsh_path}" "${shells_path}" >/dev/null 2>&1; then
    error "zsh path is not listed in ${shells_path}: ${zsh_path}"
    return 1
  fi

  printf '%s\n' "${zsh_path}"
}

macos_package_installed() {
  package_kind="$1"
  package_name="$2"

  case "${package_kind}" in
    formula)
      brew list --formula "${package_name}" >/dev/null 2>&1
      ;;
    cask)
      brew list --cask "${package_name}" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

macos_plan_package_record() {
  package_kind="$1"
  package_name="$2"

  if macos_package_installed "${package_kind}" "${package_name}"; then
    return 0
  fi

  plan_append packages install "${package_kind} ${package_name}"
}

macos_plan_packages() {
  manifest_path="$1"

  manifest_each macos "${manifest_path}" macos_plan_package_record
}

macos_plan_contains() {
  detail="$1"

  if [ -z "${DOTFILES_PLAN_FILE:-}" ] || [ ! -f "${DOTFILES_PLAN_FILE}" ]; then
    return 1
  fi

  grep -F -x -- "packages	install	${detail}" "${DOTFILES_PLAN_FILE}" >/dev/null 2>&1
}

macos_install_package_record() {
  package_kind="$1"
  package_name="$2"
  detail="${package_kind} ${package_name}"

  if ! macos_plan_contains "${detail}"; then
    return 0
  fi

  case "${package_kind}" in
    formula)
      brew install "${package_name}"
      ;;
    cask)
      brew install --cask "${package_name}"
      ;;
  esac
}

macos_install_packages() {
  manifest_path="$1"

  manifest_each macos "${manifest_path}" macos_install_package_record
}

macos_have_homebrew() {
  if dotfiles_test_mode_enabled && [ "${DOTFILES_STUB_BREW_ABSENT:-0}" = 1 ]; then
    return 1
  fi

  command -v brew >/dev/null 2>&1
}

dotfiles_confirm_run() {
  prompt="$1"

  if [ "${DOTFILES_ASSUME_YES:-0}" = 1 ]; then
    return 0
  fi

  printf '%s [y/N] ' "${prompt}" >&2
  IFS= read -r answer || return 1
  case "${answer}" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

macos_ensure_homebrew() {
  if macos_have_homebrew; then
    plan_append packages noop homebrew
    return 0
  fi

  installer_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  installer_path="$(mktemp "${TMPDIR:-/tmp}/homebrew-install.XXXXXX")" || return 1
  plan_append packages install-homebrew "${installer_url} -> ${installer_path}" || {
    rm -f "${installer_path}"
    return 1
  }

  curl -fsSL "${installer_url}" -o "${installer_path}" || {
    rm -f "${installer_path}"
    return 1
  }

  if ! dotfiles_confirm_run "Run Homebrew installer from ${installer_path}?"; then
    rm -f "${installer_path}"
    return 1
  fi

  /bin/bash "${installer_path}"
  status=$?
  rm -f "${installer_path}"
  return "${status}"
}
