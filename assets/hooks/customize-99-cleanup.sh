#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"
export SDKMAN_DIR="$chroot_dir$SDKMAN_RUNTIME_DIR"

log_info_hook "Cleaning up"
if [[ -d $SDKMAN_DIR ]]; then
    source "$SDKMAN_DIR/bin/sdkman-init.sh"

    set +e
    sdk flush archives
    sdk flush temp
    sdk flush broadcast
    set -e

    if [[ "$minimal_image" = "true" ]]; then
      # jmods (jlink-only) and src.zip (IDE source-attach only) are not needed to
      # compile or run Java/Gradle/Maven, and are large: strip them from every
      # installed JDK candidate to shrink the image.
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

find $chroot_dir/root -maxdepth 3 -type d -name ".git" ! -path "./.git" -exec rm -rf {} +
find $chroot_dir/var -maxdepth 3 -type d -name ".git" ! -path "./.git" -exec rm -rf {} +

# Remove apt lists and other temp files
rm -rf $chroot_dir/var/lib/apt/lists/*
rm -rf $chroot_dir/var/cache/apt/archives/*
rm -rf $chroot_dir/tmp/*

# Don't need apt anymore.
rm -rf $chroot_dir/var/lib/dpkg/*
rm -rf $chroot_dir/etc/dpkg/*
rm -rf $chroot_dir/usr/share/dpkg/*
rm -rf $chroot_dir/usr/libexec/dpkg
rm -rf $chroot_dir/etc/apt/*

# Don't need perl
rm -rf $chroot_dir/usr/share/perl*
rm -rf $chroot_dir/usr/lib/aarch64-linux-gnu/perl*
rm -rf $chroot_dir/usr/bin/perl*
rm -rf $chroot_dir/usr/bin/debconf*

log_info_hook "Cleanup finished"
