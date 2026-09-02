#!/bin/bash

# The versions directory stays in $RUNTIME_DIR and the task cache is copied in
# and out around the build - see sdkman.sh for why nothing is linked into the
# cache volume. This is the expensive one to lose: a pyenv version is compiled
# rather than downloaded.
#
# versions/<version>, so the immutable directories are one level down.
function restore_pyenv_cache() {
  [[ "$ENABLE_CACHE" = "true" ]] || return 0

  cache_restore_runtime "pyenv" \
    "$RUNTIME_DIR/pyenv/versions" \
    "$CACHE_DIRECTORY/pyenv/versions" \
    "versions" \
    1
}

function save_pyenv_cache() {
  cache_save_runtime "pyenv" \
    "$RUNTIME_DIR/pyenv/versions" \
    "$CACHE_DIRECTORY/pyenv/versions" \
    "versions" \
    1
}

register_initialize_callback restore_pyenv_cache
register_teardown_callback save_pyenv_cache
