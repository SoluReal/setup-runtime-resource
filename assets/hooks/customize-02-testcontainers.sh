#!/bin/bash

set -e

chroot_dir="$1"

if [[ "$testcontainers_enabled" = "true" ]]; then
  echo "source $RUNTIME_DIR/docker/docker.sh" >> $chroot_dir/root/.bashrc
fi
