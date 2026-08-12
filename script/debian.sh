#!/usr/bin/env bash

debian_package_installed() {
  package_name="$1"

  package_status="$(dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null)" || return 1
  [ "${package_status}" = "install ok installed" ]
}

debian_plan_package_record() {
  package_name="$1"

  if debian_package_installed "${package_name}"; then
    return 0
  fi

  plan_append packages install "apt ${package_name}"
}

debian_plan_packages() {
  manifest_path="$1"

  manifest_each debian "${manifest_path}" debian_plan_package_record
}

debian_plan_contains() {
  detail="$1"

  if [ -z "${DOTFILES_PLAN_FILE:-}" ] || [ ! -f "${DOTFILES_PLAN_FILE}" ]; then
    return 1
  fi

  grep -F -x -- "packages	install	${detail}" "${DOTFILES_PLAN_FILE}" >/dev/null 2>&1
}

debian_collect_planned_package() {
  package_name="$1"

  if ! debian_plan_contains "apt ${package_name}"; then
    return 0
  fi

  if [ -z "${debian_planned_packages:-}" ]; then
    debian_planned_packages="${package_name}"
  else
    debian_planned_packages="${debian_planned_packages} ${package_name}"
  fi
}

debian_install_packages() {
  manifest_path="$1"
  debian_planned_packages=""

  manifest_each debian "${manifest_path}" debian_collect_planned_package || return 1

  if [ -z "${debian_planned_packages}" ]; then
    return 0
  fi

  sudo apt-get update || return "$?"
  # shellcheck disable=SC2086
  sudo apt-get install -y ${debian_planned_packages}
}
