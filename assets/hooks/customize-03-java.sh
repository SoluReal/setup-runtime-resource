#!/bin/bash

set -e

rootdir="$1"

export SDKMAN_DIR="$rootdir$SDKMAN_RUNTIME_DIR"

if [[ -n "$java_version" ]]; then
  source $SDKMAN_DIR/bin/sdkman-init.sh

  echo "$extra_java_versions" | jq -r '.[]' | while read -r version; do
    sdk install java $version
  done

  # Install default version
  if [[ "$java_version" =~ ^[0-9]+$ ]]; then
    # Use eclipse temurin as the default version
    # If Temurin doesn't work for you, specify the vendor yourself
    install_java="$java_version-tem"
  else
    install_java="$java_version"
  fi
  sdk install java $install_java
  sdk use java $install_java
fi
