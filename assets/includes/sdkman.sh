#!/bin/bash

# sdkman puts a candidate on PATH only if its `current` symlink exists at init, and `sdk use`
# never adds one; seeding current/bin up front works since missing PATH entries are skipped.
SDKMAN_CANDIDATES_DIR="$RUNTIME_DIR/sdkman/candidates"
export PATH="$SDKMAN_CANDIDATES_DIR/java/current/bin:$SDKMAN_CANDIDATES_DIR/maven/current/bin:$SDKMAN_CANDIDATES_DIR/gradle/current/bin:$PATH"

# sdkman repacks a JDK's tar.gz into a zip only to unzip it, so storing beats compressing (~15s per JDK).
# local -x exports ZIPOPT to sdk's zip and restores the caller's value on return.
if declare -F sdk > /dev/null; then
  eval "$(declare -f sdk | sed '1s/sdk/__sdk_compressing/')"
  function sdk() {
    local -x ZIPOPT=-0
    __sdk_compressing "$@"
  }
fi

# sdkman downloads every `sdk install` again and unzips only from $SDKMAN_DIR/tmp (in the rootfs), so its download
# keeps each archive in the cache and links it there. Overriding works because plugins are sourced after sdkman-init.
if [[ "$ENABLE_CACHE" = "true" ]] && declare -F __sdkman_download > /dev/null; then
  SDKMAN_ARCHIVE_CACHE="$CACHE_DIRECTORY/sdkman-archives"
  eval "$(declare -f __sdkman_download | sed '1s/__sdkman_download/__sdkman_download_uncached/')"
  function __sdkman_download() {
    local archive="$SDKMAN_ARCHIVE_CACHE/$1-$2.zip"
    if [[ ! -f "$archive" ]]; then
      __sdkman_download_uncached "$@" || return
      mv -f "$SDKMAN_DIR/tmp/$1-$2.zip" "$archive" || return
    fi
    ln -sf "$archive" "$SDKMAN_DIR/tmp/$1-$2.zip"
  }
  register_cache_dir sdkman/archives "$SDKMAN_ARCHIVE_CACHE"
  register_initialize_callback prepare_sdkman_cache_dir
fi

function prepare_sdkman_cache_dir() {
  mkdir -p "$SDKMAN_ARCHIVE_CACHE"
}
