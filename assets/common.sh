#!/bin/bash

# Reset
Color_Off='\033[0m' # Text Reset

# To print to console with colors
Red='\033[0;31m'    # Red
Green='\033[0;32m'  # Green

export RUNTIME_DIR="/var/runtimes"
export SDKMAN_RUNTIME_DIR="$RUNTIME_DIR/sdkman"
export NVM_RUNTIME_DIR="$RUNTIME_DIR/nvm"
export COREPACK_HOME_DIR="$RUNTIME_DIR/corepack"
export RUNTIME_USER="runtime"

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

chroot_exec() {
    local rootfs="${1}"
    shift
    local cmd="$*"
    # Use fakechroot to simulate chroot
    fakechroot chroot "$rootfs" /bin/bash -lc "source /root/.bashrc; $cmd"
}

function set_env() {
  local env_line="${1}"

  touch /tmp/env_vars
  echo "$env_line" >> /tmp/env_vars
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
