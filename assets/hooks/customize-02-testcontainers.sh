#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source $ROOT_DIR/common.sh

if [[ "$testcontainers_enabled" = "true" ]]; then
  add_metadata "testcontainers" "$testcontainers_enabled"
  cp "$ROOT_DIR/includes/docker.sh" "$chroot_dir/$RUNTIME_DIR/plugins/docker.sh"
  cp -r "$ROOT_DIR/includes/docker" "$chroot_dir/$RUNTIME_DIR"

  if [[ "$testcontainers_rootless" = "true" ]]; then
    add_metadata "testcontainers-rootless" "true"
    set_env "TESTCONTAINERS_ROOTLESS=true"

    # The runtime user and its subuid/subgid ranges are created for every
    # rootfs in customize-00-runtime-user.sh, since tasks now run as that user
    # regardless of whether testcontainers is enabled.

    # podman-docker's `docker` shim prints "Emulate Docker CLI using podman..."
    # on every single call; this file is the documented way to silence it.
    mkdir -p "$chroot_dir/etc/containers"
    touch "$chroot_dir/etc/containers/nodocker"
  fi
fi
