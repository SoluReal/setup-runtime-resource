#!/bin/bash

set -e
rootdir="$1"

if [[ -d $SDKMAN_DIR ]]; then
    source $SDKMAN_DIR/bin/sdkman-init.sh

    sdk flush archives
    sdk flush temp
    sdk flush broadcast
fi

if [ -n "$nodejs_version" ]; then
    export NVM_DIR="$rootdir$NVM_RUNTIME_DIR"
    source $NVM_DIR/nvm.sh

    nvm cache clear
fi

find $rootdir/root -maxdepth 3 -type d -name ".git" ! -path "./.git" -exec rm -rf {} +
find $rootdir/var -maxdepth 3 -type d -name ".git" ! -path "./.git" -exec rm -rf {} +
