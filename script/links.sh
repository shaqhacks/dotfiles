#!/usr/bin/env bash

links_source_path() {
  repo_root="$1"
  relative_source="$2"

  repo_canonical="$(canonical_dir "${repo_root}")" || return 1
  source_path="${repo_canonical}/${relative_source}"
  source_dir="$(dirname -- "${source_path}")"
  source_base="$(basename -- "${source_path}")"
  source_dir_canonical="$(canonical_dir "${source_dir}")" || return 1
  printf '%s/%s' "${source_dir_canonical}" "${source_base}"
}

links_destination_path() {
  relative_destination="$1"

  home_canonical="$(canonical_dir "${HOME}")" || return 1
  printf '%s/%s' "${home_canonical}" "${relative_destination}"
}

links_parent_missing() {
  destination_path="$1"
  parent_path="$(dirname -- "${destination_path}")"

  if [ -d "${parent_path}" ]; then
    return 1
  fi
  printf '%s' "${parent_path}"
}

links_plan_record() {
  relative_source="$1"
  relative_destination="$2"

  source_absolute="$(links_source_path "${LINKS_REPO_ROOT}" "${relative_source}")" || return 1
  destination_absolute="$(links_destination_path "${relative_destination}")" || return 1

  if [ -L "${destination_absolute}" ]; then
    current_target="$(readlink "${destination_absolute}")" || return 1
    if [ "${current_target}" = "${source_absolute}" ]; then
      plan_append links noop "${relative_destination}" || return 1
      return 0
    fi
  fi

  parent_missing="$(links_parent_missing "${destination_absolute}")"
  if [ -n "${parent_missing}" ]; then
    plan_append links mkdir "${relative_destination}" || return 1
  fi

  if [ -e "${destination_absolute}" ] || [ -L "${destination_absolute}" ]; then
    plan_append links backup "${relative_destination}" || return 1
  fi
  plan_append links link "${relative_destination}"
}

links_plan() {
  LINKS_REPO_ROOT="$1"
  links_manifest="$2"

  manifest_each links "${links_manifest}" links_plan_record
}

links_append_preflight_record() {
  relative_source="$1"
  relative_destination="$2"

  source_absolute="$(links_source_path "${LINKS_REPO_ROOT}" "${relative_source}")" || return 1
  destination_absolute="$(links_destination_path "${relative_destination}")" || return 1
  parent_path="$(dirname -- "${destination_absolute}")"
  backup_path="${LINKS_BACKUP_ROOT}/${relative_destination}"

  reject_journal_field "${source_absolute}" source || return 1
  reject_journal_field "${destination_absolute}" destination || return 1
  reject_journal_field "${backup_path}" backup || return 1

  if [ -L "${destination_absolute}" ]; then
    current_target="$(readlink "${destination_absolute}")" || return 1
    if [ "${current_target}" = "${source_absolute}" ]; then
      printf 'noop\t%s\t%s\t%s\t%s\n' "${source_absolute}" "${destination_absolute}" "${backup_path}" "${parent_path}" >>"${LINKS_PREFLIGHT_FILE}"
      return 0
    fi
  fi

  if [ -e "${backup_path}" ] || [ -L "${backup_path}" ]; then
    error "backup path already exists: ${backup_path}"
    return 1
  fi

  probe="${parent_path}"
  while [ ! -e "${probe}" ]; do
    next_probe="$(dirname -- "${probe}")"
    if [ "${next_probe}" = "${probe}" ]; then
      break
    fi
    probe="${next_probe}"
  done
  if [ ! -d "${probe}" ]; then
    error "destination parent is not a directory: ${parent_path}"
    return 1
  fi

  printf 'link\t%s\t%s\t%s\t%s\n' "${source_absolute}" "${destination_absolute}" "${backup_path}" "${parent_path}" >>"${LINKS_PREFLIGHT_FILE}"
}

links_journal() {
  operation="$1"
  destination="$2"
  backup="$3"

  reject_journal_field "${operation}" operation || return 1
  reject_journal_field "${destination}" destination || return 1
  reject_journal_field "${backup}" backup || return 1
  printf '%s\t%s\t%s\n' "${operation}" "${destination}" "${backup}" >>"${LINKS_JOURNAL}"
}

links_maybe_fail_after_mutation() {
  if [ -n "${DOTFILES_LINKS_FAIL_AFTER_MUTATIONS:-}" ]; then
    LINKS_MUTATION_COUNT=$((LINKS_MUTATION_COUNT + 1))
    if [ "${LINKS_MUTATION_COUNT}" -ge "${DOTFILES_LINKS_FAIL_AFTER_MUTATIONS}" ]; then
      error "injected link failure after mutation ${LINKS_MUTATION_COUNT}"
      return 1
    fi
  fi
}

links_record_mkdir() {
  local mkdir_path
  local mkdir_parent

  mkdir_path="$1"

  if [ -d "${mkdir_path}" ]; then
    return 0
  fi
  mkdir_parent="$(dirname -- "${mkdir_path}")"
  if [ ! -d "${mkdir_parent}" ]; then
    links_record_mkdir "${mkdir_parent}" || return 1
  fi
  mkdir "${mkdir_path}" || return 1
  links_journal mkdir "${mkdir_path}" "" || return 1
  links_maybe_fail_after_mutation
}

links_apply_record() {
  source_absolute="$1"
  destination_absolute="$2"
  backup_path="$3"
  parent_path="$4"

  if [ -L "${destination_absolute}" ]; then
    current_target="$(readlink "${destination_absolute}")" || return 1
    if [ "${current_target}" = "${source_absolute}" ]; then
      return 0
    fi
  fi

  links_record_mkdir "${parent_path}" || return 1

  if [ -e "${destination_absolute}" ] || [ -L "${destination_absolute}" ]; then
    backup_parent="$(dirname -- "${backup_path}")"
    links_record_mkdir "${backup_parent}" || return 1
    mv "${destination_absolute}" "${backup_path}" || return 1
    links_journal backup "${destination_absolute}" "${backup_path}" || return 1
    links_maybe_fail_after_mutation || return 1
  fi

  ln -s "${source_absolute}" "${destination_absolute}" || return 1
  links_journal link "${destination_absolute}" "" || return 1
  links_maybe_fail_after_mutation
}

links_apply_preflight() {
  LINKS_PREFLIGHT_FILE="$(mktemp "${TMPDIR:-/tmp}/dotfiles-links-preflight.XXXXXX")" || return 1
  export LINKS_PREFLIGHT_FILE
  manifest_each links "${LINKS_MANIFEST}" links_append_preflight_record || {
    rm -f "${LINKS_PREFLIGHT_FILE}"
    return 1
  }
}

links_apply() {
  LINKS_REPO_ROOT="$1"
  LINKS_MANIFEST="$2"
  LINKS_BACKUP_ROOT="$3"
  LINKS_JOURNAL="$4"

  repo_canonical="$(canonical_dir "${LINKS_REPO_ROOT}")" || {
    error "invalid repository root: ${LINKS_REPO_ROOT}"
    return 1
  }
  home_canonical="$(canonical_dir "${HOME}")" || {
    error "invalid HOME: ${HOME}"
    return 1
  }
  reject_journal_field "${repo_canonical}" repo || return 1
  reject_journal_field "${home_canonical}" home || return 1
  reject_journal_field "${LINKS_BACKUP_ROOT}" backup_root || return 1
  reject_journal_field "${LINKS_JOURNAL}" journal || return 1

  links_apply_preflight || return 1

  : >"${LINKS_JOURNAL}" || {
    rm -f "${LINKS_PREFLIGHT_FILE}"
    return 1
  }

  LINKS_MUTATION_COUNT=0
  while IFS='	' read -r action source_absolute destination_absolute backup_path parent_path; do
    case "${action}" in
      noop) ;;
      link)
        if ! links_apply_record "${source_absolute}" "${destination_absolute}" "${backup_path}" "${parent_path}"; then
          links_rollback "${LINKS_JOURNAL}"
          rm -f "${LINKS_PREFLIGHT_FILE}"
          return 1
        fi
        ;;
      *)
        error "unknown link preflight action: ${action}"
        links_rollback "${LINKS_JOURNAL}"
        rm -f "${LINKS_PREFLIGHT_FILE}"
        return 1
        ;;
    esac
  done <"${LINKS_PREFLIGHT_FILE}"

  rm -f "${LINKS_PREFLIGHT_FILE}"
}

links_rollback_record() {
  operation="$1"
  destination="$2"
  backup="$3"

  case "${operation}" in
    link)
      if [ -L "${destination}" ]; then
        rm "${destination}" || return 1
      fi
      ;;
    backup)
      if [ -e "${backup}" ] || [ -L "${backup}" ]; then
        if [ ! -e "${destination}" ] && [ ! -L "${destination}" ]; then
          mv "${backup}" "${destination}" || return 1
        fi
      fi
      ;;
    mkdir)
      if [ -d "${destination}" ]; then
        rmdir "${destination}" >/dev/null 2>&1 || :
      fi
      ;;
    "")
      ;;
    *)
      error "unknown rollback operation: ${operation}"
      return 1
      ;;
  esac
}

links_rollback() {
  journal="$1"

  if [ ! -f "${journal}" ]; then
    return 0
  fi

  line_count="$(wc -l <"${journal}" | tr -d ' ')"
  while [ "${line_count}" -gt 0 ]; do
    line="$(sed -n "${line_count}p" "${journal}")" || return 1
    IFS='	' read -r operation destination backup <<EOF
${line}
EOF
    links_rollback_record "${operation}" "${destination}" "${backup}" || return 1
    line_count=$((line_count - 1))
  done
}
