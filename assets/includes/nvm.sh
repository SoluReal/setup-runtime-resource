#!/bin/bash

# The node package managers keep their stores in the task cache. This lives here
# rather than in bashrc.sh so that an image without node never configures them,
# never restores them, and never announces a `node/*` key it has no use for.
if [[ "$ENABLE_CACHE" = "true" ]]; then
  export NPM_CONFIG_CACHE="$CACHE_DIRECTORY/npm"
  export YARN_CACHE_FOLDER="$CACHE_DIRECTORY/yarn"
  # pnpm has no PNPM_STORE_PATH; it takes `store-dir` through npm's config
  # resolution, so the env spelling is the lowercase npm_config_ one. pnpm
  # appends its store version, giving $CACHE_DIRECTORY/pnpm/v3 - still under the
  # directory the `pnpm` cache key syncs. npm ignores the unknown key silently.
  export npm_config_store_dir="$CACHE_DIRECTORY/pnpm"

  register_cache_dir node/npm "$NPM_CONFIG_CACHE"
  register_cache_dir node/yarn "$YARN_CACHE_FOLDER"
  register_cache_dir node/pnpm "$npm_config_store_dir"
fi

# Corepack stays on the image path the `yarn`/`pnpm` versions were prepared into
# at build time, so they resolve without a download on a cold worker.
export COREPACK_HOME="$RUNTIME_DIR/corepack"

function prepare_node_cache_dirs() {
  [[ "$ENABLE_CACHE" = "true" ]] || return 0

  mkdir -p "$NPM_CONFIG_CACHE" "$YARN_CACHE_FOLDER" "$npm_config_store_dir"
}

register_initialize_callback prepare_node_cache_dirs
