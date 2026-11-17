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
    add_task_env_var "TESTCONTAINERS_ROOTLESS=true"

    # Wolfi has no podman-docker, so `docker` is a link to podman. Podman prints an
    # "Emulate Docker CLI" notice for it unless /etc/containers/nodocker exists.
    ln -sf podman "$chroot_dir/usr/bin/docker"
    mkdir -p "$chroot_dir/etc/containers"
    touch "$chroot_dir/etc/containers/nodocker"
    # pasta is not packaged in Wolfi.
    printf '[network]\ndefault_rootless_network_cmd = "slirp4netns"\n' > "$chroot_dir/etc/containers/containers.conf"
  fi
fi
