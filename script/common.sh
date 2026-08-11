#!/usr/bin/env bash

manifest_error() {
  manifest_path="$1"
  line_number="$2"
  message="$3"

  printf '%s:%s: %s\n' "${manifest_path}" "${line_number}" "${message}" >&2
}

error() {
  printf '%s\n' "$*" >&2
}

has_control_chars() {
  case "$1" in
    *[![:print:]]*) return 0 ;;
    *) return 1 ;;
  esac
}

trim_leading_spaces() {
  value="$1"
  while :; do
    case "${value}" in
      " "*) value="${value# }" ;;
      *) break ;;
    esac
  done
  printf '%s' "${value}"
}

is_blank_line() {
  value="$1"
  while :; do
    case "${value}" in
      "") return 0 ;;
      " "*) value="${value# }" ;;
      *) return 1 ;;
    esac
  done
}

validate_relative_path() {
  relative_path="$1"

  case "${relative_path}" in
    ""|/*)
      return 1
      ;;
  esac
  if has_control_chars "${relative_path}"; then
    return 1
  fi

  remaining="${relative_path}"
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

canonical_dir() {
  dir_path="$1"
  CDPATH= cd -P -- "${dir_path}" 2>/dev/null && pwd -P
}

path_is_under() {
  child_path="$1"
  parent_path="$2"

  case "${child_path}" in
    "${parent_path}"|"${parent_path}"/*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_repo_source() {
  repo_root="$1"
  relative_path="$2"

  if ! validate_relative_path "${relative_path}"; then
    error "invalid repository source path: ${relative_path}"
    return 1
  fi

  repo_canonical="$(canonical_dir "${repo_root}")" || {
    error "invalid repository root: ${repo_root}"
    return 1
  }
  source_path="${repo_canonical}/${relative_path}"

  if [ ! -f "${source_path}" ] || [ -L "${source_path}" ]; then
    error "repository source is not a regular file: ${relative_path}"
    return 1
  fi

  source_dir="$(dirname -- "${source_path}")"
  source_base="$(basename -- "${source_path}")"
  source_dir_canonical="$(canonical_dir "${source_dir}")" || {
    error "invalid repository source directory: ${relative_path}"
    return 1
  }
  source_canonical="${source_dir_canonical}/${source_base}"

  if ! path_is_under "${source_canonical}" "${repo_canonical}"; then
    error "repository source escapes root: ${relative_path}"
    return 1
  fi
}

validate_home_destination() {
  relative_path="$1"

  if ! validate_relative_path "${relative_path}"; then
    error "invalid home destination path: ${relative_path}"
    return 1
  fi
  if [ -z "${HOME:-}" ]; then
    error "HOME is required"
    return 1
  fi

  home_canonical="$(canonical_dir "${HOME}")" || {
    error "invalid HOME: ${HOME}"
    return 1
  }

  destination_parent="$(dirname -- "${home_canonical}/${relative_path}")"
  probe="${destination_parent}"
  while [ ! -e "${probe}" ]; do
    next_probe="$(dirname -- "${probe}")"
    if [ "${next_probe}" = "${probe}" ]; then
      break
    fi
    probe="${next_probe}"
  done

  probe_canonical="$(canonical_dir "${probe}")" || {
    error "invalid destination parent: ${relative_path}"
    return 1
  }

  if ! path_is_under "${probe_canonical}" "${home_canonical}"; then
    error "home destination escapes HOME: ${relative_path}"
    return 1
  fi
}

validate_token() {
  token="$1"

  case "${token}" in
    ""|*[\|]*)
      return 1
      ;;
  esac
  if has_control_chars "${token}"; then
    return 1
  fi
}

validate_package_name() {
  package_name="$1"

  validate_token "${package_name}" || return 1
  case "${package_name}" in
    *[!A-Za-z0-9._+-]*)
      return 1
      ;;
  esac
}

validate_plugin_url() {
  plugin_url="$1"

  validate_token "${plugin_url}" || return 1
  case "${plugin_url}" in
    https://*.git) return 0 ;;
    *) return 1 ;;
  esac
}

validate_commit_id() {
  commit_id="$1"

  case "${commit_id}" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

seen_contains() {
  seen_file="$1"
  seen_key="$2"

  if [ ! -f "${seen_file}" ]; then
    return 1
  fi
  grep -F -x -- "${seen_key}" "${seen_file}" >/dev/null 2>&1
}

seen_add() {
  seen_file="$1"
  seen_key="$2"

  printf '%s\n' "${seen_key}" >>"${seen_file}"
}

parse_two_fields() {
  record="$1"

  case "${record}" in
    *"|"*)
      field1="${record%%|*}"
      field2="${record#*|}"
      case "${field2}" in
        *"|"*) return 1 ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

parse_four_fields() {
  record="$1"

  case "${record}" in
    *"|"*"|"*"|"*)
      field1="${record%%|*}"
      rest="${record#*|}"
      field2="${rest%%|*}"
      rest="${rest#*|}"
      field3="${rest%%|*}"
      field4="${rest#*|}"
      case "${field4}" in
        *"|"*) return 1 ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

manifest_repo_root() {
  manifest_path="$1"
  manifest_dir="$(dirname -- "${manifest_path}")"
  canonical_dir "${manifest_dir}/.."
}

manifest_each() {
  manifest_kind="$1"
  manifest_path="$2"
  callback="$3"

  case "${manifest_kind}" in
    links|macos|debian|plugins) ;;
    *)
      error "unknown manifest kind: ${manifest_kind}"
      return 1
      ;;
  esac
  if [ ! -f "${manifest_path}" ] || [ -L "${manifest_path}" ]; then
    error "missing manifest: ${manifest_path}"
    return 1
  fi

  seen_file="$(mktemp "${TMPDIR:-/tmp}/dotfiles-manifest-seen.XXXXXX")" || return 1
  repo_root="$(manifest_repo_root "${manifest_path}")" || {
    rm -f "${seen_file}"
    return 1
  }

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
      manifest_error "${manifest_path}" "${line_number}" "control characters are not allowed"
      rm -f "${seen_file}"
      return 1
    fi

    case "${manifest_kind}" in
      links)
        if ! parse_two_fields "${line}"; then
          manifest_error "${manifest_path}" "${line_number}" "expected two fields"
          rm -f "${seen_file}"
          return 1
        fi
        if ! validate_repo_source "${repo_root}" "${field1}"; then
          manifest_error "${manifest_path}" "${line_number}" "invalid repository source"
          rm -f "${seen_file}"
          return 1
        fi
        if ! validate_home_destination "${field2}"; then
          manifest_error "${manifest_path}" "${line_number}" "invalid home destination"
          rm -f "${seen_file}"
          return 1
        fi
        duplicate_key="dest:${field2}"
        ;;
      macos)
        if ! parse_two_fields "${line}"; then
          manifest_error "${manifest_path}" "${line_number}" "expected two fields"
          rm -f "${seen_file}"
          return 1
        fi
        case "${field1}" in
          formula|cask) ;;
          *)
            manifest_error "${manifest_path}" "${line_number}" "expected formula or cask"
            rm -f "${seen_file}"
            return 1
            ;;
        esac
        if ! validate_package_name "${field2}"; then
          manifest_error "${manifest_path}" "${line_number}" "invalid package name"
          rm -f "${seen_file}"
          return 1
        fi
        duplicate_key="package:${field2}"
        ;;
      debian)
        case "${line}" in
          *"|"*)
            manifest_error "${manifest_path}" "${line_number}" "expected one field"
            rm -f "${seen_file}"
            return 1
            ;;
        esac
        field1="${line}"
        if ! validate_package_name "${field1}"; then
          manifest_error "${manifest_path}" "${line_number}" "invalid package name"
          rm -f "${seen_file}"
          return 1
        fi
        duplicate_key="package:${field1}"
        ;;
      plugins)
        if ! parse_four_fields "${line}"; then
          manifest_error "${manifest_path}" "${line_number}" "expected four fields"
          rm -f "${seen_file}"
          return 1
        fi
        if ! validate_package_name "${field1}"; then
          manifest_error "${manifest_path}" "${line_number}" "invalid plugin name"
          rm -f "${seen_file}"
          return 1
        fi
        if ! validate_plugin_url "${field2}"; then
          manifest_error "${manifest_path}" "${line_number}" "plugin URL must be HTTPS"
          rm -f "${seen_file}"
          return 1
        fi
        if ! validate_commit_id "${field3}"; then
          manifest_error "${manifest_path}" "${line_number}" "plugin commit must be 40 lowercase hex characters"
          rm -f "${seen_file}"
          return 1
        fi
        if ! validate_relative_path "${field4}"; then
          manifest_error "${manifest_path}" "${line_number}" "invalid plugin entrypoint"
          rm -f "${seen_file}"
          return 1
        fi
        duplicate_key="plugin:${field1}"
        ;;
    esac

    if seen_contains "${seen_file}" "${duplicate_key}"; then
      manifest_error "${manifest_path}" "${line_number}" "duplicate manifest key"
      rm -f "${seen_file}"
      return 1
    fi
    seen_add "${seen_file}" "${duplicate_key}"

    case "${manifest_kind}" in
      links|macos) "${callback}" "${field1}" "${field2}" ;;
      debian) "${callback}" "${field1}" ;;
      plugins) "${callback}" "${field1}" "${field2}" "${field3}" "${field4}" ;;
    esac || {
      rm -f "${seen_file}"
      return 1
    }
  done <"${manifest_path}"

  rm -f "${seen_file}"
}

plan_reset() {
  if [ -n "${DOTFILES_PLAN_FILE:-}" ]; then
    rm -f "${DOTFILES_PLAN_FILE}"
  fi
  DOTFILES_PLAN_FILE="$(mktemp "${TMPDIR:-/tmp}/dotfiles-plan.XXXXXX")" || return 1
  export DOTFILES_PLAN_FILE
}

plan_append() {
  phase="$1"
  action="$2"
  detail="$3"

  if [ -z "${DOTFILES_PLAN_FILE:-}" ]; then
    plan_reset || return 1
  fi
  if has_control_chars "${phase}" || has_control_chars "${action}" || has_control_chars "${detail}"; then
    error "plan fields must not contain control characters"
    return 1
  fi
  printf '%s\t%s\t%s\n' "${phase}" "${action}" "${detail}" >>"${DOTFILES_PLAN_FILE}"
}

plan_print() {
  if [ -z "${DOTFILES_PLAN_FILE:-}" ] || [ ! -f "${DOTFILES_PLAN_FILE}" ]; then
    return 0
  fi
  cat "${DOTFILES_PLAN_FILE}"
}
