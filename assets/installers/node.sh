#!/bin/bash

function node_get_dependencies() {
  # Only return dependencies if a node version is requested
    if [ -n "$nodejs_version" ]; then
      echo "ca-certificates libstdc++6 build-essential"
    else
      echo ""
    fi
}
