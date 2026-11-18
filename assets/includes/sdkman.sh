#!/bin/bash

# sdkman puts a candidate on PATH only if its `current` symlink exists at init, and `sdk use`
# never adds one; seeding current/bin up front works since missing PATH entries are skipped.
SDKMAN_CANDIDATES_DIR="$RUNTIME_DIR/sdkman/candidates"
export PATH="$SDKMAN_CANDIDATES_DIR/java/current/bin:$SDKMAN_CANDIDATES_DIR/maven/current/bin:$SDKMAN_CANDIDATES_DIR/gradle/current/bin:$PATH"

# sdkman repacks a JDK's tar.gz into a zip only to unzip it, so storing beats compressing (~15s per JDK).
# local -x exports ZIPOPT to sdk's zip and restores the caller's value on return.
if rename_function sdk __sdk_compressing; then
  function sdk() {
    local -x ZIPOPT=-0
    __sdk_compressing "$@"
  }
fi

# sdkman downloads every `sdk install` again and unzips only from $SDKMAN_DIR/tmp (in the rootfs), so its download
# keeps each archive in the cache and links it there. Overriding works because plugins are sourced after sdkman-init.
if [[ "$ENABLE_CACHE" = "true" ]] && rename_function __sdkman_download __sdkman_download_uncached; then
  SDKMAN_ARCHIVE_CACHE="$CACHE_DIRECTORY/sdkman-archives"
  # The download has passed sdkman's zip and checksum checks. The move crosses filesystems, so it copies under a
  # temporary name first: an interrupted copy must never sit in the cache as the archive.
  function __sdkman_download() {
    local archive="$SDKMAN_ARCHIVE_CACHE/$1-$2.zip"
    if [[ ! -f "$archive" ]]; then
      __sdkman_download_uncached "$@" || return
      mv -f "$SDKMAN_DIR/tmp/$1-$2.zip" "$archive.partial" && mv -f "$archive.partial" "$archive" || return
    fi
    ln -sf "$archive" "$SDKMAN_DIR/tmp/$1-$2.zip"
  }
  register_cache_dir sdkman/archives "$SDKMAN_ARCHIVE_CACHE"
  register_initialize_callback prepare_sdkman_cache_dir
fi

function prepare_sdkman_cache_dir() {
  mkdir -p "$SDKMAN_ARCHIVE_CACHE"
}
