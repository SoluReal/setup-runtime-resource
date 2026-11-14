#!/bin/bash

function node_get_dependencies() {
    if [[ -n "$nodejs_version" || "$nvm_enabled" = "true" ]]; then
      BONUS=""
      if [[ "$nvm_enabled" = "true" ]]; then
        # curl is needed for nvm on runtime
        BONUS="curl"
      fi
      [[ "$build_tools" != "false" ]] && BONUS="$BONUS build-essential"
      echo "libstdc++6 libatomic1 $BONUS"
    else
      echo ""
    fi
}
