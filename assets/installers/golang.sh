#!/bin/bash

function golang_get_dependencies() {
  if [[ -n "$golang_version" ]]; then
    local tools=""
    [[ "$build_tools" != "false" ]] && tools="build-essential"
    echo "curl $tools"
  else
    echo ""
  fi
}
