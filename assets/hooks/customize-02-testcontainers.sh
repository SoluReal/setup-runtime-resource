#!/bin/bash

set -e

chroot_dir="$1"
source $ROOT_DIR/common.sh

if [[ "$testcontainers_enabled" = "true" ]]; then
  echo "source $RUNTIME_DIR/docker/docker.sh" >> $chroot_dir/root/.bashrc
  add_metadata "testcontainers" "$testcontainers_enabled"
  add_metadata "docker" "$(docker --version)"
fi
