#!/bin/bash

function prepare_sdkman_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -d "$RUNTIME_DIR/sdkman/candidates" ]]; then
    info "Saving sdkman candidates to cache..."
    mkdir -p "$CACHE_DIRECTORY/sdkman"
    tar -I lz4 -cf "$CACHE_DIRECTORY/sdkman/archive.tar.lz4" -C "$RUNTIME_DIR/sdkman/" candidates
  fi
}

function restore_sdkman_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -f "$CACHE_DIRECTORY/sdkman/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
    info "Restoring sdkman candidates from cache..."
    mkdir -p "$RUNTIME_DIR/sdkman/candidates/"
    tar -I lz4 -xf "$CACHE_DIRECTORY/sdkman/archive.tar.lz4" -C "$RUNTIME_DIR/sdkman" candidates
  fi
}

register_initialize_callback restore_sdkman_cache
register_teardown_callback prepare_sdkman_cache

# SDKMAN only prepends a candidate to PATH while sourcing sdkman-init.sh, and
# only when that candidate's `current` symlink already exists. `sdk use` /
# `sdk env install` rewrite an sdkman entry that is already in PATH, but never
# add one (see __sdk_use in sdkman-use.sh). So a candidate that only appears
# later in the task - restored from the task cache above, or installed by
# `sdk env install` - gets its *_HOME exported but stays off PATH: `./gradlew`
# still works (JAVA_HOME), while `java`, `jar`, `native-image` or `mvn` fail
# with "command not found".
#
# Seeding the `current/bin` entries here fixes both cases: a PATH entry that
# does not exist yet is simply skipped during lookup until it does, and once it
# exists `sdk use` finds an entry to rewrite to the exact version.
function seed_sdkman_path() {
  local candidates_dir="${SDKMAN_CANDIDATES_DIR:-$RUNTIME_DIR/sdkman/candidates}"
  local candidate candidate_bin

  for candidate in "$@"; do
    candidate_bin="$candidates_dir/$candidate/current/bin"

    case ":$PATH:" in
      *":$candidate_bin:"*) ;;
      *) PATH="$candidate_bin:$PATH" ;;
    esac
  done

  export PATH
}

seed_sdkman_path java maven gradle
