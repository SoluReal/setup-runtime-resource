#!/bin/bash

function node_get_dependencies() {
    if [[ -n "$nodejs_version" || "$nvm_enabled" = "true" ]]; then
      echo "ca-certificates libstdc++6 build-essential"
    else
      echo ""
    fi
}
