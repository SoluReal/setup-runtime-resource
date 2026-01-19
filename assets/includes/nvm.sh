#!/bin/bash

function enable_nvm() {
  export NVM_DIR="$RUNTIME_DIR/nvm"
  export COREPACK_HOME="$RUNTIME_DIR/corepack"
  source "$NVM_DIR/nvm.sh"
}

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
    mkdir -p "$RUNTIME_DIR/nvm"
    tar -I lz4 -xf "$CACHE_DIRECTORY/nvm/archive.tar.lz4" -C "$RUNTIME_DIR/nvm"
  fi
}

register_initialize_callback enable_nvm
register_initialize_callback restore_nvm_cache
register_teardown_callback prepare_nvm_cache
