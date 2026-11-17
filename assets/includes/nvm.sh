#!/bin/bash

# Here rather than in bashrc.sh so an image without node never announces a `node/*` key.
if [[ "$ENABLE_CACHE" = "true" ]]; then
  export NPM_CONFIG_CACHE="$CACHE_DIRECTORY/npm"
  export YARN_CACHE_FOLDER="$CACHE_DIRECTORY/yarn"
  # pnpm ignores PNPM_STORE_PATH; it reads `store-dir` via npm config resolution.
  export npm_config_store_dir="$CACHE_DIRECTORY/pnpm"

  register_cache_dir node/npm "$NPM_CONFIG_CACHE"
  register_cache_dir node/yarn "$YARN_CACHE_FOLDER"
  register_cache_dir node/pnpm "$npm_config_store_dir"

  # nvm has no env var for its download cache; overriding works because bashrc.sh sources
  # plugins after nvm.sh. Not under $CACHE_DIRECTORY/nvm: remove_legacy_cache_layout wipes that.
  NVM_DOWNLOAD_CACHE="$CACHE_DIRECTORY/nvm-downloads"
  nvm_cache_dir() { printf '%s' "$NVM_DOWNLOAD_CACHE"; }
  register_cache_dir node/nvm "$NVM_DOWNLOAD_CACHE"
fi

# Corepack stays on the image path the `yarn`/`pnpm` versions were prepared into
# at build time, so they resolve without a download on a cold worker.
export COREPACK_HOME="$RUNTIME_DIR/corepack"

function prepare_node_cache_dirs() {
  [[ "$ENABLE_CACHE" = "true" ]] || return 0

  mkdir -p "$NPM_CONFIG_CACHE" "$YARN_CACHE_FOLDER" "$npm_config_store_dir" "$NVM_DOWNLOAD_CACHE"
}

register_initialize_callback prepare_node_cache_dirs
