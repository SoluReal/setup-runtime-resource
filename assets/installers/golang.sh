#!/bin/bash

function golang_get_dependencies() {
  if [[ -n "$golang_version" ]]; then
    echo "curl ca-certificates build-essential"
  else
    echo ""
  fi
}
