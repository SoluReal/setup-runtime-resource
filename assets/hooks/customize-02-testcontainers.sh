#!/bin/bash

set -e

rootdir="$1"

if [[ "$testcontainers_enabled" = "true" ]]; then
  echo "source $RUNTIME_DIR/docker/docker.sh" >> $rootdir/root/.bashrc
fi
