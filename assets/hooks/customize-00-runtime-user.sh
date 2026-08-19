#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR"/common.sh

# Tasks run as this user (metadata.json sets `user`), so it must exist in
# every rootfs, not just the rootless testcontainers one.
#
# Written directly rather than via useradd: useradd auto-assigns subuid/subgid
# ranges that collide with the explicit ones below, making newuidmap fail.
echo "$RUNTIME_USER:x:$RUNTIME_UID:$RUNTIME_UID:runtime:$RUNTIME_HOME:/bin/bash" >> "$chroot_dir/etc/passwd"
echo "$RUNTIME_USER:!:19000:0:99999:7:::" >> "$chroot_dir/etc/shadow"
echo "$RUNTIME_USER:x:$RUNTIME_UID:" >> "$chroot_dir/etc/group"

# Only rootless podman uses these, but they're harmless otherwise.
echo "$RUNTIME_USER:100000:65536" >> "$chroot_dir/etc/subuid"
echo "$RUNTIME_USER:100000:65536" >> "$chroot_dir/etc/subgid"

mkdir -p "$chroot_dir$RUNTIME_HOME"
chown "$RUNTIME_UID:$RUNTIME_UID" "$chroot_dir$RUNTIME_HOME"
