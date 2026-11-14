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

    # podman-docker's `docker` shim prints an "Emulate Docker CLI" notice on every call;
    # this file is the documented way to silence it.
    mkdir -p "$chroot_dir/etc/containers"
    touch "$chroot_dir/etc/containers/nodocker"
  fi
fi
