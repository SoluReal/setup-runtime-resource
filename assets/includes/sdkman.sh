#!/bin/bash

# The candidates directory stays where the image put it. The task cache is
# copied in at startup and whatever this build installed is copied back out at
# teardown, one candidate version at a time and only when a side is missing it.
# Nothing is linked or mounted into the cache volume, so `sdk install` always
# writes the image's own filesystem: an unreadable cache costs a reinstall and
# says so, rather than leaving SDKMAN attached to a volume it cannot write.
function sdkman_candidates_dir() { echo "$RUNTIME_DIR/sdkman/candidates"; }
function sdkman_cache_dir() { echo "$CACHE_DIRECTORY/sdkman/candidates"; }

# candidates/<candidate>/<version> - two levels down is where the immutable
# directories are, and where `current` sits as a symlink beside them.
function restore_sdkman_cache() {
  [[ "$ENABLE_CACHE" = "true" ]] || return 0

  cache_restore_runtime "sdkman" \
    "$(sdkman_candidates_dir)" \
    "$(sdkman_cache_dir)" \
    "candidates" \
    2
}

function save_sdkman_cache() {
  cache_save_runtime "sdkman" \
    "$(sdkman_candidates_dir)" \
    "$(sdkman_cache_dir)" \
    "candidates" \
    2
}

register_initialize_callback restore_sdkman_cache
register_teardown_callback save_sdkman_cache

# SDKMAN only puts a candidate on PATH while sourcing sdkman-init.sh, and only
# if its `current` symlink already exists. `sdk use` / `sdk env install` rewrite
# an sdkman PATH entry but never add one, so a candidate that appears later in
# the task (restored from cache, or installed by `sdk env install`) gets its
# *_HOME exported but stays off PATH. Seeding the `current/bin` entries up front
# fixes that: a non-existing PATH entry is skipped during lookup until it exists.
SDKMAN_CANDIDATES_DIR="$RUNTIME_DIR/sdkman/candidates"
export PATH="$SDKMAN_CANDIDATES_DIR/java/current/bin:$SDKMAN_CANDIDATES_DIR/maven/current/bin:$SDKMAN_CANDIDATES_DIR/gradle/current/bin:$PATH"
