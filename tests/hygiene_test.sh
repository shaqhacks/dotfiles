# shellcheck shell=bash

HYGIENE_REPO_ROOT="${TEST_ROOT}/.."

hygiene_fail() {
  fail "$1"
  return 1
}

hygiene_tracked_files() {
  (
    cd "${HYGIENE_REPO_ROOT}" || exit 1
    git ls-files
  )
}

hygiene_scan_files() {
  hygiene_tracked_files |
    while IFS= read -r relative_path; do
      case "${relative_path}" in
      .gitignore | tests/hygiene_test.sh)
        ;;
      *)
        printf '%s\n' "${HYGIENE_REPO_ROOT}/${relative_path}"
        ;;
      esac
    done
}

hygiene_grep() {
  pattern="$1"
  message="$2"

  matches="$(hygiene_scan_files | xargs grep -nE -- "${pattern}" 2>/dev/null || true)"
  if [ -n "${matches}" ]; then
    printf '%s\n%s\n' "${message}" "${matches}" >&2
    return 1
  fi
}

hygiene_grep_filtered() {
  pattern="$1"
  allowed_pattern="$2"
  message="$3"

  matches="$(hygiene_scan_files | xargs grep -nE -- "${pattern}" 2>/dev/null | grep -vE -- "${allowed_pattern}" || true)"
  if [ -n "${matches}" ]; then
    printf '%s\n%s\n' "${message}" "${matches}" >&2
    return 1
  fi
}

hygiene_markdown_links() {
  (
    cd "${HYGIENE_REPO_ROOT}" || exit 1
    git ls-files '*.md'
  ) |
    while IFS= read -r markdown_file; do
      while IFS= read -r link_target; do
        case "${link_target}" in
        "" | \#* | http://* | https://* | mailto:* | /*)
          continue
          ;;
        esac
        link_path="${link_target%%#*}"
        link_path="${link_path%%\?*}"
        case "${link_path}" in
        "") continue ;;
        esac
        if [ ! -e "${HYGIENE_REPO_ROOT}/$(dirname -- "${markdown_file}")/${link_path}" ]; then
          printf '%s: broken relative link: %s\n' "${markdown_file}" "${link_target}" >&2
          return 1
        fi
      done <<EOF
$(sed -n 's/.*](\([^)]*\)).*/\1/p' "${HYGIENE_REPO_ROOT}/${markdown_file}")
EOF
    done
}

test_hygiene_required_repository_files_exist() {
  assert_file "${HYGIENE_REPO_ROOT}/README.md" || return 1
  assert_file "${HYGIENE_REPO_ROOT}/.github/workflows/ci.yml"
}

test_hygiene_rejects_private_paths_identity_secrets_placeholders_and_insecure_urls() {
  hygiene_grep '/Users/[A-Za-z0-9._-]+' "absolute macOS home paths are not allowed" || return 1
  hygiene_grep '/home/[A-Za-z0-9._-]+' "absolute Linux home paths are not allowed" || return 1
  hygiene_grep_filtered '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' '@example\.com' "private identity fields are not allowed" || return 1
  hygiene_grep_filtered '[A-Za-z0-9.-]+\.(local|internal|corp|lan|home|company|employer)\b' '(\.zshrc\.local|\.gitconfig\.local|gitconfig\.local\.example)' "private domains are not allowed" || return 1
  hygiene_grep '((AKIA|ASIA)[A-Z0-9]{16}|gh[pousr]_[A-Za-z0-9_]{36,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----)' "common secret formats are not allowed" || return 1
  hygiene_grep '(TODO|FIXME|TBD|REPLACE_ME|YOUR_|CHANGEME|<[^>]*(TODO|FIXME|REPLACE|YOUR|CHANGEME)[^>]*>)' "unresolved template markers are not allowed" || return 1
  hygiene_grep_filtered '\{\{[^}]+\}\}' '\$\{\{' "unresolved template markers are not allowed" || return 1
  hygiene_grep '(^|[^A-Za-z])((git|ssh)://|http://|git@)' "non-HTTPS remote URLs are not allowed"
}

test_hygiene_markdown_relative_links_resolve() {
  hygiene_markdown_links
}
