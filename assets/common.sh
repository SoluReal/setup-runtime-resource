#!/bin/bash

export Color_Off='\033[0m'

export Red='\033[0;31m'
export Green='\033[0;32m'

export RUNTIME_DIR="/var/runtimes"
export SDKMAN_RUNTIME_DIR="$RUNTIME_DIR/sdkman"
export NVM_RUNTIME_DIR="$RUNTIME_DIR/nvm"
export GOLANG_RUNTIME_DIR="$RUNTIME_DIR/golang"
export UV_RUNTIME_DIR="$RUNTIME_DIR/uv"
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

# Single source of truth for "is this runtime in source", shared by the runtime scripts and the group hook.
function runtime_is_requested_in_source() {
  case "$1" in
    sdkman) [[ -n "$java_version" || -n "$maven_version" || -n "$gradle_version" || "$sdkman_enabled" = "true" ]] ;;
    nvm) [[ -n "$nodejs_version" || "$nvm_enabled" = "true" ]] ;;
    node) [[ -n "$nodejs_version" ]] ;;
    python) [[ -n "$python_version" || "$uv_enabled" = "true" ]] ;;
    golang) [[ -n "$golang_version" ]] ;;
    *) return 1 ;;
  esac
}

# The Debian packages a requested runtime needs in the rootfs.
function runtime_dependencies() {
  runtime_is_requested_in_source "$1" || return 0
  case "$1" in
    sdkman) echo "curl zip unzip" ;;
    # nvm downloads node with curl when a task installs one itself.
    nvm) echo "libstdc++6 libatomic1 build-essential $([[ "$nvm_enabled" = "true" ]] && echo curl)" ;;
    golang) echo "curl build-essential" ;;
  esac
}

# Docker (not podman) needs real root in the task and Docker's own apt repository.
function testcontainers_uses_docker() {
  [[ "$testcontainers_enabled" = "true" && "$testcontainers_rootless" != "true" ]]
}

# 72 -> 1m12s
function format_elapsed() {
  local secs=$1
  if (( secs >= 60 )); then printf "%dm%02ds" $((secs / 60)) $((secs % 60)); else printf "%ds" "$secs"; fi
}

function group_color() {
  case "$1" in
    sdkman) printf '\033[0;36m' ;;
    node) printf '\033[0;35m' ;;
    golang) printf '\033[0;34m' ;;
    python) printf '\033[0;32m' ;;
    *) printf '\033[0;37m' ;;
  esac
}

# One printf per line: appends below PIPE_BUF are atomic, so parallel groups never interleave.
function group_event() {
  local symbol=$1 symbol_color=$2 msg=$3 elapsed=${4:-}
  local line
  [[ -z "$elapsed" ]] || msg=$(printf "%-38s %s" "$msg" "$elapsed")
  line=$(printf "%b[setup-runtime]%b %b%s%b %b%-7s%b %s" "$Green" "$Color_Off" "$symbol_color" "$symbol" \
    "$Color_Off" "$(group_color "$GROUP_NAME")" "$GROUP_NAME" "$Color_Off" "$msg")
  printf '%s\n' "$line" >> "$OUTPUT_FILE"
}

function info_spinner() {
  local progress_message=$1 finished_message=$2 pid=$3
  local started=$SECONDS status=0

  group_event "▶" "$Green" "$progress_message"
  wait "$pid" || status=$?
  if [ $status -eq 0 ]; then
    group_event "✔" "$Green" "$finished_message" "$(format_elapsed $((SECONDS - started)))"
  else
    group_event "✘" "$Red" "failed: $progress_message" "$(format_elapsed $((SECONDS - started)))"
  fi
  return $status
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

# State shared by `in` and its hooks lives in $STATE_DIR, a fresh directory per build.
function add_task_env_var() {
  echo "$1" >> "$STATE_DIR/env_vars"
}

function add_metadata() {
  jq -nc --arg name "$1" --arg value "$2" '{name: $name, value: $value}' >> "$STATE_DIR/metadata"
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
