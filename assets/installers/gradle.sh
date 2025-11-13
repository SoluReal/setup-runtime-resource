#!/bin/bash

function gradle_install() {
  local ctr="${1}"
  local config="${2}"
  gradle_version=$(jq -r '(.source.gradle.version // "")' <<< "$config")

  set_env "$ctr" "GRADLE_USER_HOME=/cache/gradle && mkdir -p /cache/gradle"
  if [ -n "$gradle_version" ]; then
    info "installing gradle: $gradle_version..."
    log_on_error chroot_exec "$ctr" "sdk install gradle $gradle_version && sdk use gradle $gradle_version"

    add_metadata "gradle" "$gradle_version"

    info "gradle installed"
  fi
}
