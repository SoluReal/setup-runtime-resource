#!/bin/bash

function node_get_dependencies() {
    if [[ -n "$nodejs_version" || "$nvm_enabled" = "true" ]]; then
      BONUS=""
      if [[ "$nvm_enabled" = "true" ]]; then
        # curl is needed for nvm on runtime
        BONUS="curl"
      fi
      echo "ca-certificates libstdc++6 build-essential $BONUS"
    else
      echo ""
    fi
}
