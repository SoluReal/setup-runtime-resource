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
