#!/usr/bin/env bash
# shellcheck disable=SC2094

font_metadata_path() {
  if [ -n "${DOTFILES_FONT_METADATA:-}" ]; then
    printf '%s' "${DOTFILES_FONT_METADATA}"
    return 0
  fi

  script_dir="$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
  printf '%s/../fonts/checksums' "${script_dir}"
}

font_data_home() {
  if [ -n "${XDG_DATA_HOME:-}" ]; then
    printf '%s' "${XDG_DATA_HOME}"
    return 0
  fi
  if [ -z "${HOME:-}" ]; then
    error "HOME is required"
    return 1
  fi
  printf '%s/.local/share' "${HOME}"
}

font_install_dir() {
  data_home="$(font_data_home)" || return 1
  printf '%s/fonts/JetBrainsMonoNerdFont' "${data_home}"
}

font_read_metadata() {
  metadata_file="$1"

  if [ ! -f "${metadata_file}" ] || [ -L "${metadata_file}" ]; then
    error "missing font metadata: ${metadata_file}"
    return 1
  fi

  line_number=0
  while IFS= read -r line || [ -n "${line}" ]; do
    line_number=$((line_number + 1))
    if is_blank_line "${line}"; then
      continue
    fi
    trimmed_line="$(trim_leading_spaces "${line}")"
    case "${trimmed_line}" in
      "#"*) continue ;;
    esac
    if has_control_chars "${line}"; then
      manifest_error "${metadata_file}" "${line_number}" "control characters are not allowed"
      return 1
    fi
    case "${line}" in
      *"|"*"|"*"|"*"|"*)
        FONT_NAME="${line%%|*}"
        rest="${line#*|}"
        FONT_VERSION="${rest%%|*}"
        rest="${rest#*|}"
        FONT_ASSET="${rest%%|*}"
        rest="${rest#*|}"
        FONT_SHA256="${rest%%|*}"
        FONT_URL="${rest#*|}"
        case "${FONT_URL}" in
          *"|"*)
            manifest_error "${metadata_file}" "${line_number}" "expected five fields"
            return 1
            ;;
        esac
        ;;
      *)
        manifest_error "${metadata_file}" "${line_number}" "expected five fields"
        return 1
        ;;
    esac
    case "${FONT_NAME}" in
      JetBrainsMonoNerdFont) ;;
      *)
        manifest_error "${metadata_file}" "${line_number}" "unsupported font name"
        return 1
        ;;
    esac
    case "${FONT_VERSION}" in
      v[0-9]*.[0-9]*.[0-9]*) ;;
      *)
        manifest_error "${metadata_file}" "${line_number}" "invalid font version"
        return 1
        ;;
    esac
    case "${FONT_ASSET}" in
      JetBrainsMono.zip) ;;
      *)
        manifest_error "${metadata_file}" "${line_number}" "invalid font asset"
        return 1
        ;;
    esac
    case "${FONT_URL}" in
      https://*) ;;
      *)
        manifest_error "${metadata_file}" "${line_number}" "font URL must be HTTPS"
        return 1
        ;;
    esac
    case "${FONT_SHA256}" in
      [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
        ;;
      *)
        manifest_error "${metadata_file}" "${line_number}" "font checksum must be 64 lowercase hex characters"
        return 1
        ;;
    esac
    return 0
  done <"${metadata_file}"

  error "font metadata has no records: ${metadata_file}"
  return 1
}

font_installed() {
  install_dir="$(font_install_dir)" || return 1

  [ -f "${install_dir}/.version" ] || return 1
  [ "$(cat "${install_dir}/.version")" = "v3.5.0" ] || return 1
  find "${install_dir}" \( -name '*.ttf' -o -name '*.otf' \) -type f -print 2>/dev/null | sed -n '1p' | grep . >/dev/null 2>&1
}

font_plan() {
  platform="$1"

  case "${platform}" in
    macos)
      return 0
      ;;
    debian|linux)
      ;;
    *)
      error "unsupported font platform: ${platform}"
      return 1
      ;;
  esac

  metadata_file="$(font_metadata_path)" || return 1
  font_read_metadata "${metadata_file}" || return 1

  if font_installed; then
    plan_append fonts noop JetBrainsMonoNerdFont
  else
    plan_append fonts install JetBrainsMonoNerdFont
  fi
}

font_archive_safe_member() {
  member="$1"

  case "${member}" in
    ""|/*|*"/../"*|../*|*".."|*"\\"*|*":"*)
      return 1
      ;;
  esac

  remaining="${member}"
  while :; do
    segment="${remaining%%/*}"
    case "${segment}" in
      ""|"."|"..")
        return 1
        ;;
    esac
    if [ "${segment}" = "${remaining}" ]; then
      break
    fi
    remaining="${remaining#*/}"
  done
}

font_archive_has_font_suffix() {
  member="$1"

  case "${member}" in
    *.ttf|*.otf) return 0 ;;
    *) return 1 ;;
  esac
}

font_validate_archive_members() {
  archive="$1"
  font_member_count=0

  unzip -Z1 "${archive}" |
    while IFS= read -r member || [ -n "${member}" ]; do
      font_archive_safe_member "${member}" || {
        error "unsafe font archive member: ${member}"
        exit 2
      }
      if font_archive_has_font_suffix "${member}"; then
        font_member_count=$((font_member_count + 1))
      fi
    done
  status=$?
  if [ "${status}" -ne 0 ]; then
    return 1
  fi

  if ! unzip -Z1 "${archive}" | grep -E '\.(ttf|otf)$' >/dev/null 2>&1; then
    error "font archive contains no font files"
    return 1
  fi
}

font_archive_checksum() {
  archive="$1"

  shasum -a 256 "${archive}" | sed 's/ .*//'
}

font_cleanup_temp() {
  if [ -n "${FONT_TEMP_ARCHIVE:-}" ]; then
    rm -f "${FONT_TEMP_ARCHIVE}"
  fi
  if [ -n "${FONT_TEMP_DIR:-}" ]; then
    rm -rf "${FONT_TEMP_DIR}"
  fi
}

font_install_linux() {
  metadata_file="$1"

  font_read_metadata "${metadata_file}" || return 1
  install_dir="$(font_install_dir)" || return 1
  parent_dir="$(dirname -- "${install_dir}")"
  mkdir -p "${parent_dir}" || return 1

  FONT_TEMP_ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/dotfiles-font.XXXXXX")" || return 1
  FONT_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-font-extract.XXXXXX")" || {
    rm -f "${FONT_TEMP_ARCHIVE}"
    FONT_TEMP_ARCHIVE=""
    return 1
  }
  trap font_cleanup_temp RETURN

  curl -fsSL "${FONT_URL}" -o "${FONT_TEMP_ARCHIVE}" || {
    trap - RETURN
    font_cleanup_temp
    FONT_TEMP_ARCHIVE=""
    FONT_TEMP_DIR=""
    return 1
  }

  actual_sha256="$(font_archive_checksum "${FONT_TEMP_ARCHIVE}")" || {
    trap - RETURN
    font_cleanup_temp
    FONT_TEMP_ARCHIVE=""
    FONT_TEMP_DIR=""
    return 1
  }
  if [ "${actual_sha256}" != "${FONT_SHA256}" ]; then
    error "font checksum mismatch for ${FONT_ASSET}"
    trap - RETURN
    font_cleanup_temp
    FONT_TEMP_ARCHIVE=""
    FONT_TEMP_DIR=""
    return 1
  fi

  font_validate_archive_members "${FONT_TEMP_ARCHIVE}" || {
    trap - RETURN
    font_cleanup_temp
    FONT_TEMP_ARCHIVE=""
    FONT_TEMP_DIR=""
    return 1
  }

  unzip -q "${FONT_TEMP_ARCHIVE}" '*.ttf' '*.otf' -d "${FONT_TEMP_DIR}" || {
    trap - RETURN
    font_cleanup_temp
    FONT_TEMP_ARCHIVE=""
    FONT_TEMP_DIR=""
    return 1
  }

  rm -rf "${install_dir}" || {
    trap - RETURN
    font_cleanup_temp
    FONT_TEMP_ARCHIVE=""
    FONT_TEMP_DIR=""
    return 1
  }
  mkdir -p "${install_dir}" || {
    trap - RETURN
    font_cleanup_temp
    FONT_TEMP_ARCHIVE=""
    FONT_TEMP_DIR=""
    return 1
  }
  find "${FONT_TEMP_DIR}" \( -name '*.ttf' -o -name '*.otf' \) -type f -exec cp {} "${install_dir}/" \; || {
    trap - RETURN
    font_cleanup_temp
    FONT_TEMP_ARCHIVE=""
    FONT_TEMP_DIR=""
    return 1
  }
  printf '%s\n' "${FONT_VERSION}" >"${install_dir}/.version" || {
    trap - RETURN
    font_cleanup_temp
    FONT_TEMP_ARCHIVE=""
    FONT_TEMP_DIR=""
    return 1
  }

  fc-cache -f "${install_dir}" || {
    trap - RETURN
    font_cleanup_temp
    FONT_TEMP_ARCHIVE=""
    FONT_TEMP_DIR=""
    return 1
  }

  trap - RETURN
  font_cleanup_temp
  FONT_TEMP_ARCHIVE=""
  FONT_TEMP_DIR=""
}
