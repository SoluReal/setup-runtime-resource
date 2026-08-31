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

    # aardvark-dns hardcodes port 53 by default. When Testcontainers creates
    # several networks concurrently, their aardvark-dns instances race to bind
    # 53; the loser leaves an incomplete network state, which later surfaces as
    # "netavark: remove aardvark entries: IO error: No such file or directory"
    # when that network is torn down. Moving DNS off 53 avoids the collision.
    # https://github.com/podman-container-tools/podman/discussions/14242
    cat >> "$chroot_dir/etc/containers/containers.conf" <<'EOF'
[network]
dns_bind_port = 5300
EOF
  fi
fi
