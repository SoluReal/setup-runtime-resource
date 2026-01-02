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
fi

export NVM_DIR="$chroot_dir$NVM_RUNTIME_DIR"
if [ -d "$NVM_DIR" ]; then
    source "$NVM_DIR/nvm.sh"

    nvm cache clear
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
