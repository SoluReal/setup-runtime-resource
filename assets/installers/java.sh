#!/bin/bash

function java_install() {
  local ctr="${1}"
  local config="${2}"
  java_version=$(jq -r '(.source.java.version // "")' <<< "$config")
  extra_versions=$(jq -r '(.source.java.extra_versions // [])' <<< "$config")

  if [[ -n "$java_version" ]]; then
    echo "$extra_versions" | jq '.[]' | while read -r version; do
      info "installing extra java candidate: $version..."
      log_on_error chroot_exec "$ctr" "sdk install java $version"
      info "extra java candidate installed: $version"
    done

    # Install default version
    if [[ "$java_version" =~ ^[0-9]+$ ]]; then
      # Use eclipse temurin as the default version
      # If Temurin doesn't work for you, specify the vendor yourself
      install_java="$java_version-tem"
    else
      install_java="$java_version"
    fi
    info "installing default java candidate: $install_java..."
    add_metadata "java" "$install_java"
    log_on_error chroot_exec "$ctr" "
      sdk install java $install_java &&
      sdk use java $install_java"
    info "default java candidate installed: $install_java"
  fi
}
