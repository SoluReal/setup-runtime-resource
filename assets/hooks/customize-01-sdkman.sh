#!/bin/bash

set -e

rootdir="$1"

export SDKMAN_DIR="$rootdir$SDKMAN_RUNTIME_DIR"

if [[ -n "$java_version" ]]; then
  curl -s 'https://get.sdkman.io?ci=true&rcupdate=false' | bash
  echo "export SDKMAN_DIR=$SDKMAN_RUNTIME_DIR; source $SDKMAN_RUNTIME_DIR/bin/sdkman-init.sh" >> $rootdir/root/.bashrc
fi
