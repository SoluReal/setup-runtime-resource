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
find $chroot_dir/home -maxdepth 3 -type d -name ".git" ! -path "./.git" -exec rm -rf {} +
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

# Leave apt.conf.d/00mmdebstrap and apt.conf.d/99debconf in place: mmdebstrap
# creates and unlinks these itself after all customize hooks run, and removing
# them here makes it warn "failed to unlink ...: No such file or directory".
find $chroot_dir/etc/apt -mindepth 1 -maxdepth 1 ! -name apt.conf.d -exec rm -rf {} +
find $chroot_dir/etc/apt/apt.conf.d -mindepth 1 ! -name 00mmdebstrap ! -name 99debconf -exec rm -rf {} +

# Don't need perl
rm -rf $chroot_dir/usr/share/perl*
rm -rf $chroot_dir/usr/lib/*-linux-gnu/perl*
rm -rf $chroot_dir/usr/bin/perl*
rm -rf $chroot_dir/usr/bin/debconf*
# shasum is a perl script, so removing perl above leaves it an orphan shasum
rm -rf $chroot_dir/usr/bin/shasum

log_info_hook "Cleanup finished"
