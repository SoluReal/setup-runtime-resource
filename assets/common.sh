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

# Single source of truth for "is this runtime in source", shared by the runtime scripts and the group hook.
function runtime_wanted() {
  case "$1" in
    sdkman) [[ -n "$java_version" || -n "$maven_version" || -n "$gradle_version" || "$sdkman_enabled" = "true" ]] ;;
    nvm) [[ -n "$nodejs_version" || "$nvm_enabled" = "true" ]] ;;
    node) [[ -n "$nodejs_version" ]] ;;
    pyenv) [[ "$pyenv_enabled" = "true" ]] ;;
    golang) [[ -n "$golang_version" ]] ;;
    *) return 1 ;;
  esac
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
    pyenv) printf '\033[0;33m' ;;
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
  local progress_message=$1
  local finished_message=$2
  local pid=$3
  local delay=0.05
  local spin='|/-\'
  local status

  if [ "$SETUP_PARALLEL" = "true" ]; then
    local started=$SECONDS
    group_event "▶" "$Green" "$progress_message"
    status=0
    wait "$pid" || status=$?
    if [ $status -eq 0 ]; then
      group_event "✔" "$Green" "$finished_message" "$(format_elapsed $((SECONDS - started)))"
    else
      group_event "✘" "$Red" "failed: $progress_message" "$(format_elapsed $((SECONDS - started)))"
    fi
  elif [ "$VERBOSE" = "true" ]; then
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
