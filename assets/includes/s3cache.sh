#!/bin/bash

# Second-tier cache backed by an S3-compatible object store.
# It is used when the local task cache is cold and must not fail a build.

S3_CACHE_REMOTE="s3cache"

function s3cache_marker_dir() {
  echo "$CACHE_DIRECTORY/.s3cache"
}

function s3cache_marker_path() {
  local key="$1"
  echo "$(s3cache_marker_dir)/$(echo "$key" | tr '/' '_').marker"
}

# Mark the cache state so the teardown check sees only files changed by the build.
function s3cache_touch_marker() {
  local marker
  marker="$(s3cache_marker_path "$1")"
  mkdir -p "$(dirname "$marker")"
  touch "$marker"
}

# Print why the tier is disabled, or nothing when it is enabled.
function s3cache_disabled_reason() {
  [[ "$ENABLE_CACHE" = "true" ]] || { echo "caching-disabled"; return 0; }
  [[ "$S3_CACHE_ENABLED" = "true" ]] || { echo "not-installed"; return 0; }
  [[ -n "$S3_CACHE_BUCKET" ]] || { echo "no-bucket"; return 0; }
  [[ -n "$S3_CACHE_ACCESS_KEY_ID" && -n "$S3_CACHE_SECRET_ACCESS_KEY" ]] || { echo "no-credentials"; return 0; }
  command -v rclone >/dev/null 2>&1 || { echo "no-rclone"; return 0; }
  echo ""
}

function s3cache_enabled() {
  [[ -z "$(s3cache_disabled_reason)" ]]
}

# Called once per task from bashrc, before any cache is touched.
function s3cache_announce() {
  local reason
  reason="$(s3cache_disabled_reason)"

  if [[ -n "$reason" ]]; then
    cache_event "tier s3=disabled reason=$reason"
    return 0
  fi

  cache_event "tier s3=enabled scope=${S3_CACHE_SCOPE:-default} bucket=$S3_CACHE_BUCKET"
}

# Configure rclone through environment variables so credentials stay off disk.
function s3cache_configure_remote() {
  # The remote is defined entirely by the RCLONE_CONFIG_S3CACHE_* variables
  # below, so there is no config file and rclone would open every build with
  #   NOTICE: Config file "~/.config/rclone/rclone.conf" not found - using defaults
  # An empty value is rclone's "use no config file" - nothing to create, nothing
  # to leave behind, and no $HOME to depend on.
  export RCLONE_CONFIG=""

  export RCLONE_CONFIG_S3CACHE_TYPE="s3"
  export RCLONE_CONFIG_S3CACHE_PROVIDER="${S3_CACHE_PROVIDER:-Other}"
  export RCLONE_CONFIG_S3CACHE_ACCESS_KEY_ID="$S3_CACHE_ACCESS_KEY_ID"
  export RCLONE_CONFIG_S3CACHE_SECRET_ACCESS_KEY="$S3_CACHE_SECRET_ACCESS_KEY"

  if [[ -n "$S3_CACHE_ENDPOINT" ]]; then
    export RCLONE_CONFIG_S3CACHE_ENDPOINT="$S3_CACHE_ENDPOINT"
  fi

  if [[ -n "$S3_CACHE_REGION" ]]; then
    export RCLONE_CONFIG_S3CACHE_REGION="$S3_CACHE_REGION"
  fi
}

# Scope the remote cache per pipeline. Task containers do not have BUILD_* metadata.
function s3cache_remote_path() {
  local key="$1"

  local scope_key="pipeline/${S3_CACHE_SCOPE:-default}"

  local prefix="${S3_CACHE_PREFIX:+${S3_CACHE_PREFIX}/}"
  echo "${S3_CACHE_REMOTE}:${S3_CACHE_BUCKET}/${prefix}${scope_key}/${key}"
}

function s3cache_flags() {
  # Preserve metadata and avoid unnecessary listings and transfers.
  echo "--metadata --fast-list --size-only --transfers ${S3_CACHE_TRANSFERS:-12} --checkers ${S3_CACHE_TRANSFERS:-12} --retries 2 --low-level-retries 3 --stats-one-line --stats 30s"
}

# Convert the upload exclusions into predicates for the local dirty check.
function s3cache_find_excludes() {
  local -a predicates=()
  local pattern

  while (( $# )); do
    if [[ "$1" != "--exclude" || -z "${2:-}" ]]; then
      shift
      continue
    fi

    pattern="${2#\*\*/}"
    if [[ "$pattern" == */\*\* ]]; then
      predicates+=( ! -path "*/${pattern%/\*\*}/*" )
    else
      predicates+=( ! -name "$pattern" )
    fi
    shift 2
  done

  (( ${#predicates[@]} )) || return 0
  printf '%s\n' "${predicates[@]}"
}

# s3cache_restore <local-dir> <cache-key> [extra rclone args...]
#
# Exit codes, which callers must distinguish:
#   0  the local directory now holds a complete copy of the remote cache
#   1  a restore ran but failed or was cut short - the directory may be partial
#   2  nothing was attempted (tier disabled/unconfigured); the directory is
#      untouched, so whatever the local tier put there is still valid
# Callers that can't tolerate a partially populated directory must clean up on 1
# only - treating 2 the same way would discard a good local restore.
function s3cache_restore() {
  local local_dir="$1"
  local key="$2"
  shift 2

  # Silent: the `tier s3=disabled reason=...` line already said why, once, up
  # front - repeating it per key would be the same fact eight more times.
  if ! s3cache_enabled; then
    return 2
  fi
  s3cache_configure_remote

  mkdir -p "$local_dir"
  info "Restoring $key from the S3 cache..."

  local flags
  read -r -a flags <<< "$(s3cache_flags)"

  local started=$SECONDS
  local rc=0
  rclone copy "$(s3cache_remote_path "$key")" "$local_dir" \
      "${flags[@]}" \
      --max-duration "${S3_CACHE_RESTORE_MAX_DURATION:-10m}" \
      "$@" || rc=$?

  # Count files after the transfer so the event reflects usable files.
  local files
  files="$(cache_file_count "$local_dir")"
  local elapsed=$(( SECONDS - started ))

  if (( rc != 0 )); then
    cache_event "restore $key from=s3 status=failed files=$files in=${elapsed}s"
    error "S3 cache restore for $key failed or timed out - continuing without it"
    return 1
  fi

  s3cache_touch_marker "$key"

  # rclone reports a missing remote key as success, so check the file count. A
  # key the bucket does not hold yet is the normal first build and says nothing.
  if (( files > 0 )); then
    cache_event "restore $key from=s3 files=$files in=${elapsed}s"
  fi

  return 0
}

# s3cache_save <local-dir> <cache-key> [extra rclone args...]
#
# Always returns 0 - a cache upload must never fail an otherwise green build.
function s3cache_save() {
  local local_dir="$1"
  local key="$2"
  shift 2

  s3cache_enabled || return 0
  [[ -d "$local_dir" ]] || return 0
  s3cache_configure_remote

  # Skip the remote listing when the local cache has not changed.
  local marker
  marker="$(s3cache_marker_path "$key")"
  local -a find_excludes=()
  mapfile -t find_excludes < <(s3cache_find_excludes "$@")
  # Silent: nothing changed, so there is nothing to report. A build only logs
  # what it moved.
  if [[ -f "$marker" ]] && [[ -z "$(find "$local_dir" -type f -newer "$marker" "${find_excludes[@]}" -print -quit 2>/dev/null)" ]]; then
    return 0
  fi

  info "Saving $key to the S3 cache..."

  local flags
  read -r -a flags <<< "$(s3cache_flags)"

  local started=$SECONDS

  # Bound uploads so a slow endpoint cannot hold up task teardown.
  if rclone copy "$local_dir" "$(s3cache_remote_path "$key")" \
      "${flags[@]}" \
      --max-duration "${S3_CACHE_SAVE_MAX_DURATION:-5m}" \
      "$@"; then
    s3cache_touch_marker "$key"
    cache_event "save $key to=s3 files=$(cache_file_count "$local_dir") in=$(( SECONDS - started ))s"
  else
    cache_event "save $key to=s3 status=failed in=$(( SECONDS - started ))s"
    error "S3 cache save for $key failed or timed out - partial upload kept, next build resumes it"
  fi

  return 0
}
