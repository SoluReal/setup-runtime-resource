#!/bin/bash

function prepare_pyenv_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -d "$RUNTIME_DIR/pyenv/versions" ]]; then
    info "Saving pyenv versions to cache..."
    mkdir -p "$CACHE_DIRECTORY/pyenv"
    tar -I lz4 -cf "$CACHE_DIRECTORY/pyenv/archive.tar.lz4" -C "$RUNTIME_DIR/pyenv" versions
  fi
}

function restore_pyenv_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -f "$CACHE_DIRECTORY/pyenv/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
    info "Restoring pyenv versions from cache..."
    restore_lz4_cache "$CACHE_DIRECTORY/pyenv/archive.tar.lz4" "$RUNTIME_DIR/pyenv"
  fi
}

register_initialize_callback restore_pyenv_cache
register_teardown_callback prepare_pyenv_cache
