#!/bin/bash

function prepare_nvm_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -d "$RUNTIME_DIR/nvm/versions" ]]; then
    info "Saving nvm versions to cache..."
    mkdir -p "$CACHE_DIRECTORY/nvm"
    tar -I lz4 -cf "$CACHE_DIRECTORY/nvm/archive.tar.lz4" -C "$RUNTIME_DIR/nvm" versions
  fi
}

# A cached node version can be incomplete (e.g. a prior run was killed mid-install)
function prune_incomplete_nvm_versions() {
  local versions_dir="$RUNTIME_DIR/nvm/versions/node"
  local version_dir

  [[ -d "$versions_dir" ]] || return 0

  for version_dir in "$versions_dir"/*/; do
    [[ -d "$version_dir" ]] || continue
    if [[ ! -x "$version_dir/bin/node" ]]; then
      error "Discarding incomplete cached node version $(basename "$version_dir")"
      rm -rf "$version_dir"
    fi
  done
}

function restore_nvm_cache() {
  if [[ "$ENABLE_CACHE" = "true" && -f "$CACHE_DIRECTORY/nvm/archive.tar.lz4" && "$LZ4_INSTALLED" = "true" ]]; then
    info "Restoring nvm versions from cache..."
    restore_lz4_cache "$CACHE_DIRECTORY/nvm/archive.tar.lz4" "$RUNTIME_DIR/nvm"
    prune_incomplete_nvm_versions
  fi
}

register_initialize_callback restore_nvm_cache
register_teardown_callback prepare_nvm_cache
