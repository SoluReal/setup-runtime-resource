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

    # Rootless podman needs a real (non-root) user with its own subuid/subgid
    # range to map container UIDs into. Written directly rather than via
    # useradd since that would need to run inside the chroot.
    RUNTIME_UID=1000
    echo "$RUNTIME_USER:x:$RUNTIME_UID:$RUNTIME_UID:runtime:/home/$RUNTIME_USER:/bin/bash" >> "$chroot_dir/etc/passwd"
    echo "$RUNTIME_USER:!:19000:0:99999:7:::" >> "$chroot_dir/etc/shadow"
    echo "$RUNTIME_USER:x:$RUNTIME_UID:" >> "$chroot_dir/etc/group"
    echo "$RUNTIME_USER:100000:65536" >> "$chroot_dir/etc/subuid"
    echo "$RUNTIME_USER:100000:65536" >> "$chroot_dir/etc/subgid"

    mkdir -p "$chroot_dir/home/$RUNTIME_USER"
    chown "$RUNTIME_UID:$RUNTIME_UID" "$chroot_dir/home/$RUNTIME_USER"
  fi
fi
