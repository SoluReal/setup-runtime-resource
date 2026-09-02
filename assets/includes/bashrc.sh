# File is included in the bashrc file and is expected to be executed on task startup.

# Reset
export Color_Off='\033[0m' # Text Reset

# To print to console with colors
export Red='\033[0;31m'    # Red
export Green='\033[0;32m'  # Green
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

function cache_file_size() {
  local path="$1"
  [[ -e "$path" ]] || { echo 0; return 0; }
  du -sh "$path" 2>/dev/null | cut -f1
}

# The Concourse task cache already held this one, so no network tier was asked.
# Callers reach here on a non-empty directory, but a directory holding only empty
# subdirectories still counts zero files - and a cache reporting zero of
# something says nothing worth reading.
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

function cache_entry_count() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo 0; return 0; }
  ls -A "$dir" 2>/dev/null | wc -l | tr -d ' '
}

function cache_prune_incomplete() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -depth -name '*.incomplete' -exec rm -rf {} + 2>/dev/null || true
}

function cache_copy_missing() {
  local key="$1" src="$2" dst="$3" depth="$4"
  local copied=0 entry rel target scratch

  [[ -d "$src" ]] || { echo 0; return 0; }

  while IFS= read -r entry; do
    rel="${entry#"$src"/}"
    target="$dst/$rel"
    [[ -e "$target" || -L "$target" ]] && continue

    mkdir -p "$(dirname "$target")" || continue
    scratch="$target.incomplete"
    rm -rf "$scratch"

    # Preserve modes and symlinks, then publish the copy atomically.
    if cp -a "$entry" "$scratch" && mv "$scratch" "$target"; then
      copied=$((copied + 1))
    else
      rm -rf "$scratch"
      error "Could not copy $key/$rel - it will be reinstalled when something needs it"
    fi
  done < <(find "$src" -mindepth "$depth" -maxdepth "$depth" \
             \( -type d -o -type l \) ! -name '*.incomplete' 2>/dev/null)

  echo "$copied"
}

# Bring the task cache's versions into the runtime directory the image shipped.
#
# The runtime stays where it is and the cache is copied into it, rather than the
# runtime being pointed or linked at the cache volume. That costs a copy the
# first time a version is seen, and buys the property that the tool only ever
# writes the image's own filesystem: a cache that cannot be read - streamed from
# another worker, remounted under a different uid - costs a reinstall and says
# so, instead of leaving a runtime half-attached to a volume it cannot write.
#
#   cache_restore_runtime <key> <runtime-dir> <cache-dir> <unit> <depth> [count-dir] [after-fn]
function cache_restore_runtime() {
  local key="$1" runtime_dir="$2" cache_dir="$3" unit="$4" depth="$5"
  local count_dir="${6:-$runtime_dir}"
  local after_restore="${7:-}"

  mkdir -p "$cache_dir" "$runtime_dir"
  cache_prune_incomplete "$cache_dir"
  cache_prune_incomplete "$runtime_dir"

  # Record whether the cache already contained this runtime.
  local before
  before="$(cache_entry_count "$cache_dir")"

  cache_copy_missing "$key" "$cache_dir" "$runtime_dir" "$depth" >/dev/null

  # Clean up incomplete entries before counting the restored runtime.
  [[ -n "$after_restore" ]] && "$after_restore"

  local count
  count="$(cache_entry_count "$count_dir")"

  # Nothing to say when there was nothing to restore: an empty cache is the
  # normal state of a first build, and a line per key claiming zero of something
  # reads like a fault. The save event at teardown is what shows up instead.
  if (( count == 0 )); then
    return 0
  elif (( before > 0 )); then
    cache_event "restore $key from=local $unit=$count"
  else
    cache_event "restore $key from=rootfs $unit=$count"
  fi

  return 0
}

# The other half: hand back whatever this build installed. Only versions the
# cache does not already hold are copied, so the usual build writes nothing.
#
#   cache_save_runtime <key> <runtime-dir> <cache-dir> <unit> <depth>
function cache_save_runtime() {
  local key="$1" runtime_dir="$2" cache_dir="$3" unit="$4" depth="$5"

  [[ "$ENABLE_CACHE" = "true" ]] || return 0
  [[ -d "$runtime_dir" ]] || return 0

  mkdir -p "$cache_dir"

  local saved
  saved="$(cache_copy_missing "$key" "$runtime_dir" "$cache_dir" "$depth")"

  # Silent when nothing moved - which is the usual warm build, since a version
  # already in the cache is never copied again. A build logs what it moved and
  # nothing else.
  if (( saved > 0 )); then
    cache_event "save $key to=local $unit=$saved"
  fi

  return 0
}

# Empty $CACHE_DIRECTORY while keeping the directory itself, since Concourse
# owns the mount point. Only used when caching is switched off entirely - the
# runtimes keep their live state in here now, so this is not a pruning tool.
function clear_cache_directory() {
  if [[ ! -d "$CACHE_DIRECTORY" ]]; then
    return 0
  fi

  # Don't fail on this, you can receive Device or resource busy
  find "$CACHE_DIRECTORY" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
}

# Caches that need no per-tool logic: the whole directory is synced under one
# key, with the generic excludes below. Maven and Gradle are absent because they
# need the opposite of all of that - individual subdirectories under separate
# keys, tool-specific excludes, and cleanup after a partial restore - so they
# call s3cache_restore/s3cache_save themselves from their own plugins.
#
# Empty here on purpose. A plugin registers its own directories when it is
# installed, so a runtime that is not enabled has nothing to restore and never
# announces a key the image does not have - `register_directory_cache <name>`,
# called from the tool's include.
S3_DIR_CACHES=()

function register_directory_cache() {
  S3_DIR_CACHES+=("$1")
}

DIR_CACHE_EXCLUDES=(
  --exclude "**/tmp/**"
  --exclude "**/_locks/**"
  --exclude "**/*.lock"
)

function restore_directory_caches() {
  [[ "$ENABLE_CACHE" = "true" ]] || return 0

  local name dir
  for name in "${S3_DIR_CACHES[@]}"; do
    dir="$CACHE_DIRECTORY/$name"
    # Skip S3 when the local cache is warm.
    if [[ -n "$(ls -A "$dir" 2>/dev/null)" && "$S3_CACHE_ALWAYS_RESTORE" != "true" ]]; then
      cache_local_hit "node/$name" "$dir"
      continue
    fi
    s3cache_restore "$dir" "node/$name" "${DIR_CACHE_EXCLUDES[@]}" || true
  done

  for name in ${S3_CACHE_EXTRA_DIRS:-}; do
    dir="$CACHE_DIRECTORY/$name"
    if [[ -n "$(ls -A "$dir" 2>/dev/null)" && "$S3_CACHE_ALWAYS_RESTORE" != "true" ]]; then
      cache_local_hit "dir/$name" "$dir"
      continue
    fi
    s3cache_restore "$dir" "dir/$name" "${DIR_CACHE_EXCLUDES[@]}" || true
  done

  return 0
}

function save_directory_caches() {
  [[ "$ENABLE_CACHE" = "true" ]] || return 0

  local name
  for name in "${S3_DIR_CACHES[@]}"; do
    s3cache_save "$CACHE_DIRECTORY/$name" "node/$name" "${DIR_CACHE_EXCLUDES[@]}"
  done

  for name in ${S3_CACHE_EXTRA_DIRS:-}; do
    s3cache_save "$CACHE_DIRECTORY/$name" "dir/$name" "${DIR_CACHE_EXCLUDES[@]}"
  done

  return 0
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

# No-op fallbacks for the optional S3 cache tier.
function s3cache_restore() { return 2; }
function s3cache_save() { return 0; }
function s3cache_announce() { return 0; }

if [[ -d "$RUNTIME_DIR/plugins" ]]; then
  for f in "$RUNTIME_DIR"/plugins/*.sh; do
    [[ -f "$f" ]] && source "$f"
  done
fi

# Store the main pid so we can make sure that we only execute the traps on the main bash process.
if [[ ! -f /tmp/main_pid ]]; then
  echo $$ > /tmp/main_pid
fi

if [[ ! -f /tmp/runtime-prep-applied ]]; then
  touch /tmp/runtime-prep-applied

  if [[ "$ENABLE_CACHE" = "true" ]]; then
    mkdir -p "$CACHE_DIRECTORY"

    if [[ "$DEBUG" = "true" ]]; then
      info "Cache size in $CACHE_DIRECTORY:"
      info "$(du -sh "$CACHE_DIRECTORY" 2>/dev/null)" || true
    fi
  fi

  register_initialize_callback restore_directory_caches
  register_teardown_callback save_directory_caches

  # Announce the S3 tier once before running callbacks.
  s3cache_announce

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
