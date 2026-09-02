#!/bin/bash

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

# The versions directory stays in $RUNTIME_DIR and the task cache is copied in
# and out around the build - see sdkman.sh for why nothing is linked into the
# cache volume.
#
# versions/node/<version> is where the immutable directories are, so the copy
# looks two levels down. The count is taken one level deeper than the directory
# it syncs: versions/ only ever holds `node` (and `iojs`), so it is
# versions/node that says how many node versions are cached.
function restore_nvm_cache() {
  [[ "$ENABLE_CACHE" = "true" ]] || return 0

  cache_restore_runtime "nvm" \
    "$RUNTIME_DIR/nvm/versions" \
    "$CACHE_DIRECTORY/nvm/versions" \
    "versions" \
    2 \
    "$RUNTIME_DIR/nvm/versions/node" \
    prune_incomplete_nvm_versions
}

function save_nvm_cache() {
  cache_save_runtime "nvm" \
    "$RUNTIME_DIR/nvm/versions" \
    "$CACHE_DIRECTORY/nvm/versions" \
    "versions" \
    2
}

register_initialize_callback restore_nvm_cache
register_teardown_callback save_nvm_cache

# The node package managers keep their stores in the task cache. This lives here
# rather than in bashrc.sh so that an image without node never configures them,
# never restores them, and never announces a `node/*` key it has no use for.
if [[ "$ENABLE_CACHE" = "true" ]]; then
  export COREPACK_HOME="$CACHE_DIRECTORY/corepack"
  export NPM_CONFIG_CACHE="$CACHE_DIRECTORY/npm"
  export YARN_CACHE_FOLDER="$CACHE_DIRECTORY/yarn"
  export PNPM_STORE_PATH="$CACHE_DIRECTORY/pnpm"

  register_directory_cache npm
  register_directory_cache yarn
  register_directory_cache pnpm
fi

# Creating the directories is initialize-time work, not something to redo in
# every subshell that sources this plugin.
function prepare_node_cache_dirs() {
  [[ "$ENABLE_CACHE" = "true" ]] || return 0

  mkdir -p "$COREPACK_HOME" "$NPM_CONFIG_CACHE" "$YARN_CACHE_FOLDER" "$PNPM_STORE_PATH"

  # Keep image-provided package managers alongside cached versions.
  if [[ -d "$RUNTIME_DIR/corepack" ]]; then
    cp -r "$RUNTIME_DIR"/corepack/* "$COREPACK_HOME" 2>/dev/null || true
  fi

  return 0
}

register_initialize_callback prepare_node_cache_dirs
