#!/bin/bash

function sdkman_get_dependencies() {
  if [[ -n "$java_version"  ]]; then
    echo "curl zip unzip"
  else
    echo ""
  fi
}
