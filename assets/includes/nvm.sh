#!/bin/bash

function prepare_nvm_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -d "$RUNTIME_DIR/nvm/versions" ]]; then
    info "Saving nvm versions to cache..."
    mkdir -p "$CACHE_DIRECTORY/nvm"
    tar -I lz4 -cf "$CACHE_DIRECTORY/nvm/archive.tar.lz4" -C "$RUNTIME_DIR/nvm" versions
  fi
}

function restore_nvm_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -f "$CACHE_DIRECTORY/nvm/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
    info "Restoring nvm versions from cache..."
    restore_lz4_cache "$CACHE_DIRECTORY/nvm/archive.tar.lz4" "$RUNTIME_DIR/nvm"
  fi
}

register_initialize_callback restore_nvm_cache
register_teardown_callback prepare_nvm_cache
