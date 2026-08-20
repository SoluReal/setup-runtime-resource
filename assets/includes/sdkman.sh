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

# SDKMAN only puts a candidate on PATH while sourcing sdkman-init.sh, and only
# if its `current` symlink already exists. `sdk use` / `sdk env install` rewrite
# an sdkman PATH entry but never add one, so a candidate that appears later in
# the task (restored from cache, or installed by `sdk env install`) gets its
# *_HOME exported but stays off PATH. Seeding the `current/bin` entries up front
# fixes that: a non-existing PATH entry is skipped during lookup until it exists.
SDKMAN_CANDIDATES_DIR="$RUNTIME_DIR/sdkman/candidates"
export PATH="$SDKMAN_CANDIDATES_DIR/java/current/bin:$SDKMAN_CANDIDATES_DIR/maven/current/bin:$SDKMAN_CANDIDATES_DIR/gradle/current/bin:$PATH"
