#!/bin/bash

set -e
chroot_dir="$1"
source $ROOT_DIR/common.sh

log_info_hook "Cleaning up"
if [[ -d $SDKMAN_DIR ]]; then
    source $SDKMAN_DIR/bin/sdkman-init.sh

    sdk flush archives
    sdk flush temp
    sdk flush broadcast
fi

if [ -n "$nodejs_version" ]; then
    export NVM_DIR="$chroot_dir$NVM_RUNTIME_DIR"
    source $NVM_DIR/nvm.sh

    nvm cache clear
fi

find $chroot_dir/root -maxdepth 3 -type d -name ".git" ! -path "./.git" -exec rm -rf {} +
find $chroot_dir/var -maxdepth 3 -type d -name ".git" ! -path "./.git" -exec rm -rf {} +

log_info_hook "Cleanup finished"
