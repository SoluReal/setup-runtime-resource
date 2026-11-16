#!/bin/bash

function golang_get_dependencies() {
  if [[ -n "$golang_version" ]]; then
    echo "curl build-essential"
  else
    echo ""
  fi
}
