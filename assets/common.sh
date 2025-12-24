#!/bin/bash

# Reset
export Color_Off='\033[0m' # Text Reset

# To print to console with colors
export Red='\033[0;31m'    # Red
export Green='\033[0;32m'  # Green

export RUNTIME_DIR="/var/runtimes"
export SDKMAN_RUNTIME_DIR="$RUNTIME_DIR/sdkman"
export NVM_RUNTIME_DIR="$RUNTIME_DIR/nvm"
export PYENV_RUNTIME_DIR="$RUNTIME_DIR/pyenv"
export GOLANG_RUNTIME_DIR="$RUNTIME_DIR/golang"
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

function log_info_hook() {
  printf "$Green[setup-runtime] %s$Color_Off\n" "$1" >> $OUTPUT_FILE
}

function info_spinner() {
  local progress_message=$1
  local finished_message=$2
  local pid=$3
  local delay=0.05
  local spin='|/-\'

  if [ "$VERBOSE" = "true" ]; then
    log_info_hook "$progress_message"
    wait $pid
    log_info_hook "$finished_message"
  else
    while kill -0 "$pid" 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r$Green[setup-runtime] %s [%c]$Color_Off" "$progress_message" "${spin:i:1}" >> $OUTPUT_FILE
            sleep $delay
        done
    done

    printf "\r$Green[setup-runtime] %s                                   $Color_Off\n" "$finished_message" >> $OUTPUT_FILE
  fi
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

function add_trap() {
  local trap_cmd="${1}"
  local trap_signal="${2:-EXIT}"

  touch "/tmp/traps_$trap_signal"
  echo "$trap_cmd" >> "/tmp/traps_$trap_signal"
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
