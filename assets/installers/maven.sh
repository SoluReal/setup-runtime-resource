#!/bin/bash

function maven_install() {
  local ctr="${1}"
  local config="${2}"
  maven_version=$(jq -r '(.source.maven.version // "")' <<< "$config")

  if [ -n "$maven_version" ]; then
    info "installing maven $maven_version..."
    log_on_error buildah run "$ctr" -- bash -lc "
      sdk install maven $maven_version &&
      sdk use maven $maven_version"
    log_on_error buildah run "$ctr" -- bash -lc "
      mkdir pi ~/.m2 &&
      touch ~/.m2/settings.xml &&
      echo '<settings><localRepository>/cache/maven</localRepository></settings>' > ~/.m2/settings.xml"
    info "maven installed"
  fi
}
