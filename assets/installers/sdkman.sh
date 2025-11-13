#!/bin/bash

function sdkman_get_dependencies() {
  local config="${1}"
  java_version=$(jq -r '(.source.java.version // "")' <<< "$config")
  gradle_version=$(jq -r '(.source.gradle.version // "")' <<< "$config")
  maven_version=$(jq -r '(.source.maven.version // "")' <<< "$config")

  if [[ -n "$java_version" || -n "$gradle_version" || -n "$maven_version" ]]; then
    echo "ca-certificates curl zip unzip"
  else
    echo ""
  fi
}

function sdkman_install() {
  local ctr="${1}"
  local config="${2}"
  java_version=$(jq -r '(.source.java.version // "")' <<< "$config")
  gradle_version=$(jq -r '(.source.gradle.version // "")' <<< "$config")
  maven_version=$(jq -r '(.source.maven.version // "")' <<< "$config")

  if [[ -n "$java_version" || -n "$gradle_version" || -n "$maven_version" ]]; then
    info "installing sdkman..."
    set_env "$ctr" "SDKMAN_DIR=$SDKMAN_DIR"
    log_on_error chroot_exec "$ctr" "
      curl -s 'https://get.sdkman.io?ci=true&rcupdate=false' | bash &&
      echo 'source $SDKMAN_DIR/bin/sdkman-init.sh' >> /root/.bashrc
      "
    info "sdkman installed"
  fi
}

function sdkman_cleanup() {
  local ctr="${1}"

  log_on_error chroot_exec "$ctr" "
    if [[ -d $SDKMAN_DIR ]]; then
        sdk flush archives &&
        sdk flush temp &&
        sdk flush broadcast

        echo 'SDKMAN_OFFLINE_MODE=true' >> /root/.bashrc
    fi"
}
