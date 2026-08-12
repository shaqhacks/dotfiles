#!/usr/bin/env bash

plugins_root() {
  data_root="$1"
  printf '%s/plugins' "${data_root}"
}

plugin_path() {
  data_root="$1"
  plugin_name="$2"

  printf '%s/%s' "$(plugins_root "${data_root}")" "${plugin_name}"
}

plugin_git_origin() {
  checkout="$1"

  git -C "${checkout}" config --get remote.origin.url
}

plugin_git_commit() {
  checkout="$1"

  git -C "${checkout}" rev-parse HEAD
}

plugin_git_clean() {
  checkout="$1"

  [ -z "$(git -C "${checkout}" status --porcelain)" ]
}

plugin_validate_checkout() {
  checkout="$1"
  plugin_name="$2"
  expected_origin="$3"

  if [ ! -d "${checkout}" ]; then
    return 0
  fi
  if ! git -C "${checkout}" rev-parse --git-dir >/dev/null 2>&1; then
    error "plugin checkout is not a git repository: ${plugin_name}"
    return 1
  fi

  current_origin="$(plugin_git_origin "${checkout}")" || {
    error "plugin origin is unavailable: ${plugin_name}"
    return 1
  }
  if [ "${current_origin}" != "${expected_origin}" ]; then
    error "plugin origin mismatch for ${plugin_name}: ${current_origin}"
    return 1
  fi
  if ! plugin_git_clean "${checkout}"; then
    error "plugin checkout is dirty: ${plugin_name}"
    return 1
  fi
}

plugins_plan_record() {
  plugin_name="$1"
  plugin_url="$2"
  commit_id="$3"
  checkout="$(plugin_path "${PLUGINS_DATA_ROOT}" "${plugin_name}")"

  plugin_validate_checkout "${checkout}" "${plugin_name}" "${plugin_url}" || return 1

  if [ ! -d "${checkout}" ]; then
    plan_append plugins clone "${plugin_name}"
    return "$?"
  fi

  current_commit="$(plugin_git_commit "${checkout}")" || return 1
  if [ "${current_commit}" = "${commit_id}" ]; then
    plan_append plugins noop "${plugin_name}"
  else
    plan_append plugins update "${plugin_name}"
  fi
}

plugins_plan() {
  plugins_manifest="$1"
  PLUGINS_DATA_ROOT="$2"

  manifest_each plugins "${plugins_manifest}" plugins_plan_record
}

plugins_cleanup_temp() {
  if [ -n "${PLUGINS_TEMP_CHECKOUT:-}" ]; then
    rm -rf "${PLUGINS_TEMP_CHECKOUT}"
  fi
}

plugins_clone_record() {
  plugin_name="$1"
  plugin_url="$2"
  commit_id="$3"
  entrypoint="$4"
  plugins_dir="$(plugins_root "${PLUGINS_DATA_ROOT}")"
  checkout="$(plugin_path "${PLUGINS_DATA_ROOT}" "${plugin_name}")"

  if [ -d "${checkout}" ]; then
    return 0
  fi

  mkdir -p "${plugins_dir}" || return 1
  PLUGINS_TEMP_CHECKOUT="$(mktemp -d "${plugins_dir}/.${plugin_name}.tmp.XXXXXX")" || return 1
  trap plugins_cleanup_temp RETURN

  git clone "${plugin_url}" "${PLUGINS_TEMP_CHECKOUT}" || {
    trap - RETURN
    plugins_cleanup_temp
    PLUGINS_TEMP_CHECKOUT=""
    return 1
  }
  git -C "${PLUGINS_TEMP_CHECKOUT}" fetch --depth 1 origin "${commit_id}" || {
    trap - RETURN
    plugins_cleanup_temp
    PLUGINS_TEMP_CHECKOUT=""
    return 1
  }
  git -C "${PLUGINS_TEMP_CHECKOUT}" checkout --detach "${commit_id}" || {
    trap - RETURN
    plugins_cleanup_temp
    PLUGINS_TEMP_CHECKOUT=""
    return 1
  }

  if [ ! -f "${PLUGINS_TEMP_CHECKOUT}/${entrypoint}" ]; then
    error "plugin entrypoint is missing after clone: ${plugin_name}/${entrypoint}"
    trap - RETURN
    plugins_cleanup_temp
    PLUGINS_TEMP_CHECKOUT=""
    return 1
  fi

  mv "${PLUGINS_TEMP_CHECKOUT}" "${checkout}" || {
    trap - RETURN
    plugins_cleanup_temp
    PLUGINS_TEMP_CHECKOUT=""
    return 1
  }
  PLUGINS_TEMP_CHECKOUT=""
  trap - RETURN
}

plugins_apply_record() {
  plugin_name="$1"
  plugin_url="$2"
  commit_id="$3"
  entrypoint="$4"
  checkout="$(plugin_path "${PLUGINS_DATA_ROOT}" "${plugin_name}")"

  if [ ! -d "${checkout}" ]; then
    plugins_clone_record "${plugin_name}" "${plugin_url}" "${commit_id}" "${entrypoint}"
    return "$?"
  fi

  plugin_validate_checkout "${checkout}" "${plugin_name}" "${plugin_url}" || return 1
  current_commit="$(plugin_git_commit "${checkout}")" || return 1
  if [ "${current_commit}" = "${commit_id}" ]; then
    return 0
  fi

  git -C "${checkout}" fetch --depth 1 origin "${commit_id}" || return 1
  git -C "${checkout}" checkout --detach "${commit_id}" || return 1
  if [ ! -f "${checkout}/${entrypoint}" ]; then
    error "plugin entrypoint is missing after checkout: ${plugin_name}/${entrypoint}"
    return 1
  fi
}

plugins_apply() {
  plugins_manifest="$1"
  PLUGINS_DATA_ROOT="$2"

  manifest_each plugins "${plugins_manifest}" plugins_apply_record
}
