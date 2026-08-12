#!/usr/bin/env bash

set -u

error() {
  printf '%s\n' "$*" >&2
}

setup_usage() {
  cat <<'EOF'
Usage: setup.sh [--dry-run] [--skip-packages] [--set-default-shell] [--help]

Options:
  --dry-run            Print the validated plan and exit without prompting.
  --skip-packages      Skip package planning and installation.
  --set-default-shell  Change the login shell to the validated zsh path.
  --help              Show this help.
EOF
}

setup_phase() {
  phase="$1"

  if [ -n "${DOTFILES_PHASE_LOG:-}" ]; then
    printf '%s\n' "${phase}" >>"${DOTFILES_PHASE_LOG}"
  fi
}

setup_root() {
  script_dir="$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
  printf '%s\n' "${script_dir}"
}

setup_data_root() {
  if [ -n "${XDG_DATA_HOME:-}" ]; then
    printf '%s/dotfiles' "${XDG_DATA_HOME}"
    return 0
  fi
  if [ -z "${HOME:-}" ]; then
    error "HOME is required"
    return 1
  fi
  printf '%s/.local/share/dotfiles' "${HOME}"
}

setup_state_root() {
  if [ -n "${XDG_STATE_HOME:-}" ]; then
    printf '%s/dotfiles' "${XDG_STATE_HOME}"
    return 0
  fi
  if [ -z "${HOME:-}" ]; then
    error "HOME is required"
    return 1
  fi
  printf '%s/.local/state/dotfiles' "${HOME}"
}

setup_plan_has() {
  phase="$1"
  action="$2"

  if [ -z "${DOTFILES_PLAN_FILE:-}" ] || [ ! -f "${DOTFILES_PLAN_FILE}" ]; then
    return 1
  fi
  grep -F -- "${phase}	${action}	" "${DOTFILES_PLAN_FILE}" >/dev/null 2>&1
}

setup_plan_has_link_changes() {
  setup_plan_has links link || setup_plan_has links backup || setup_plan_has links mkdir
}

setup_backup_root() {
  backup_parent="${SETUP_STATE_ROOT}/backups"
  backup_stamp="$(date +%Y%m%d%H%M%S)" || return 1
  printf '%s/%s.%s' "${backup_parent}" "${backup_stamp}" "$$"
}

setup_confirm() {
  prompt="$1"

  if [ "${DOTFILES_TEST_MODE:-0}" = 1 ] && [ -n "${DOTFILES_TEST_INTERACTIVE:-}" ]; then
    case "${DOTFILES_TEST_INTERACTIVE}" in
    1) ;;
    *)
      error "setup requires an interactive terminal"
      return 1
      ;;
    esac
    answer="${DOTFILES_TEST_CONFIRM_RESPONSE:-}"
  else
    if [ ! -t 0 ]; then
      error "setup requires an interactive terminal"
      return 1
    fi
    printf '%s [y/N] ' "${prompt}" >&2
    IFS= read -r answer || {
      error "setup aborted"
      return 1
    }
  fi

  case "${answer}" in
  y | Y | yes | YES)
    return 0
    ;;
  *)
    error "setup aborted"
    return 1
    ;;
  esac
}

setup_parse_args() {
  SETUP_DRY_RUN=0
  SETUP_SKIP_PACKAGES=0
  SETUP_SET_DEFAULT_SHELL=0
  SETUP_HELP=0

  seen_dry_run=0
  seen_skip_packages=0
  seen_set_default_shell=0
  seen_help=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
    --dry-run)
      if [ "${seen_dry_run}" = 1 ]; then
        error "duplicate flag: --dry-run"
        return 2
      fi
      seen_dry_run=1
      SETUP_DRY_RUN=1
      ;;
    --skip-packages)
      if [ "${seen_skip_packages}" = 1 ]; then
        error "duplicate flag: --skip-packages"
        return 2
      fi
      seen_skip_packages=1
      SETUP_SKIP_PACKAGES=1
      ;;
    --set-default-shell)
      if [ "${seen_set_default_shell}" = 1 ]; then
        error "duplicate flag: --set-default-shell"
        return 2
      fi
      seen_set_default_shell=1
      SETUP_SET_DEFAULT_SHELL=1
      ;;
    --help)
      if [ "${seen_help}" = 1 ]; then
        error "duplicate flag: --help"
        return 2
      fi
      seen_help=1
      SETUP_HELP=1
      ;;
    *)
      error "unknown flag: $1"
      return 2
      ;;
    esac
    shift
  done
}

setup_plan_packages() {
  case "${SETUP_PLATFORM}" in
  debian)
    debian_plan_packages "${SETUP_ROOT}/manifest/packages.debian"
    ;;
  macos)
    macos_plan_homebrew || return "$?"
    macos_plan_packages "${SETUP_ROOT}/manifest/packages.macos"
    ;;
  *)
    error "unsupported platform: ${SETUP_PLATFORM}"
    return 1
    ;;
  esac
}

setup_apply_packages() {
  if [ "${SETUP_SKIP_PACKAGES}" = 1 ]; then
    return 0
  fi

  case "${SETUP_PLATFORM}" in
  debian)
    debian_install_packages "${SETUP_ROOT}/manifest/packages.debian"
    ;;
  macos)
    if setup_plan_has packages install-homebrew; then
      DOTFILES_ASSUME_YES=1 macos_ensure_homebrew || return "$?"
    fi
    macos_install_packages "${SETUP_ROOT}/manifest/packages.macos"
    ;;
  *)
    error "unsupported platform: ${SETUP_PLATFORM}"
    return 1
    ;;
  esac
}

setup_apply_fonts() {
  case "${SETUP_PLATFORM}" in
  macos)
    return 0
    ;;
  debian)
    if setup_plan_has fonts install; then
      font_install_linux "${SETUP_ROOT}/fonts/checksums"
    fi
    ;;
  *)
    error "unsupported platform: ${SETUP_PLATFORM}"
    return 1
    ;;
  esac
}

setup_preflight() {
  SETUP_PLATFORM="$(detect_platform)" || return "$?"
  SETUP_DATA_ROOT="$(setup_data_root)" || return "$?"
  SETUP_STATE_ROOT="$(setup_state_root)" || return "$?"
  if [ "${SETUP_SET_DEFAULT_SHELL}" = 1 ]; then
    SETUP_ZSH_PATH="$(platform_zsh_path "${SETUP_PLATFORM}")" || return "$?"
  else
    SETUP_ZSH_PATH=""
  fi

  plan_reset || return "$?"
  if [ "${SETUP_SKIP_PACKAGES}" != 1 ]; then
    setup_plan_packages || return "$?"
  fi
  plugins_plan "${SETUP_ROOT}/manifest/plugins.conf" "${SETUP_DATA_ROOT}" || return "$?"
  font_plan "${SETUP_PLATFORM}" || return "$?"
  links_plan "${SETUP_ROOT}" "${SETUP_ROOT}/manifest/links.conf" || return "$?"
}

setup_cleanup() {
  if [ -n "${SETUP_TMPDIR:-}" ]; then
    rm -rf "${SETUP_TMPDIR}"
  fi
  if [ -n "${DOTFILES_PLAN_FILE:-}" ]; then
    rm -f "${DOTFILES_PLAN_FILE}"
  fi
}

setup_main() {
  setup_phase parse
  setup_parse_args "$@"
  status=$?
  if [ "${status}" -ne 0 ]; then
    return "${status}"
  fi
  if [ "${SETUP_HELP}" = 1 ]; then
    setup_usage
    return 0
  fi

  SETUP_ROOT="$(setup_root)" || return "$?"
  # shellcheck source=script/common.sh
  . "${SETUP_ROOT}/script/common.sh" || return 1
  # shellcheck source=script/macos.sh
  . "${SETUP_ROOT}/script/macos.sh" || return 1
  # shellcheck source=script/debian.sh
  . "${SETUP_ROOT}/script/debian.sh" || return 1
  # shellcheck source=script/plugins.sh
  . "${SETUP_ROOT}/script/plugins.sh" || return 1
  # shellcheck source=script/fonts.sh
  . "${SETUP_ROOT}/script/fonts.sh" || return 1
  # shellcheck source=script/links.sh
  . "${SETUP_ROOT}/script/links.sh" || return 1
  # shellcheck source=script/doctor.sh
  . "${SETUP_ROOT}/script/doctor.sh" || return 1

  SETUP_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-setup.XXXXXX")" || return 1
  trap setup_cleanup EXIT HUP INT TERM

  setup_phase preflight
  setup_preflight || return "$?"

  setup_phase print-plan
  plan_print

  if [ "${SETUP_DRY_RUN}" = 1 ]; then
    return 0
  fi

  setup_phase confirm
  setup_confirm "Apply this dotfiles plan?" || return "$?"

  setup_phase packages
  setup_apply_packages || return "$?"

  setup_phase plugins
  plugins_apply "${SETUP_ROOT}/manifest/plugins.conf" "${SETUP_DATA_ROOT}" || return "$?"

  setup_phase fonts
  setup_apply_fonts || return "$?"

  setup_phase links
  SETUP_BACKUP_ROOT="$(setup_backup_root)" || return "$?"
  SETUP_LINK_JOURNAL="${SETUP_TMPDIR}/links.journal"
  if setup_plan_has_link_changes; then
    printf 'backup root: %s\n' "${SETUP_BACKUP_ROOT}" >&2
  fi
  links_apply "${SETUP_ROOT}" "${SETUP_ROOT}/manifest/links.conf" "${SETUP_BACKUP_ROOT}" "${SETUP_LINK_JOURNAL}" || return "$?"

  if [ "${SETUP_SET_DEFAULT_SHELL}" = 1 ]; then
    setup_phase chsh
    chsh -s "${SETUP_ZSH_PATH}" || return "$?"
  fi

  setup_phase doctor
  DOCTOR_SKIP_PACKAGES="${SETUP_SKIP_PACKAGES}" doctor_main "${SETUP_ROOT}"
}

setup_main "$@"
