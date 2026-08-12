#!/usr/bin/env bash

doctor_root() {
  script_dir="$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
  CDPATH='' cd -P -- "${script_dir}/.." 2>/dev/null && pwd -P
}

doctor_data_root() {
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

doctor_fail() {
  DOCTOR_STATUS=1
  error "$@"
}

doctor_ok() {
  printf 'ok %s\n' "$1"
}

doctor_check_package_debian() {
  package_name="$1"

  if ! debian_package_installed "${package_name}"; then
    doctor_fail "missing package: ${package_name}"
  fi
}

doctor_check_package_macos() {
  package_kind="$1"
  package_name="$2"

  if ! macos_package_installed "${package_kind}" "${package_name}"; then
    doctor_fail "missing package: ${package_name}"
  fi
}

doctor_check_packages() {
  if [ "${DOCTOR_SKIP_PACKAGES:-0}" = 1 ]; then
    return 0
  fi

  case "${DOCTOR_PLATFORM}" in
    debian)
      manifest_each debian "${DOCTOR_ROOT}/manifest/packages.debian" doctor_check_package_debian || return 1
      ;;
    macos)
      manifest_each macos "${DOCTOR_ROOT}/manifest/packages.macos" doctor_check_package_macos || return 1
      ;;
    *)
      doctor_fail "unsupported platform: ${DOCTOR_PLATFORM}"
      ;;
  esac
}

doctor_check_plugin() {
  plugin_name="$1"
  plugin_url="$2"
  commit_id="$3"
  entrypoint="$4"
  checkout="$(plugin_path "${DOCTOR_DATA_ROOT}" "${plugin_name}")"

  if [ ! -d "${checkout}" ]; then
    doctor_fail "missing plugin: ${plugin_name}"
    return 0
  fi
  if ! git -C "${checkout}" rev-parse --git-dir >/dev/null 2>&1; then
    doctor_fail "plugin is not a git repository: ${plugin_name}"
    return 0
  fi
  current_origin="$(plugin_git_origin "${checkout}")" || {
    doctor_fail "plugin origin is unavailable: ${plugin_name}"
    return 0
  }
  if [ "${current_origin}" != "${plugin_url}" ]; then
    doctor_fail "plugin origin mismatch: ${plugin_name}"
  fi
  current_commit="$(plugin_git_commit "${checkout}")" || {
    doctor_fail "plugin revision is unavailable: ${plugin_name}"
    return 0
  }
  if [ "${current_commit}" != "${commit_id}" ]; then
    doctor_fail "plugin revision mismatch: ${plugin_name}"
  fi
  if ! plugin_git_clean "${checkout}"; then
    doctor_fail "plugin checkout is dirty: ${plugin_name}"
  fi
  if [ ! -f "${checkout}/${entrypoint}" ]; then
    doctor_fail "plugin entrypoint is missing: ${plugin_name}/${entrypoint}"
  fi
}

doctor_check_plugins() {
  manifest_each plugins "${DOCTOR_ROOT}/manifest/plugins.conf" doctor_check_plugin
}

doctor_check_fonts() {
  case "${DOCTOR_PLATFORM}" in
    macos)
      return 0
      ;;
    debian)
      if ! font_installed; then
        doctor_fail "font is not installed: JetBrainsMonoNerdFont"
      fi
      ;;
    *)
      doctor_fail "unsupported platform: ${DOCTOR_PLATFORM}"
      ;;
  esac
}

doctor_check_link() {
  relative_source="$1"
  relative_destination="$2"

  source_absolute="$(links_source_path "${DOCTOR_ROOT}" "${relative_source}")" || {
    doctor_fail "link source is invalid: ${relative_source}"
    return 0
  }
  destination_absolute="$(links_destination_path "${relative_destination}")" || {
    doctor_fail "link destination is invalid: ${relative_destination}"
    return 0
  }
  if [ ! -L "${destination_absolute}" ]; then
    doctor_fail "link mismatch: ${relative_destination}"
    return 0
  fi
  current_target="$(readlink "${destination_absolute}")" || {
    doctor_fail "link mismatch: ${relative_destination}"
    return 0
  }
  if [ "${current_target}" != "${source_absolute}" ]; then
    doctor_fail "link mismatch: ${relative_destination}"
  fi
}

doctor_check_links() {
  manifest_each links "${DOCTOR_ROOT}/manifest/links.conf" doctor_check_link
}

doctor_load_helpers() {
  DOCTOR_ROOT="$1"
  # shellcheck source=common.sh
  # shellcheck disable=SC1091
  . "${DOCTOR_ROOT}/script/common.sh" || return 1
  # shellcheck source=macos.sh
  # shellcheck disable=SC1091
  . "${DOCTOR_ROOT}/script/macos.sh" || return 1
  # shellcheck source=debian.sh
  # shellcheck disable=SC1091
  . "${DOCTOR_ROOT}/script/debian.sh" || return 1
  # shellcheck source=plugins.sh
  # shellcheck disable=SC1091
  . "${DOCTOR_ROOT}/script/plugins.sh" || return 1
  # shellcheck source=fonts.sh
  # shellcheck disable=SC1091
  . "${DOCTOR_ROOT}/script/fonts.sh" || return 1
  # shellcheck source=links.sh
  # shellcheck disable=SC1091
  . "${DOCTOR_ROOT}/script/links.sh" || return 1
}

doctor_main() {
  if [ "$#" -gt 0 ]; then
    DOCTOR_ROOT="$1"
  else
    DOCTOR_ROOT="$(doctor_root)" || return "$?"
  fi

  doctor_load_helpers "${DOCTOR_ROOT}" || return "$?"
  DOCTOR_STATUS=0
  DOCTOR_DATA_ROOT="$(doctor_data_root)" || return "$?"
  DOCTOR_PLATFORM="$(detect_platform)" || return "$?"
  platform_zsh_path "${DOCTOR_PLATFORM}" >/dev/null || DOCTOR_STATUS=1
  doctor_ok platform

  doctor_check_packages || DOCTOR_STATUS=1
  doctor_ok packages
  doctor_check_plugins || DOCTOR_STATUS=1
  doctor_ok plugins
  doctor_check_fonts || DOCTOR_STATUS=1
  doctor_ok fonts
  doctor_check_links || DOCTOR_STATUS=1
  doctor_ok links

  return "${DOCTOR_STATUS}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  doctor_main "$@"
fi
