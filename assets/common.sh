#!/bin/bash

export Color_Off='\033[0m'

export Red='\033[0;31m'
export Green='\033[0;32m'

export RUNTIME_DIR="/var/runtimes"
export SDKMAN_RUNTIME_DIR="$RUNTIME_DIR/sdkman"
export NVM_RUNTIME_DIR="$RUNTIME_DIR/nvm"
export PYENV_RUNTIME_DIR="$RUNTIME_DIR/pyenv"
export GOLANG_RUNTIME_DIR="$RUNTIME_DIR/golang"
export COREPACK_HOME_DIR="$RUNTIME_DIR/corepack"
export RUNTIME_USER="runtime"
export RUNTIME_UID=1000
export RUNTIME_HOME="/home/$RUNTIME_USER"

hash_source() {
  local json="$1"
  echo "$json" | jq -c .source | sha256sum | awk '{print $1}'
}

function info() {
  printf "$Green[setup-runtime] %s$Color_Off\n" "$1"
}

function info_to_output_file() {
  printf "$Green[setup-runtime] %s$Color_Off\n" "$1" >> $OUTPUT_FILE
}

function info_spinner() {
  local progress_message=$1
  local finished_message=$2
  local pid=$3
  local delay=0.05
  local spin='|/-\'
  local status

  if [ "$VERBOSE" = "true" ]; then
    info_to_output_file "$progress_message"
    wait "$pid"
    status=$?
    printf "\n" >> $OUTPUT_FILE
    info_to_output_file "$finished_message"
  else
    while kill -0 "$pid" 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r$Green[setup-runtime] %s [%c]$Color_Off" "$progress_message" "${spin:i:1}" >> "$OUTPUT_FILE"
            sleep $delay
        done
    done
    wait "$pid"
    status=$?

    printf "\r$Green[setup-runtime] %s                                   $Color_Off\n" "$finished_message" >> "$OUTPUT_FILE"
  fi

  return $status
}

# Greppable timing line: `[timing] <label> seconds=N`, N counted from $2 (a $SECONDS value, default shell start).
function timing_line() {
  [[ "${build_stats:-}" == true ]] || return 0
  printf '[timing] %s seconds=%s\n' "$1" "$(( SECONDS - ${2:-0} ))"
}

# Hooks are separate processes (SECONDS starts at 0), so an EXIT trap covers the whole hook.
function time_hook() {
  local name
  name=$(basename "$1" .sh)
  trap "timing_line hook=$name >> \"\$OUTPUT_FILE\"" EXIT
}

# `log_sizes <rootfs> <path>...`: one `[size] path=<path> kb=<n>` line per path that exists in the rootfs.
function log_sizes() {
  [[ "${build_stats:-}" == true ]] || return 0
  local root=$1 p
  shift
  for p in "$@"; do
    [[ -e "$root$p" ]] && printf '[size] path=%s kb=%s\n' "$p" "$(du -sk "$root$p" | cut -f1)"
  done
  return 0
}

function error() {
  printf "$Red[setup-runtime] %s$Color_Off\n" "$1" >&2
}

function curl_retry() {
  local max_retries="${dependency_download_retries:-0}"
  local retry_args=()

  if [[ "$max_retries" -gt 0 ]]; then
    retry_args=( --retry "$max_retries" --retry-all-errors )
  fi

  curl "${retry_args[@]}" "$@"
}
export -f curl_retry

# For installers that download without retrying themselves (sdk, nvm, corepack).
function retry() {
  local attempt=0
  until "$@"; do
    (( attempt++ < ${dependency_download_retries:-0} )) || return 1
    sleep 5
  done
}

chroot_exec() {
    local rootfs="${1}"
    shift
    local cmd="$*"
    fakechroot chroot "$rootfs" /bin/bash -lc "[[ -f $RUNTIME_HOME/.bashrc ]] && source $RUNTIME_HOME/.bashrc; $cmd"
}

function add_task_env_var() {
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
