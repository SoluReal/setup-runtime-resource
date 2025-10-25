#!/bin/bash

function gradle_install() {
  local ctr="${1}"
  local config="${2}"
  gradle_version=$(jq -r '(.source.gradle.version // "")' <<< "$config")

  if [ -n "$gradle_version" ]; then
    info "installing gradle: $gradle_version..."
    log_on_error buildah run "$ctr" -- bash -lc "sdk install gradle $gradle_version && sdk use gradle $gradle_version"
    info "gradle installed"
  fi
}
