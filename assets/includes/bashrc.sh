# File is included in the bashrc file and is expected to be executed on task startup.

# Reset
export Color_Off='\033[0m' # Text Reset

# To print to console with colors
export Red='\033[0;31m'    # Red
export Green='\033[0;32m'  # Green
export RUNTIME_DIR="/var/runtimes"

function info() {
  printf "$Green%s$Color_Off\n" "$1"
}

function error() {
  printf "$Red%s$Color_Off\n" "$1" >&2
}

declare -a TEARDOWN_CALLBACKS=()
declare -a ON_INITIALIZE_CALLBACKS=()

function register_teardown_callback() {
  TEARDOWN_CALLBACKS+=("$1")
}

function register_initialize_callback() {
  ON_INITIALIZE_CALLBACKS+=("$1")
}

CACHE_DIR="${CACHE_DIR:-cache}"
export ENABLE_CACHE="${ENABLE_CACHE:-true}"
export CACHE_DIRECTORY="$(pwd)/$CACHE_DIR"
export CI=true

if [[ -d "$RUNTIME_DIR/plugins" ]]; then
  for f in "$RUNTIME_DIR"/plugins/*.sh; do
    source "$f"
  done
fi

# Store the main pid so we can make sure that we only execute the traps on the main bash process.
if [[ ! -f /tmp/main_pid ]]; then
  echo $$ > /tmp/main_pid
fi

unset BASH_ENV

if [[ ! -f /tmp/runtime-prep-applied ]]; then
  touch /tmp/runtime-prep-applied

  if [[ "$ENABLE_CACHE" = "true" ]]; then
    mkdir -p "$CACHE_DIRECTORY"

    if [[ "$DEBUG" = "true" ]]; then
      info "Cache size in $CACHE_DIRECTORY:"
      info "$(du -sh "$CACHE_DIRECTORY" 2>/dev/null)" || true
    fi
  fi

  # It is possible that cache exists but that e.g. sdkman is no longer requested in the setup-runtime source.
  # Then the cache restore will break if we don't check for the existence of lz4.
  if command -v lz4 >/dev/null 2>&1; then
    LZ4_INSTALLED=true
  else
    LZ4_INSTALLED=false
  fi

  export LZ4_INSTALLED

  for cb in "${ON_INITIALIZE_CALLBACKS[@]}"; do
    "$cb"
  done

  if [[ "$ENABLE_CACHE" = "true" ]]; then
    export COREPACK_HOME=$CACHE_DIRECTORY/corepack
    mkdir -p "$COREPACK_HOME"

    export NPM_CONFIG_CACHE=$CACHE_DIRECTORY/npm
    mkdir -p "$NPM_CONFIG_CACHE"

    export YARN_CACHE_FOLDER=$CACHE_DIRECTORY/yarn
    mkdir -p "$YARN_CACHE_FOLDER"

    export PNPM_STORE_PATH=$CACHE_DIRECTORY/pnpm
    mkdir -p "$PNPM_STORE_PATH"
  fi
fi

function teardown_setup_runtime() {
  if [[ "$ENABLE_CACHE" = "true" ]]; then
    if [[ ! -f /tmp/runtime-teardown-executed ]]; then
      touch /tmp/runtime-teardown-executed

      for cb in "${TEARDOWN_CALLBACKS[@]}"; do
        if [[ "$DEBUG" = "true" ]]; then
          echo "Executing $cb"
        fi
        "$cb"
      done

      if [[ ! -d "$CACHE_DIRECTORY" ]]; then
        return 0
      fi

      size_bytes=$(du -sb "$CACHE_DIRECTORY" | awk '{print $1}')

      if [[ -n "$MAX_CACHE_SIZE_MB" ]]; then
        local max_size=$(($MAX_CACHE_SIZE_MB * 1024 * 1024))

        if (( size_bytes > max_size )); then
          info "Cache size is $(du -sh "$CACHE_DIRECTORY" 2>/dev/null) which is above $MAX_CACHE_SIZE_MB MB. Cleaning up $CACHE_DIRECTORY..."
          rm -rf "$CACHE_DIRECTORY/*" || true
          info "Cleanup completed."
        fi
      fi

      if [[ "$DEBUG" = "true" ]]; then
        info "Cache size in $CACHE_DIR:"
        info "$(du -sh "$CACHE_DIRECTORY" 2>/dev/null)" || true
      fi
    fi
  else
    # Don't fail on this, you can receive Device or resource busy
    rm -rf "$CACHE_DIRECTORY/*" || true
  fi
}

if [[ "$PYENV_ENABLED" = "true" ]]; then
  eval "$(pyenv init - bash)"
fi
