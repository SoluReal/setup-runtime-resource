#!/bin/bash

set -e

if [[ -d $SDKMAN_DIR ]]; then
    source $SDKMAN_DIR/bin/sdkman-init.sh

    sdk flush archives
    sdk flush temp
    sdk flush broadcast
fi
