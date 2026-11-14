
export Color_Off='\033[0m'

export Red='\033[0;31m'
export Green='\033[0;32m'
export RUNTIME_DIR="/var/runtimes"
export RUNTIME_USER="runtime"
export RUNTIME_HOME="/home/$RUNTIME_USER"
# Concourse execs the task without a login shell, so HOME may be unset.
export HOME="${HOME:-$RUNTIME_HOME}"

function info() {
  printf "$Green%s$Color_Off\n" "$1"
}

function error() {
  printf "$Red%s$Color_Off\n" "$1" >&2
}

function cache_event() {
  printf "$Green[cache] %s$Color_Off\n" "$*"
}

function cache_file_count() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo 0; return 0; }
  find "$dir" -type f 2>/dev/null | wc -l | tr -d ' '
}

# A cache never reports zero of something, so a directory of only empty dirs logs nothing.
function cache_local_hit() {
  local files
  files="$(cache_file_count "$2")"
  if (( files > 0 )); then
    cache_event "restore $1 from=local files=$files"
  fi
}

declare -a TEARDOWN_CALLBACKS=()
declare -a ON_INITIALIZE_CALLBACKS=()

function register_teardown_callback() {
  TEARDOWN_CALLBACKS+=("$1")
}

function register_initialize_callback() {
  ON_INITIALIZE_CALLBACKS+=("$1")
}

# Empty $CACHE_DIRECTORY while keeping the directory itself, since Concourse
# owns the mount point. Only used when caching is switched off entirely.
function clear_cache_directory() {
  if [[ ! -d "$CACHE_DIRECTORY" ]]; then
    return 0
  fi

  # Don't fail on this, you can receive Device or resource busy
  find "$CACHE_DIRECTORY" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
}

# register_cache_dir <key> <dir>: each plugin registers its own keys, so an image without a
# tool never announces its key. Only used to log what the task cache already held.
CACHE_KEYS=()
declare -A CACHE_PATHS=()

function register_cache_dir() {
  CACHE_KEYS+=("$1")
  CACHE_PATHS["$1"]="$2"
}

function restore_cache_dirs() {
  [[ "$ENABLE_CACHE" = "true" ]] || return 0

  local key
  for key in "${CACHE_KEYS[@]}"; do
    cache_local_hit "$key" "${CACHE_PATHS[$key]}"
  done

  return 0
}

# In-place caches only grow, so MAX_CACHE_SIZE_MB is the one bound on worker disk.
function prune_oversized_cache() {
  [[ -n "${MAX_CACHE_SIZE_MB:-}" && -d "$CACHE_DIRECTORY" ]] || return 0
  if ! [[ "$MAX_CACHE_SIZE_MB" =~ ^[0-9]+$ ]]; then
    error "MAX_CACHE_SIZE_MB must be a whole number of megabytes, got '$MAX_CACHE_SIZE_MB'"
    return 1
  fi

  local size_mb
  size_mb=$(du -sm "$CACHE_DIRECTORY" | cut -f1)
  if (( size_mb > MAX_CACHE_SIZE_MB )); then
    info "Cache is ${size_mb} MB, above MAX_CACHE_SIZE_MB=$MAX_CACHE_SIZE_MB; clearing $CACHE_DIRECTORY"
    clear_cache_directory
  fi
}

# Remove legacy lz4 archives and tool dirs that now live in the rootfs.
function remove_legacy_cache_layout() {
  rm -rf "$CACHE_DIRECTORY"/gradle/archive.tar.lz4 "$CACHE_DIRECTORY"/maven/archive.tar.lz4 \
    "$CACHE_DIRECTORY"/sdkman "$CACHE_DIRECTORY"/nvm "$CACHE_DIRECTORY"/pyenv "$CACHE_DIRECTORY"/corepack
}

function teardown_setup_runtime() {
  if [[ "$ENABLE_CACHE" = "true" ]]; then
    if [[ ! -f /tmp/runtime-teardown-executed ]]; then
      touch /tmp/runtime-teardown-executed

      _pids=()
      for cb in "${TEARDOWN_CALLBACKS[@]}"; do
        if [[ "$DEBUG" = "true" ]]; then
          echo "Executing $cb"
        fi
        "$cb" &
        _pids+=($!)
      done
      for _pid in "${_pids[@]}"; do
        wait "$_pid"
      done
      unset _pids _pid

      prune_oversized_cache

      if [[ "$DEBUG" = "true" && -d "$CACHE_DIRECTORY" ]]; then
        info "Cache size in $CACHE_DIRECTORY:"
        info "$(du -sh "$CACHE_DIRECTORY" 2>/dev/null)" || true
      fi
    fi
  else
    clear_cache_directory
  fi
}

CACHE_DIR="${CACHE_DIR:-cache}"
export ENABLE_CACHE="${ENABLE_CACHE:-true}"
export CACHE_DIRECTORY="${CACHE_DIRECTORY:-$(pwd)/$CACHE_DIR}"
export CI=true

if [[ -d "$RUNTIME_DIR/plugins" ]]; then
  for f in "$RUNTIME_DIR"/plugins/*.sh; do
    [[ -f "$f" ]] && source "$f"
  done
fi

# Main pid, so traps run only in the main bash process.
if [[ ! -f /tmp/main_pid ]]; then
  echo $$ > /tmp/main_pid
fi

if [[ ! -f /tmp/runtime-prep-applied ]]; then
  touch /tmp/runtime-prep-applied

  if [[ "$ENABLE_CACHE" = "true" ]]; then
    mkdir -p "$CACHE_DIRECTORY"
    remove_legacy_cache_layout

    if [[ "$DEBUG" = "true" ]]; then
      info "Cache size in $CACHE_DIRECTORY:"
      info "$(du -sh "$CACHE_DIRECTORY" 2>/dev/null)" || true
    fi
  fi

  register_initialize_callback restore_cache_dirs

  # Callbacks run in parallel; `wait`'s exit status is the only signal that
  # one failed, and a failed runtime start must abort the task.
  _pids=()
  for cb in "${ON_INITIALIZE_CALLBACKS[@]}"; do
    "$cb" &
    _pids+=($!)
  done
  _failed=0
  for _pid in "${_pids[@]}"; do
    wait "$_pid" || _failed=1
  done
  unset _pids _pid
  if (( _failed )); then
    unset _failed
    error "A setup-runtime initialize callback failed - aborting."
    exit 1
  fi
  unset _failed

  if [[ "$PYENV_ENABLED" = "true" ]]; then
    eval "$(pyenv init - bash)"
  fi
fi
