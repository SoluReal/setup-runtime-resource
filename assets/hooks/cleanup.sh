#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"
export SDKMAN_DIR="$chroot_dir$SDKMAN_RUNTIME_DIR"

info_to_output_file "Cleaning up"
if [[ -d $SDKMAN_DIR ]]; then
    source "$SDKMAN_DIR/bin/sdkman-init.sh"

    set +e
    sdk flush archives
    sdk flush temp
    sdk flush broadcast
    set -e

    if [[ "$minimal_image" = "true" ]]; then
      # jmods (jlink-only) and src.zip (IDE-only) are large and not needed to compile or run;
      # stripped to shrink the image.
      find "$SDKMAN_DIR/candidates/java" -mindepth 2 -maxdepth 2 -type d -name jmods -exec rm -rf {} + 2>/dev/null || true
      find "$SDKMAN_DIR/candidates/java" -mindepth 3 -maxdepth 3 -type f -name src.zip -delete 2>/dev/null || true
    fi
fi

export NVM_DIR="$chroot_dir$NVM_RUNTIME_DIR"
if [ -d "$NVM_DIR" ]; then
    source "$NVM_DIR/nvm.sh"

    nvm cache clear
fi

if [ -d "$chroot_dir$COREPACK_HOME_DIR" ]; then
  corepack cache clean
fi

rm -rf $chroot_dir/tmp/*

info_to_output_file "Cleanup finished"
