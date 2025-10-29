#!/bin/bash

# Reset
Color_Off='\033[0m' # Text Reset

# To print to console with colors
Red='\033[0;31m'    # Red
Green='\033[0;32m'  # Green

RUNTIME_DIR="/opt/runtimes"
SDKMAN_DIR="$RUNTIME_DIR/sdkman"
RUNTIME_USER="runtime"

# Compute a deterministic hash of the .source from stdin JSON
compute_hash() {
  local json="$1"
  echo "$json" | jq -c .source | sha256sum | awk '{print $1}'
}

function info() {
  printf "$Green[setup-runtime] %s$Color_Off\n" "$1"
}
function error() {
  printf "$Red[setup-runtime] %s$Color_Off\n" "$1" >&2
}

function set_env() {
  local ctr="${1}"
  local env="${2}"

  touch /tmp/env_vars
  echo $env >> /tmp/env_vars
  buildah config --env "$env" "$ctr"
}

function add_metadata() {
  local key="${1}"
  local value="${2}"

  touch /tmp/metadata
  echo "{\"name\": \"$key\", \"value\": \"$value\"}" >> /tmp/metadata
}

function log_on_error() {
  if [ "$VERBOSE" = "true" ]; then
    "$@"
  else
    local tmp
    tmp=$(mktemp)

    set +e
    "$@" >"$tmp" 2>&1
    local status=$?
    set -e

     if [ $status -ne 0 ]; then
        cat "$tmp"
        rm -f "$tmp"
        error "failed to setup-runtime. You can set verbose: true to enable more verbose logging."
        exit $status
      fi

    rm -f "$tmp"

    return $status
  fi
}
