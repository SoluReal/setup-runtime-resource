#!/bin/bash

function sdkman_get_dependencies() {
  if [[ -n "$java_version" || -n "$maven_version" || -n "$gradle_version" || "$sdkman_enabled" = "true" ]]; then
    # lz4 is used for our own caching
    echo "curl zip unzip ca-certificates lz4"
  else
    echo ""
  fi
}
